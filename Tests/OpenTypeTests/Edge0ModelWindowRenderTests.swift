import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class Edge0ModelWindowRenderTests: XCTestCase {
    func testRenderEdge0DownloadOnlySection() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["UTTER_EDGE0_LAYOUT_OUTPUT"] else {
            throw XCTSkip("Opt-in headless layout evidence")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [UILanguage.chinese, .english] {
            Loc.use(language)
            let fixture = try await ModelSourceIntegration.start(language: language)
            let catalog = ModelCatalogProjection(service: fixture.catalog)
            let lifecycle = ModelLifecycleProjection(service: Edge0WindowLifecycle())
            let state = AppState()
            fixture.settings.localLLMBackend = .mlx
            fixture.settings.useRemoteLLM = false
            fixture.settings.llmModel = Edge0Model.defaultID
            fixture.settings.uiLanguage = language

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for width in [760.0, 560.0] {
                    var view = ModelManagementView(
                        catalog: catalog,
                        storage: fixture.storage,
                        lifecycle: lifecycle,
                        remoteConnection: nil
                    )
                    view.selectedModelFamily = .edge0
                    let host = NSHostingView(rootView: view
                        .environmentObject(fixture.settings)
                        .environmentObject(state))
                    host.appearance = NSAppearance(named: appearance)
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 1400)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let name = "edge0-\(language.rawValue)-\(appearance.rawValue)-\(Int(width)).png"
                    try data.write(to: directory.appendingPathComponent(name))
                }
            }

            catalog.dispose()
            lifecycle.dispose()
            try await fixture.close()
        }
        Loc.use(.chinese)
    }
}

@MainActor
private final class Edge0WindowLifecycle: ModelLifecycleService {
    var snapshot = ModelLifecycleSnapshot()
    func observe(_ callback: @escaping (ModelLifecycleSnapshot) -> Void) -> UUID { UUID() }
    func removeObserver(_ id: UUID) {}
    func preloadSpeech() async throws { throw GenerationServiceError.unsupportedOperation }
    func preloadText() async throws { throw GenerationServiceError.unsupportedOperation }
    func unloadSpeech(providerID: String?) async throws {}
    func unloadText() async throws {}
    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult {
        throw GenerationServiceError.unsupportedOperation
    }
    func validateBundle(at url: URL) async throws { throw GenerationServiceError.unsupportedOperation }
}
