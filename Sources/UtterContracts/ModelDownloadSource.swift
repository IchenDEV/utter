package enum ModelDownloadSource: String, CaseIterable, Sendable {
    case huggingFace = "huggingface"
    case hfMirror = "hf-mirror"

    package var endpoint: String {
        switch self {
        case .huggingFace: "https://huggingface.co"
        case .hfMirror: "https://hf-mirror.com"
        }
    }

    package var displayName: String {
        switch self {
        case .huggingFace: L("model.source.huggingface")
        case .hfMirror: L("model.source.hf_mirror")
        }
    }

    // An explicit empty token prevents Hub clients from discovering saved credentials.
    package var hubTokenOverride: String? { self == .hfMirror ? "" : nil }
}
