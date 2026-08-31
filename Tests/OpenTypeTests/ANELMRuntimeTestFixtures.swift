import Foundation

let syntheticANEModelVocabularySize = 262

func makeSyntheticQwen3Directory(
    dtype: String = "BF16",
    omitting omittedName: String? = nil
) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("utter-ane-model-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try writeSyntheticQwen3Config(to: directory)
    try writeSyntheticTokenizer(to: directory)
    try writeSyntheticTokenizerConfig(to: directory)

    let tensors: [(String, [Int])] = [
        ("model.embed_tokens.weight", [syntheticANEModelVocabularySize, 2]),
        ("model.norm.weight", [2]),
        ("model.layers.0.input_layernorm.weight", [2]),
        ("model.layers.0.post_attention_layernorm.weight", [2]),
        ("model.layers.0.self_attn.q_norm.weight", [2]),
        ("model.layers.0.self_attn.k_norm.weight", [2]),
        ("model.layers.0.self_attn.q_proj.weight", [2, 2]),
        ("model.layers.0.self_attn.k_proj.weight", [2, 2]),
        ("model.layers.0.self_attn.v_proj.weight", [2, 2]),
        ("model.layers.0.self_attn.o_proj.weight", [2, 2]),
        ("model.layers.0.mlp.gate_proj.weight", [3, 2]),
        ("model.layers.0.mlp.up_proj.weight", [3, 2]),
        ("model.layers.0.mlp.down_proj.weight", [2, 3]),
    ].filter { $0.0 != omittedName }

    var offset = 0
    var header: [String: Any] = [:]
    for (name, shape) in tensors {
        let byteCount = shape.reduce(1, *) * 2
        header[name] = [
            "dtype": dtype,
            "shape": shape,
            "data_offsets": [offset, offset + byteCount],
        ]
        offset += byteCount
    }
    var headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    headerData.append(contentsOf: repeatElement(0x20, count: (8 - headerData.count % 8) % 8))
    var headerLength = UInt64(headerData.count).littleEndian
    var file = withUnsafeBytes(of: &headerLength) { Data($0) }
    file.append(headerData)
    file.append(Data(repeating: 0, count: offset))
    try file.write(to: directory.appendingPathComponent("model.safetensors"))
    return directory
}

func writeSyntheticQwen3Config(
    to directory: URL,
    qHeads: Int = 1,
    kvHeads: Int = 1
) throws {
    let config: [String: Any] = [
        "model_type": "qwen3",
        "hidden_size": 2,
        "intermediate_size": 3,
        "num_hidden_layers": 1,
        "num_attention_heads": qHeads,
        "num_key_value_heads": kvHeads,
        "head_dim": 2,
        "vocab_size": syntheticANEModelVocabularySize,
        "max_position_embeddings": 16,
        "tie_word_embeddings": true,
    ]
    try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        .write(to: directory.appendingPathComponent("config.json"))
}

func rewriteSyntheticTokenizer(
    at directory: URL,
    mutate: (inout [String: Any]) -> Void
) throws {
    var tokenizer = syntheticTokenizer()
    mutate(&tokenizer)
    try writeJSON(tokenizer, to: directory.appendingPathComponent("tokenizer.json"))
}

func rewriteSyntheticTokenizerConfig(
    at directory: URL,
    mutate: (inout [String: Any]) -> Void
) throws {
    var config = syntheticTokenizerConfig()
    mutate(&config)
    try writeJSON(config, to: directory.appendingPathComponent("tokenizer_config.json"))
}

private func writeSyntheticTokenizer(to directory: URL) throws {
    try writeJSON(syntheticTokenizer(), to: directory.appendingPathComponent("tokenizer.json"))
}

private func writeSyntheticTokenizerConfig(to directory: URL) throws {
    try writeJSON(
        syntheticTokenizerConfig(),
        to: directory.appendingPathComponent("tokenizer_config.json")
    )
}

private func syntheticTokenizer() -> [String: Any] {
    var vocabulary = Dictionary(
        uniqueKeysWithValues: byteLevelAlphabet().enumerated().map { ($0.element, $0.offset) }
    )
    vocabulary["of"] = 256
    return [
        "version": "1.0",
        "added_tokens": [
            ["id": 257, "content": "<bos>", "special": true],
            ["id": 258, "content": "<pad>", "special": true],
            ["id": 259, "content": "<|im_start|>", "special": true],
            ["id": 260, "content": "<|im_end|>", "special": true],
            ["id": 261, "content": "<unk>", "special": true],
        ],
        "model": [
            "type": "BPE",
            "vocab": vocabulary,
            "merges": [["o", "f"]],
            "unk_token": "<unk>",
        ],
        "normalizer": ["type": "NFC"],
        "pre_tokenizer": [
            "type": "Sequence",
            "pretokenizers": [
                ["type": "Split", "pattern": ["String": " "], "invert": false],
                ["type": "ByteLevel", "add_prefix_space": false, "use_regex": false],
            ],
        ],
        "post_processor": ["type": "ByteLevel", "use_regex": false],
        "decoder": ["type": "ByteLevel", "use_regex": false],
    ]
}

private func syntheticTokenizerConfig() -> [String: Any] {
    [
        "tokenizer_class": "Qwen2Tokenizer",
        "bos_token": "<bos>",
        "eos_token": "<|im_end|>",
        "unk_token": "<unk>",
        "pad_token": "<pad>",
        "model_max_length": 128,
    ]
}

private func byteLevelAlphabet() -> [String] {
    var bytes = Array(33...126) + Array(161...172) + Array(174...255)
    var codePoints = bytes
    for byte in 0...255 where !bytes.contains(byte) {
        bytes.append(byte)
        codePoints.append(256 + codePoints.count - 188)
    }
    return codePoints.compactMap(UnicodeScalar.init).map(String.init)
}

private func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: url)
}
