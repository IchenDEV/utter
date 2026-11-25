import Darwin
import MLX
import MLXAudioCore
import MLXNN

package final class Audio8MlpTowerBlock: Module {
    @ModuleInfo(key: "norm") var norm: LayerNorm
    @ModuleInfo(key: "fc1") var fc1: Linear
    @ModuleInfo(key: "fc2") var fc2: Linear

    package init(dimensions: Int, intermediateDimensions: Int) {
        self._norm.wrappedValue = LayerNorm(dimensions: dimensions)
        self._fc1.wrappedValue = Linear(dimensions, intermediateDimensions)
        self._fc2.wrappedValue = Linear(intermediateDimensions, dimensions)
        super.init()
    }

    package func callAsFunction(_ x: MLXArray) -> MLXArray {
        fc2(gelu(fc1(norm(x)))) + x
    }
}

package final class Audio8MlpTower: Module {
    @ModuleInfo(key: "layers") var layers: [Audio8MlpTowerBlock]
    @ModuleInfo(key: "final_norm") var finalNorm: LayerNorm

    package init(dimensions: Int, layerCount: Int, intermediateDimensions: Int) {
        self._layers.wrappedValue = (0..<layerCount).map { _ in
            Audio8MlpTowerBlock(dimensions: dimensions, intermediateDimensions: intermediateDimensions)
        }
        self._finalNorm.wrappedValue = LayerNorm(dimensions: dimensions)
        super.init()
    }

    package func callAsFunction(_ x: MLXArray) -> MLXArray {
        var output = x
        for layer in layers {
            output = layer(output)
        }
        return finalNorm(output)
    }
}

package final class Audio8Projector: Module {
    @ModuleInfo var norm: LayerNorm
    @ModuleInfo var linear: Linear

    package init(inputDimensions: Int, outputDimensions: Int) {
        self._norm.wrappedValue = LayerNorm(dimensions: inputDimensions)
        self._linear.wrappedValue = Linear(inputDimensions, outputDimensions)
        super.init()
    }

    package func callAsFunction(_ x: MLXArray) -> MLXArray {
        linear(norm(x))
    }
}

package enum Audio8AudioAdapterMath {

    package static func periodicHannWindow(size: Int) -> MLXArray {
        precondition(size > 1)
        let denominator = Double(size)
        var values = [Float]()
        values.reserveCapacity(size)
        for index in 0..<size {
            let phase = 2.0 * Double.pi * Double(index) / denominator
            values.append(Float(0.5 * (1.0 - Darwin.cos(phase))))
        }
        return MLXArray(values)
    }

    package static func melSpectrogram(
        audio: MLXArray,
        sampleRate: Int,
        nFft: Int,
        hopLength: Int,
        melBins: Int
    ) -> MLXArray {
        let window = periodicHannWindow(size: nFft)
        var frames = MLXAudioCore.stft(
            audio: audio,
            window: window,
            nFft: nFft,
            hopLength: hopLength,
            padMode: .reflect
        )
        let keptFrames = max(1, frames.dim(0) - 1)
        frames = frames[0..<keptFrames]

        let magnitudes = MLX.abs(frames).square()
        eval(magnitudes)
        let filters = MLXAudioCore.melFilters(
            sampleRate: sampleRate,
            nFft: nFft,
            nMels: melBins,
            norm: "slaney",
            melScale: .slaney
        )
        var mel = matmul(magnitudes, filters)
        eval(mel)
        mel = MLX.maximum(mel, MLXArray(Float(1e-10)))
        mel = MLX.log10(mel)
        mel = MLX.maximum(mel, mel.max() - MLXArray(Float(8.0)))
        return (mel + MLXArray(Float(4.0))) / MLXArray(Float(4.0))
    }
    package static func adaptiveAveragePool1d(_ input: MLXArray, outputLength: Int) -> MLXArray {
        precondition(outputLength > 0)
        let inputLength = input.dim(0)
        precondition(inputLength > 0)
        let input32 = input.asType(.float32)
        let rows = (0..<outputLength).map { index in
            let start = index * inputLength / outputLength
            let end = ((index + 1) * inputLength + outputLength - 1) / outputLength
            return input32[start..<end].mean(axis: 0)
        }
        return stacked(rows, axis: 0).asType(input.dtype)
    }

    package static func mergeAudioFrames(
        features: MLXArray,
        audioTokenCount: Int
    ) throws -> MLXArray {
        adaptiveAveragePool1d(features, outputLength: audioTokenCount)
    }

}
