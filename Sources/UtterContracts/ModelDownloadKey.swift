import Foundation

package enum ModelDownloadKind: Hashable, Sendable {
    case whisper
    case llm
    case asr
}

package struct ModelDownloadKey: Hashable, Sendable {
    package let kind: ModelDownloadKind
    package let modelID: String

    package init(kind: ModelDownloadKind, modelID: String) { self.kind = kind; self.modelID = modelID }
}

