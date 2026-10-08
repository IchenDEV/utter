import Foundation

package struct SpeechSelection: Equatable, Sendable {
    package let providerID: String
    package let type: SpeechEngineType
    package let model: String
    package let modelPath: String
    package let locale: String
    package let appKey: String
    package let accessKey: String
    package let resourceID: String

    package init(
        providerID: String, type: SpeechEngineType, model: String = "", modelPath: String = "",
        locale: String = "", appKey: String = "", accessKey: String = "", resourceID: String = ""
    ) {
        self.providerID = providerID
        self.type = type
        self.model = model
        self.modelPath = modelPath
        self.locale = locale
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceID = resourceID
    }
}

extension SpeechSelection {
    package init(settings: SettingsValues, modelPath: String = "", inputLanguage: InputLanguage? = nil, providerID: String? = nil) {
        let type = settings.speechEngine
        let model: String
        switch type {
        case .whisper: model = settings.whisperModel
        case .qwen3: model = settings.qwenASRModel
        default: model = type.asrModelID ?? ""
        }
        self.init(
            providerID: providerID ?? type.rawValue, type: type, model: model,
            modelPath: type == .qwen3 ? modelPath : "",
            locale: type == .apple ? (inputLanguage ?? settings.inputLanguage).localeIdentifier : "",
            appKey: type == .volc ? settings.volcAppKey : "",
            accessKey: type == .volc ? settings.volcAccessKey : "",
            resourceID: type == .volc ? settings.volcResourceId : ""
        )
    }
}
