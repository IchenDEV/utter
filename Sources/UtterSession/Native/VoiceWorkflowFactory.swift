import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
final class VoiceWorkflowFactory: SessionWorkflowFactory {
    private let dependencies: VoiceWorkflowDependencies
    private let isReady: () -> Bool
    private var followups: [UUID: (work: any SessionFollowupWork, task: Task<Void, Never>)] = [:]
    init(dependencies: VoiceWorkflowDependencies, isReady: @escaping () -> Bool) {
        self.dependencies = dependencies
        self.isReady = isReady
    }

    func make(_ intent: SessionIntent) throws -> any SessionJob {
        guard isReady() else { throw CancellationError() }
        try authorize(intent)
        if case .applyReplacement(let id) = intent.operation {
            guard intent.clientID == nil, let outputs = dependencies.outputs else { throw IntegrationError.invalidSessionState }
            let values = dependencies.settings.values
            let target = try? dependencies.targets.capture(TargetCaptureRequest(outputMode: values.outputMode,
                inputLanguage: values.inputLanguage, source: .menuBar))
            return try DeferredReplacementJob(id: id, outputs: outputs, output: dependencies.output,
                access: dependencies.access, target: target, operationID: intent.id, authorize: { [self] in try authorize(intent) })
        }
        var values = dependencies.credentials.snapshot.applying(to: dependencies.settings.values)
        if let language = intent.request.language { values.inputLanguage = language }
        if let mode = intent.request.mode { values.outputMode = mode }
        if let screen = intent.request.useScreenContext { values.useScreenContext = screen }
        let bindings = try dependencies.configuration?.sessionSnapshot.bindings ?? [:]
        let speech: ProviderDescriptor?
        if case .text = intent.input { speech = nil }
        else { speech = try descriptor(bindings["speech"] ?? values.speechEngine.rawValue, in: dependencies.speech.descriptors) }
        if let legacyType = speech?.legacyIDs.compactMap({ SpeechEngineType(rawValue: $0) }).first {
            values.speechEngine = legacyType
        }
        let selection = SpeechSelection(settings: values, providerID: speech?.id)
        let speechFiles = speech == nil ? nil : FrozenModelFiles(modelID: selection.model, using: dependencies.files)
        let frozenSpeech = SpeechSelection(providerID: selection.providerID, type: selection.type, model: selection.model,
            modelPath: speechFiles?.installedSpeechModelURL(selection.model)?.path ?? "", locale: selection.locale,
            appKey: selection.appKey, accessKey: selection.accessKey, resourceID: selection.resourceID)
        let mode = intent.mode ?? Self.mode(for: values.outputMode)
        let recipe = try descriptor(bindings[Self.recipeID(for: mode)] ?? Self.recipeID(for: mode), in: dependencies.recipes.descriptors)
        let providerID = bindings["text"] ?? (values.useRemoteLLM ? "generation.remote" : values.localLLMBackend == .espresso ? "generation.ane" : "generation.mlx")
        let generation = mode == .direct ? nil : try descriptor(providerID, in: dependencies.generation.descriptors)
        var options = TextProcessingOptions(settings: values)
        if let generation { options = options.selecting(generation) }
        options = options.freezingModelLocations(using: dependencies.files)
        options.fallbackProviderID = bindings["fallback"] ?? options.fallbackProviderID
        options.imageProviderID = bindings["image"] ?? options.imageProviderID
        if generation?.modelLocation == .bundle, options.fallbackToMLXOnEspressoFailure {
            _ = try descriptor(options.fallbackProviderID, in: dependencies.generation.descriptors)
        }
        let client = intent.clientID.flatMap { dependencies.clients.client(id: $0) }
        let target = intent.clientID == nil ? try? dependencies.targets.capture(TargetCaptureRequest(
            outputMode: values.outputMode, inputLanguage: values.inputLanguage, source: .menuBar)) : nil
        let context = target?.context ?? InputContext(appName: client?.displayName, bundleIdentifier: client?.bundleIdentifier,
            outputMode: values.outputMode, inputLanguage: values.inputLanguage, source: .integration)
        let dictionary = dependencies.dictionary.snapshot(industryLexicon: dependencies.lexicons.snapshot(for: values.industryLexicon),
            bundleIdentifier: context.bundleIdentifier, languageCode: values.inputLanguage.whisperCode)
        let settings = VoiceInputSettings(settings: values, speech: frozenSpeech, dictionary: dictionary)
        let memory = settings.enableMemory && mode != .direct
            ? dependencies.memory?.recentContext(limit: 5, windowMinutes: settings.memoryWindowMinutes, currentContext: context) ?? "" : ""
        return VoiceSessionJob(intent: intent, settings: settings, options: options, mode: mode, recipeID: recipe.id,
            directRecipeID: bindings["mode.direct"] ?? "mode.direct", editRecipeID: bindings["mode.edit"] ?? "mode.edit",
            speechDescriptor: speech, speechFiles: speechFiles, context: context, target: target,
            recentOutput: dependencies.outputs?.recent, memoryContext: memory,
            dependencies: dependencies, authorize: { [self] in try authorize(intent) })
    }

    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {
        guard case .success(let completion) = result, completion.accepted else { return }
        let recordID = completion.historyReplacement?.recordID ?? intent.id
        switch completion.outputMutation {
        case .remember: dependencies.outputs?.remember(completion, recordID: recordID)
        case .copiedPending(let id, let message):
            dependencies.outputs?.updatePending(id) { $0.state = .copied; $0.message = message }
        }
        if let work = completion.followup {
            let installed = work.install(completion, recordID: intent.id)
            let task = Task { [self] in
                if installed { await work.run() }
                await work.close()
                followups[intent.id] = nil
            }
            followups[intent.id] = (work, task)
        }
        guard case .delivery(let receipt) = completion.acceptance, let context = completion.record?.context,
              let seed = receipt.anchor?.correctionSeed(context: context) else { return }
        dependencies.correction?.start(seed: seed, recordID: recordID)
    }

    func willActivate(_ intent: SessionIntent) { if intent.operation == .input { revoke() } }

    func revoke() {
        for (_, followup) in followups { followup.work.revoke(); followup.task.cancel() }
    }

    func close() async {
        revoke()
        for (_, followup) in Array(followups) { await followup.task.value }
    }

    private func authorize(_ intent: SessionIntent) throws {
        guard isReady() else { throw CancellationError() }
        guard let clientID = intent.clientID else { return }
        guard dependencies.settings.values.developerInterfaceEnabled else { throw IntegrationError.developerInterfaceDisabled }
        guard dependencies.clients.isAuthorized(clientID: clientID, capability: .record) else { throw IntegrationError.unauthorizedClient }
        if clientID.hasPrefix("http:"), clientID != IntegrationClient.localHTTP(tokenID: dependencies.credentials.snapshot.developerHTTPToken).id {
            throw IntegrationError.unauthorizedClient
        }
    }

    private func descriptor(_ id: String, in descriptors: [ProviderDescriptor]) throws -> ProviderDescriptor {
        guard let value = descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }) else { throw ProviderCatalogError.unknownIdentifier(id) }
        return value
    }
    private static func mode(for mode: OutputMode) -> TextProcessingMode {
        switch mode { case .direct: return .direct; case .processed: return .formatting; case .command: return .command }
    }
    private static func recipeID(for mode: TextProcessingMode) -> String {
        switch mode {
        case .direct: return "mode.direct"
        case .formatting: return "mode.formatting"
        case .command: return "mode.command"
        case .translation: return "mode.translation"
        case .selectionEdit: return "mode.edit"
        }
    }
}
