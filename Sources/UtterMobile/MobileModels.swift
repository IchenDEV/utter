#if os(iOS)
import Foundation
import UtterContracts
import UtterModels
import UtterAppleSpeech

/// One downloadable model as the phone shows it: the same catalog the desktop app uses, judged against this device.
public struct MobileModel: Identifiable {
    public enum Kind { case speech, polish }
    public enum Tier: Int { case recommended = 0, standard, legacy }
    public enum Fit: Equatable { case ok, marginal(String), blocked(String) }
    public enum State: Equatable { case notDownloaded, downloading, preparing, downloaded, paused, failed(String) }

    public let id: String
    public let kind: Kind
    public let name: String
    public let detail: String
    public let family: String?
    public let tier: Tier
    public let fit: Fit
    /// Download size before the model is installed; the installed size afterwards.
    public let bytes: Int64
    public let progress: Double
    public let progressDetail: String
    public let state: State
    let engine: Engine

    enum Engine { case whisper, mlxSpeech, mlxText }

    public var isWhisper: Bool { engine == .whisper }
    public var downloaded: Bool { state == .downloaded }
    public var downloading: Bool { state == .downloading || state == .preparing }
    public var error: String? { if case .failed(let message) = state { return message }; return nil }
    public var canDownload: Bool {
        if case .blocked = fit { return false }
        return state == .notDownloaded || state == .paused || error != nil
    }
}

extension MobileController {
    public var libraryReady: Bool { runtime?.state == .ready }
    public var canChangeConfiguration: Bool { !status.isBusy && activation == nil && !disabling && !clearing && !applePreparing && modelMutation == nil }
    public var industryLexicon: String {
        get { UserDefaults.standard.string(forKey: "mobile.industry") ?? "general" }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "mobile.industry") }
    }
    public var recordingLimit: Int {
        get { let value = UserDefaults.standard.integer(forKey: "mobile.limit"); return [30, 60, 120].contains(value) ? value : 120 }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "mobile.limit") }
    }
    public var audioSensitivity: String {
        get { UserDefaults.standard.string(forKey: "mobile.sensitivity") ?? "standard" }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "mobile.sensitivity") }
    }

    public func prepareLibrary() async {
        guard !clearing else { return }
        do {
            try await ensureLibrary()
            guard !applePreparing, !clearing else { return }
            appleStatusRevision += 1
            let revision = appleStatusRevision
            let requestedLanguage = language
            let installed = await AppleSpeechAnalyzer.isModelInstalled(locale: Locale(identifier: requestedLanguage == "en" ? "en-US" : "zh-CN"))
            guard !clearing, appleStatusRevision == revision, language == requestedLanguage else { return }
            appleReady = installed; libraryError = nil
        }
        catch { libraryError = "ios.error.library" }
    }

    func ensureLibrary() async throws {
        guard !clearing else { throw CancellationError() }
        if let libraryTask { try await libraryTask.value; return }
        guard runtime == nil else { return }
        let task = Task { try await install() }
        libraryTask = task
        defer { libraryTask = nil }
        try await task.value
    }

    public func prepareAppleModel() async {
        guard !applePreparing, canChangeConfiguration else { return }
        let requestedLanguage = language
        appleStatusRevision += 1
        applePreparing = true
        let task = Task {
            try await AppleSpeechAnalyzer.prepare(locale: Locale(identifier: requestedLanguage == "en" ? "en-US" : "zh-CN"))
            try Task.checkCancellation()
        }
        appleTask = task
        defer { applePreparing = false; appleTask = nil }
        do {
            try await task.value
            guard !clearing, language == requestedLanguage else { return }
            appleReady = true; libraryError = nil
        } catch is CancellationError {} catch { if !clearing { libraryError = "ios.error.local_unavailable" } }
    }

    public func cancelApplePreparation() { appleTask?.cancel() }

    public func changeLanguage(_ value: String) async {
        guard canChangeConfiguration, ["zh", "en"].contains(value) else { return }
        modelMutation = selectedModel
        defer { modelMutation = nil }
        await disable()
        language = value; appleReady = false
        await prepareLibrary()
    }
}
#endif
