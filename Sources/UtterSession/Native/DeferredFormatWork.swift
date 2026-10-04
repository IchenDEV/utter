import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
final class DeferredFormatWork: SessionFollowupWork {
    private let request: ProcessingRequest
    private let recipeID: String
    private let outputs: any SessionOutputStateService
    private let recipes: any ProviderCatalog<Void, any ModeRecipeService>
    private let access: any ModelResourceAccess
    private let screen: Task<ScreenContextSnapshot, Never>?
    private let authorize: () throws -> Void
    private var replacement: DeferredReplacement?
    private var revoked = false

    init(request: ProcessingRequest, recipeID: String, outputs: any SessionOutputStateService,
         recipes: any ProviderCatalog<Void, any ModeRecipeService>, access: any ModelResourceAccess,
         screen: Task<ScreenContextSnapshot, Never>?, authorize: @escaping () throws -> Void) {
        self.request = request; self.recipeID = recipeID; self.outputs = outputs
        self.recipes = recipes; self.access = access; self.screen = screen; self.authorize = authorize
    }

    func install(_ completion: SessionCompletion, recordID: UUID) -> Bool {
        guard !revoked, completion.accepted, case .delivery(let receipt) = completion.acceptance else { return false }
        let target = receipt.anchor?.target
        let pending = DeferredReplacement(historyRecordID: recordID, rawText: completion.transcript,
            insertedText: completion.text, targetPID: target?.processIdentifier,
            targetBundleIdentifier: target?.context.bundleIdentifier, targetAppName: target?.context.appName ?? "",
            message: L("pipeline.background_formatting"), context: request.inputContext,
            formatKind: request.formatKind ?? .plainParagraph)
        guard outputs.installPending(pending, anchor: receipt.anchor) else { return false }
        replacement = pending
        return true
    }

    func run() async {
        guard let replacement else { return }
        do {
            try check()
            let context = await screen?.value ?? .empty
            try check()
            let result = try await access.withAccess {
                try check()
                let recipe = try await recipes.create(id: recipeID, request: ())
                try check()
                return try await recipe.process(ProcessingRequest(mode: request.mode, text: request.text,
                    options: request.options, dictionary: request.dictionary, screenContext: context.text,
                    screenImage: context.image, memoryContext: request.memoryContext,
                    inputContext: request.inputContext, formatKind: request.formatKind))
            }
            try check()
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw IntegrationError.operationFailed }
            outputs.updatePending(replacement.id) {
                $0.formattedText = text
                $0.state = Date() < $0.expiresAt ? .ready : .expired
                $0.message = L($0.state == .ready ? "pipeline.formatted_ready" : "pipeline.replacement_expired")
            }
        } catch {
            outputs.updatePending(replacement.id) { $0.state = .failed; $0.message = L("pipeline.formatting_failed") }
        }
    }

    private func check() throws {
        try Task.checkCancellation()
        guard !revoked, outputs.snapshot.pending?.id == replacement?.id else { throw CancellationError() }
        try authorize()
    }

    func revoke() { revoked = true; screen?.cancel() }
    func close() async { screen?.cancel(); if let screen { _ = await screen.value } }
}
