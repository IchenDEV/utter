import XCTest
@testable import OpenType

final class IndustryEditionTests: XCTestCase {
    func testMedicalEditionLocksNetworkAndCustomizationCapabilities() {
        let profile = ProductEdition.current

        XCTAssertEqual(profile.id, "medical-offline-cn-v1")
        XCTAssertEqual(profile.minimumMemoryGB, 8)
        XCTAssertEqual(profile.maximumFormattingCharacters, 2_048)
        XCTAssertEqual(profile.maximumGenerationTokens, 2_048)
        XCTAssertFalse(profile.capabilities.modelManagement)
        XCTAssertFalse(profile.capabilities.modelDownloads)
        XCTAssertFalse(profile.capabilities.remoteInference)
        XCTAssertFalse(profile.capabilities.developerIntegrations)
        XCTAssertFalse(profile.capabilities.customPrompts)
        XCTAssertFalse(profile.capabilities.externalLinks)
        XCTAssertTrue(profile.capabilities.translation)
        XCTAssertEqual(profile.speechModel.id, "mlx-community/Qwen3-ASR-0.6B-bf16")
        XCTAssertEqual(profile.formattingModel.id, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(profile.capabilities.voiceCommands)
        XCTAssertTrue(profile.capabilities.requiresInsertionReview)
        XCTAssertFalse(profile.capabilities.contextMemory)
        XCTAssertFalse(profile.capabilities.correctionLearning)
        XCTAssertFalse(profile.capabilities.dictionaryTransfer)
        XCTAssertFalse(profile.capabilities.activityHistory)
    }

    @MainActor
    func testProductPolicyOverridesSavedOpenAndRemoteSettings() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(SpeechEngineType.volc.rawValue, forKey: "speechEngine")
        defaults.set(true, forKey: "useRemoteLLM")
        defaults.set(true, forKey: "useCustomSystemPrompt")
        defaults.set(true, forKey: "developerInterfaceEnabled")
        defaults.set(true, forKey: "enableMemory")
        defaults.set(true, forKey: "enableCorrectionLearning")
        defaults.set("secret", forKey: "remoteAPIKey")
        let resourceRoot = try makeOfflineBundle()

        let settings = AppSettings(defaults: defaults)
        ProductEdition.apply(to: settings, resourceURL: resourceRoot)

        XCTAssertEqual(settings.speechEngine, .qwen3)
        XCTAssertEqual(settings.qwenASRModel, ProductEdition.current.speechModel.id)
        XCTAssertEqual(settings.llmModel, ProductEdition.current.formattingModel.id)
        XCTAssertEqual(settings.outputMode, .processed)
        XCTAssertFalse(settings.enableInstantInsert)
        XCTAssertFalse(settings.useRemoteLLM)
        XCTAssertFalse(settings.useCustomSystemPrompt)
        XCTAssertFalse(settings.developerInterfaceEnabled)
        XCTAssertFalse(settings.enableMemory)
        XCTAssertFalse(settings.enableCorrectionLearning)
        XCTAssertTrue(settings.remoteAPIKey.isEmpty)
        XCTAssertTrue(settings.localWhisperModelPaths.isEmpty)
        XCTAssertNotNil(settings.localASRModelPaths[settings.qwenASRModel])
        XCTAssertTrue(settings.localASRPythonPath.hasSuffix("speech-runtime/bin/python"))
        XCTAssertNotNil(settings.localLLMModelPaths[settings.llmModel])
    }

    func testOfflineBundleValidationAcceptsCompleteFixedModels() throws {
        let resourceRoot = try makeOfflineBundle()

        XCTAssertTrue(OfflineModelBundle.validate(resourceURL: resourceRoot).isReady)
    }

    func testOfflineBundleValidationRejectsProfileMismatch() throws {
        let resourceRoot = try makeOfflineBundle(editionID: "different-edition")

        XCTAssertEqual(
            OfflineModelBundle.validate(resourceURL: resourceRoot),
            .profileMismatch
        )
    }

    func testOfflineBundleValidationRequiresLicensesAndNotices() throws {
        let resourceRoot = try makeOfflineBundle()
        let root = resourceRoot.appendingPathComponent(OfflineModelBundle.directoryName)
        try FileManager.default.removeItem(at: root.appendingPathComponent("NOTICE"))

        XCTAssertEqual(
            OfflineModelBundle.validate(resourceURL: resourceRoot),
            .missingLegalNotices
        )
    }

    func testOfflineBundleValidationRequiresBundledQwenRuntime() throws {
        let resourceRoot = try makeOfflineBundle()
        let root = resourceRoot.appendingPathComponent(OfflineModelBundle.directoryName)
        try FileManager.default.removeItem(at: root.appendingPathComponent("speech-runtime/bin/python"))

        XCTAssertEqual(
            OfflineModelBundle.validate(resourceURL: resourceRoot),
            .incompleteSpeechRuntime
        )
    }

    func testBundledMedicalLexiconHasSafeCoreCoverage() {
        let lexicon = IndustryLexicon.shared
        let terms = Set(lexicon.terms.map(\.term))

        XCTAssertEqual(lexicon.editionID, ProductEdition.current.id)
        XCTAssertEqual(lexicon.sourceVersion, "medical-seed-v1")
        XCTAssertFalse(lexicon.licenseOrRights.isEmpty)
        XCTAssertGreaterThanOrEqual(terms.count, 70)
        XCTAssertTrue(terms.contains("主诉"))
        XCTAssertTrue(terms.contains("糖化血红蛋白"))
        XCTAssertTrue(terms.contains("静脉滴注"))
        XCTAssertTrue(terms.contains("知情同意"))
    }

    func testIndustryTermsReachRecognitionAndSafetyPromptsWithoutReplacement() {
        let snapshot = PersonalDictionarySnapshot(
            entries: [],
            editRules: [],
            industryTerms: ["糖化血红蛋白", "HbA1c"]
        )
        let prompt = TextProcessor().systemPromptWithPersonalContext(
            "base",
            inputLanguage: .chinese,
            dictionarySnapshot: snapshot
        )

        XCTAssertEqual(snapshot.applyReplacements(to: "HbA1c 7%"), "HbA1c 7%")
        XCTAssertEqual(snapshot.recognitionPhrases, ["糖化血红蛋白", "HbA1c"])
        XCTAssertTrue(prompt.contains("医疗行业词库"))
        XCTAssertTrue(prompt.contains("不得据此补写诊断、药名、剂量、数值或医嘱"))
    }

    func testMedicalFormattingUsesBoundedGenerationBudget() {
        let options = TextProcessor().formattingOptions(
            for: String(repeating: "病", count: 2_048),
            style: .professional
        )

        XCTAssertEqual(options.maxTokens, ProductEdition.current.maximumGenerationTokens)
        XCTAssertEqual(options.temperature, 0)
    }

    @MainActor
    func testTranslationUsesTheFixedLocalQwenTextModel() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.llmModel = "untrusted/other-model"
        settings.useRemoteLLM = true

        let options = TextProcessingOptions(settings: settings)

        XCTAssertTrue(ProductEdition.current.capabilities.translation)
        XCTAssertEqual(options.llmModel, ProductEdition.current.formattingModel.id)
        XCTAssertTrue(options.llmModel.localizedCaseInsensitiveContains("qwen"))
        XCTAssertFalse(options.useRemoteLLM)
    }

    func testRemoteClientFailsBeforeCreatingANetworkRequest() async {
        do {
            _ = try await RemoteLLMClient().generate(
                prompt: "test",
                systemPrompt: nil,
                baseURL: "https://example.invalid",
                apiKey: "unused",
                model: "unused"
            )
            XCTFail("Expected offline edition rejection")
        } catch RemoteLLMError.unavailableInOfflineEdition {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "IndustryEditionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeOfflineBundle(editionID: String = ProductEdition.current.id) throws -> URL {
        let resourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndustryEditionTests-\(UUID().uuidString)", isDirectory: true)
        let root = resourceRoot.appendingPathComponent(OfflineModelBundle.directoryName, isDirectory: true)
        let speech = root.appendingPathComponent("speech", isDirectory: true)
        let speechRuntime = root.appendingPathComponent("speech-runtime", isDirectory: true)
        let formatting = root.appendingPathComponent("formatting", isDirectory: true)
        try FileManager.default.createDirectory(at: speech, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: speechRuntime.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: formatting, withIntermediateDirectories: true)

        for name in [
            "config.json",
            "model.safetensors",
            "model.safetensors.index.json",
            "preprocessor_config.json",
            "tokenizer_config.json",
            "vocab.json",
        ] {
            try Data("model".utf8).write(to: speech.appendingPathComponent(name))
        }
        let runtimePython = speechRuntime.appendingPathComponent("bin/python")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: runtimePython)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runtimePython.path
        )
        for marker in [".opentype-runtime-ready", ".opentype-native-runtime-ready"] {
            try Data(LocalASRRuntime.qwenRequirement.utf8).write(
                to: speechRuntime.appendingPathComponent(marker)
            )
        }
        try Data("{}".utf8).write(to: formatting.appendingPathComponent("config.json"))
        try Data("weights".utf8).write(to: formatting.appendingPathComponent("model.safetensors"))
        let licenses = root.appendingPathComponent("LICENSES", isDirectory: true)
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        try Data("model license".utf8).write(to: licenses.appendingPathComponent("MODELS.txt"))
        try Data("third-party notices".utf8).write(to: root.appendingPathComponent("NOTICE"))

        let manifest = OfflineModelManifest(
            schemaVersion: 2,
            editionID: editionID,
            minimumMemoryGB: ProductEdition.current.minimumMemoryGB,
            speech: .init(
                id: ProductEdition.current.speechModel.id,
                path: ProductEdition.current.speechModel.relativePath
            ),
            speechRuntime: .init(
                id: ProductEdition.current.speechRuntime.id,
                path: ProductEdition.current.speechRuntime.relativePath
            ),
            formatting: .init(
                id: ProductEdition.current.formattingModel.id,
                path: ProductEdition.current.formattingModel.relativePath
            )
        )
        try JSONEncoder().encode(manifest).write(
            to: root.appendingPathComponent(OfflineModelBundle.manifestFilename)
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: resourceRoot) }
        return resourceRoot
    }
}
