import MLX
import MLXLMCommon
import MLXNN

package final class Audio8Attention: Module {
    let scale: Float
    let numHeads: Int
    let numKeyValueHeads: Int
    let headDim: Int

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear
    let rope: RoPE

    package init(_ config: Audio8ASRConfiguration) {
        self.numHeads = config.numAttentionHeads
        self.numKeyValueHeads = config.numKeyValueHeads
        self.headDim = config.hiddenSize / config.numAttentionHeads
        self.scale = 1.0 / Float(self.headDim).squareRoot()
        self._qProj.wrappedValue = Linear(
            config.hiddenSize,
            config.numAttentionHeads * headDim,
            bias: true
        )
        self._kProj.wrappedValue = Linear(
            config.hiddenSize,
            config.numKeyValueHeads * headDim,
            bias: true
        )
        self._vProj.wrappedValue = Linear(
            config.hiddenSize,
            config.numKeyValueHeads * headDim,
            bias: true
        )
        self._oProj.wrappedValue = Linear(
            config.numAttentionHeads * headDim,
            config.hiddenSize,
            bias: false
        )
        // Transformers 4.57 Qwen2 applies rotary positions unconditionally; the checkpoint's use_rope flag is not consumed there.
        self.rope = RoPE(dimensions: headDim, traditional: false, base: config.ropeTheta)
        super.init()
    }

    package func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let (batch, length) = (x.dim(0), x.dim(1))
        var queries = qProj(x).reshaped(batch, length, numHeads, headDim).transposed(0, 2, 1, 3)
        var keys = kProj(x).reshaped(batch, length, numKeyValueHeads, headDim).transposed(0, 2, 1, 3)
        var values = vProj(x).reshaped(batch, length, numKeyValueHeads, headDim).transposed(0, 2, 1, 3)

        if let cache {
            queries = rope(queries, offset: cache.offset)
            keys = rope(keys, offset: cache.offset)
            (keys, values) = cache.update(keys: keys, values: values)
        } else {
            queries = rope(queries)
            keys = rope(keys)
        }

        let output = MLXFast.scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: scale,
            mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batch, length, -1)
        return oProj(output)
    }


}

package final class Audio8DecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: Audio8Attention
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm
    @ModuleInfo(key: "mlp") var mlp: Audio8MLP

    package init(_ config: Audio8ASRConfiguration) {
        self._attention.wrappedValue = Audio8Attention(config)
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._mlp.wrappedValue = Audio8MLP(config)
        super.init()
    }

    package func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        var output = x + attention(inputLayerNorm(x), mask: mask, cache: cache)
        output = output + mlp(postAttentionLayerNorm(output))
        return output
    }
}

package final class Audio8MLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    package init(_ config: Audio8ASRConfiguration) {
        self._gateProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: false)
        self._upProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: false)
        self._downProj.wrappedValue = Linear(config.intermediateSize, config.hiddenSize, bias: false)
        super.init()
    }

    package func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

package final class Audio8TextModel: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [Audio8DecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    package init(_ config: Audio8ASRConfiguration) {
        self._embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabSize, dimensions: config.hiddenSize)
        self._layers.wrappedValue = (0..<config.numHiddenLayers).map { _ in Audio8DecoderLayer(config) }
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }

    package func callAsFunction(inputsEmbeds: MLXArray, cache: [KVCache]?) -> MLXArray {
        var hidden = inputsEmbeds
        let mask = createAttentionMask(h: hidden, cache: cache?.first)
        for (index, layer) in layers.enumerated() {
            hidden = layer(hidden, mask: mask, cache: cache?[index])
        }
        return norm(hidden)
    }
}

package final class Audio8LanguageModel: Module {
    @ModuleInfo(key: "model") var model: Audio8TextModel

    package init(_ config: Audio8ASRConfiguration) {
        self._model.wrappedValue = Audio8TextModel(config)
        super.init()
    }

    package func callAsFunction(inputsEmbeds: MLXArray, cache: [KVCache]?) -> MLXArray {
        let hidden = model(inputsEmbeds: inputsEmbeds, cache: cache)
        return model.embedTokens.asLinear(hidden)
    }
}
