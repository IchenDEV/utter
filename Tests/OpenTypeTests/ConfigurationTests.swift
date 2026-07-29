import Foundation
import XCTest
@testable import OpenType

final class ConfigurationTests: XCTestCase {
    func testDefaultFormattingModelDoesNotUseTinyFallback() {
        XCTAssertEqual(AppSettings.defaultLLMModelID, "mlx-community/Qwen3.5-2B-4bit")
        XCTAssertNotEqual(AppSettings.defaultLLMModelID, "mlx-community/Qwen3.5-0.8B-MLX-4bit")
    }

    func testRemoteProviderDefaultsMatchExpectedAPIs() {
        XCTAssertEqual(RemoteProvider.openai.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(RemoteProvider.openai.defaultModel, "gpt-4.1-mini")
        XCTAssertEqual(RemoteProvider.openai.apiFormat, .openai)
        XCTAssertNil(RemoteProvider.openai.defaultApiVersion)

        XCTAssertEqual(RemoteProvider.claude.defaultBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(RemoteProvider.claude.defaultModel, "claude-sonnet-4-6-20251001")
        XCTAssertEqual(RemoteProvider.claude.apiFormat, .anthropic)
        XCTAssertEqual(RemoteProvider.claude.defaultApiVersion, "2023-06-01")

        XCTAssertEqual(RemoteProvider.gemini.defaultBaseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(RemoteProvider.openrouter.defaultModel, "google/gemini-2.5-flash")
        XCTAssertEqual(RemoteProvider.siliconflow.defaultBaseURL, "https://api.siliconflow.cn/v1")
        XCTAssertEqual(RemoteProvider.doubao.defaultBaseURL, "https://ark.cn-beijing.volces.com/api/v3")
        XCTAssertEqual(RemoteProvider.bailian.defaultBaseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(RemoteProvider.minimax.defaultBaseURL, "https://api.minimax.chat/v1")
        XCTAssertEqual(RemoteProvider.minimaxGlobal.defaultBaseURL, "https://api.minimaxi.chat/v1")
    }

    func testRemoteProviderAllCasesAreStableAndIdentifiable() {
        XCTAssertEqual(RemoteProvider.allCases.map(\.id), [
            "custom", "openai", "claude", "gemini", "openrouter",
            "siliconflow", "doubao", "bailian", "minimax", "minimaxGlobal",
        ])
        XCTAssertTrue(RemoteProvider.allCases.dropFirst().allSatisfy { !$0.defaultBaseURL.isEmpty })
        XCTAssertTrue(RemoteProvider.allCases.dropFirst().allSatisfy { !$0.defaultModel.isEmpty })
    }

    func testInputLanguageMetadata() {
        XCTAssertNil(InputLanguage.auto.whisperCode)
        XCTAssertEqual(InputLanguage.chinese.whisperCode, "zh")
        XCTAssertEqual(InputLanguage.english.whisperCode, "en")
        XCTAssertEqual(InputLanguage.japanese.whisperCode, "ja")
        XCTAssertEqual(InputLanguage.korean.whisperCode, "ko")
        XCTAssertEqual(InputLanguage.cantonese.whisperCode, "yue")

        XCTAssertEqual(InputLanguage.auto.localeIdentifier, Locale.current.identifier)
        XCTAssertEqual(InputLanguage.chinese.localeIdentifier, "zh-CN")
        XCTAssertEqual(InputLanguage.english.localeIdentifier, "en-US")
        XCTAssertEqual(InputLanguage.japanese.localeIdentifier, "ja-JP")
        XCTAssertEqual(InputLanguage.korean.localeIdentifier, "ko-KR")
        XCTAssertEqual(InputLanguage.cantonese.localeIdentifier, "zh-HK")
    }

    func testSpeechEngineCasesIncludeLocalASRProviders() {
        XCTAssertEqual(SpeechEngineType.allCases.map(\.rawValue), [
            "whisper", "apple", "volc", "qwen3", "mimo",
        ])
    }

    func testLocalASRDefaultsMatchOnDeviceRunner() {
        XCTAssertEqual(LocalASRConfiguration.defaultPythonPath, "python3")
        XCTAssertEqual(LocalASRConfiguration.qwen3DefaultModel, "mlx-community/Qwen3-ASR-1.7B-bf16")
        XCTAssertEqual(LocalASRConfiguration.mimoDefaultModel, "XiaomiMiMo/MiMo-V2.5-ASR")
        XCTAssertEqual(LocalASRConfiguration.mimoTokenizerModel, "XiaomiMiMo/MiMo-Audio-Tokenizer")
    }

    @MainActor
    func testASRCompletenessRequiresWeightFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestFiles(["config.json", "tokenizer_config.json", "vocab.json"], under: dir)
        XCTAssertFalse(ModelCatalog.asrRepoContainsRequiredFiles(LocalASRConfiguration.qwen3DefaultModel, at: dir))

        try writeTestFiles(ModelCatalog.asrRequiredFiles(for: LocalASRConfiguration.qwen3DefaultModel), under: dir)
        XCTAssertTrue(ModelCatalog.asrRepoContainsRequiredFiles(LocalASRConfiguration.qwen3DefaultModel, at: dir))
    }

    @MainActor
    func testMiMoRepositoryReadinessRequiresRunnerSource() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertFalse(ModelCatalog.mimoRepositoryIsReady(at: dir))
        let runner = dir.appendingPathComponent("src/mimo_audio/mimo_audio.py")
        try FileManager.default.createDirectory(at: runner.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: runner)
        XCTAssertTrue(ModelCatalog.mimoRepositoryIsReady(at: dir))
    }

    func testAudioCaptureActivityDetectsSilence() {
        var activity = AudioCaptureActivity()
        activity.record(rms: 0, frameCount: 16_000)

        XCTAssertFalse(activity.hasMeaningfulAudio)
    }

    func testAudioCaptureActivityAcceptsAudibleInput() {
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.02, frameCount: 4_096)

        XCTAssertTrue(activity.hasMeaningfulAudio)
    }

    func testHistoryRetentionIntervals() {
        XCTAssertNil(HistoryRetention.forever.timeInterval)
        XCTAssertEqual(HistoryRetention.threeDays.timeInterval, TimeInterval(3 * 24 * 3600))
        XCTAssertEqual(HistoryRetention.sevenDays.timeInterval, TimeInterval(7 * 24 * 3600))
        XCTAssertEqual(HistoryRetention.oneMonth.timeInterval, TimeInterval(30 * 24 * 3600))
    }

    func testMenuBarIconSymbols() {
        XCTAssertEqual(MenuBarIcon.mic.symbolName, "mic.fill")
        XCTAssertEqual(MenuBarIcon.waveform.symbolName, "waveform")
        XCTAssertEqual(MenuBarIcon.bubble.symbolName, "bubble.left.fill")
    }

    func testAppIconAppearanceResourceNames() {
        XCTAssertEqual(AppIconAppearance.dark.resourceName(systemIsDark: false), "AppIconDark")
        XCTAssertEqual(AppIconAppearance.light.resourceName(systemIsDark: true), "AppIconLight")
        XCTAssertEqual(AppIconAppearance.system.resourceName(systemIsDark: true), "AppIconDark")
        XCTAssertEqual(AppIconAppearance.system.resourceName(systemIsDark: false), "AppIconLight")
    }

    func testLanguageStyleStaticMetadata() {
        XCTAssertEqual(LanguageStyle.professional.icon, "list.number")
        XCTAssertEqual(LanguageStyle.casual.icon, "bubble.left")
        XCTAssertEqual(LanguageStyle.custom.icon, "slider.horizontal.3")
    }

    @MainActor
    func testRecommendedLocalModelRemainsListed() {
        let models = ModelCatalog.defaultLLMModels
        XCTAssertTrue(models.contains { $0.0 == "mlx-community/Qwen3.5-2B-4bit" })
    }

    @MainActor
    func testGemma4ModelsRemainListed() {
        let models = ModelCatalog.defaultLLMModels
        XCTAssertTrue(models.contains { $0.0 == "mlx-community/gemma-4-e2b-it-4bit" })
        XCTAssertTrue(models.contains { $0.0 == "mlx-community/gemma-4-e4b-it-4bit" })
    }

    @MainActor
    func testLLMModelsAreTiered() {
        let models = ModelCatalog.defaultLLMModels
        XCTAssertTrue(models.contains { $0.4 == .recommended })
        XCTAssertTrue(models.contains { $0.4 == .legacy })
        let defaultModel = models.first { $0.0 == "mlx-community/Qwen3.5-2B-4bit" }
        XCTAssertEqual(defaultModel?.4, .recommended)
    }

    @MainActor
    func testLocalASRModelsRemainListed() {
        let models = ModelCatalog.defaultASRModels
        XCTAssertTrue(models.contains { $0.id == LocalASRConfiguration.qwen3DefaultModel && $0.provider == .qwen3 })
        XCTAssertTrue(models.contains { $0.id == LocalASRConfiguration.mimoDefaultModel && $0.provider == .mimo })
    }

    func testUILanguageDisplayNames() {
        XCTAssertEqual(UILanguage.chinese.displayName, "中文")
        XCTAssertEqual(UILanguage.english.displayName, "English")
    }

    func testLocalizedStringsFollowExplicitUILanguage() {
        XCTAssertEqual(Loc.string("tab.general", language: .english), "General")
        XCTAssertEqual(Loc.string("tab.general", language: .chinese), "通用")
    }

    @MainActor
    func testAppSettingsUpdatesLocalizationLanguageImmediately() {
        let priorLanguage = AppSettings.shared.uiLanguage
        defer { Loc.use(priorLanguage) }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(UILanguage.english.rawValue, forKey: "uiLanguage")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(L("tab.general"), "General")

        settings.uiLanguage = .chinese
        XCTAssertEqual(L("tab.general"), "通用")
    }

    @MainActor
    func testSettingsWindowTitleFollowsUILanguage() {
        XCTAssertEqual(SettingsWindowTitle.text(for: .english), "OpenType Settings")
        XCTAssertEqual(SettingsWindowTitle.text(for: .chinese), "OpenType 设置")
    }

    func testSettingsWindowWidthAllowsEnglishTabLabels() {
        XCTAssertGreaterThanOrEqual(SettingsWindowLayout.width, 760)
    }

    func testInstantInsertDefaultsOff() {
        XCTAssertFalse(AppSettings.shared.enableInstantInsert)
    }

    func testDeveloperInterfaceDefaultsOff() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.developerInterfaceEnabled)
    }

    func testDeveloperHTTPTokenCanBeReset() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let original = settings.developerHTTPToken

        settings.resetDeveloperHTTPToken()
        let reset = settings.developerHTTPToken

        XCTAssertFalse(reset.isEmpty)
        XCTAssertNotEqual(reset, original)
    }

    func testDeveloperHTTPPortFallsBackForInvalidPersistedValue() {
        let (negativeDefaults, negativeSuiteName) = makeIsolatedDefaults()
        defer { negativeDefaults.removePersistentDomain(forName: negativeSuiteName) }
        negativeDefaults.set(-1, forKey: "developerHTTPPort")

        XCTAssertEqual(AppSettings(defaults: negativeDefaults).developerHTTPPort, 38_765)

        let (largeDefaults, largeSuiteName) = makeIsolatedDefaults()
        defer { largeDefaults.removePersistentDomain(forName: largeSuiteName) }
        largeDefaults.set(70_000, forKey: "developerHTTPPort")

        XCTAssertEqual(AppSettings(defaults: largeDefaults).developerHTTPPort, 38_765)
    }

    func testStartupPreloadPolicyLoadsOnlyWhisperSpeechModel() {
        XCTAssertTrue(StartupModelPreloadPolicy.shouldPreloadSpeechModel(enabled: true, speechEngine: .whisper))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadSpeechModel(enabled: true, speechEngine: .apple))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadSpeechModel(enabled: true, speechEngine: .volc))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadSpeechModel(enabled: true, speechEngine: .qwen3))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadSpeechModel(enabled: true, speechEngine: .mimo))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadSpeechModel(enabled: false, speechEngine: .whisper))
    }

    func testStartupPreloadPolicyLoadsOnlyLocalFormattingModelWithID() {
        XCTAssertTrue(StartupModelPreloadPolicy.shouldPreloadFormattingModel(
            enabled: true,
            useRemoteLLM: false,
            modelID: "mlx-community/Qwen3.5-2B-4bit"
        ))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadFormattingModel(
            enabled: true,
            useRemoteLLM: true,
            modelID: "gpt-4.1-mini"
        ))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadFormattingModel(
            enabled: true,
            useRemoteLLM: false,
            modelID: "  "
        ))
        XCTAssertFalse(StartupModelPreloadPolicy.shouldPreloadFormattingModel(
            enabled: false,
            useRemoteLLM: false,
            modelID: "mlx-community/Qwen3.5-2B-4bit"
        ))
    }
}

private func writeTestFiles(_ paths: [String], under dir: URL) throws {
    for path in paths {
        let file = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: file)
    }
}

private func makeIsolatedDefaults(function: String = #function) -> (UserDefaults, String) {
    let suiteName = "OpenTypeTests.\(function).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
