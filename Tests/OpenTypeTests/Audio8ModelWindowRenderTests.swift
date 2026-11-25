import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class Audio8ModelWindowRenderTests: XCTestCase {
    func testRenderAudio8ModelSectionLayouts() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["UTTER_AUDIO8_LAYOUT_OUTPUT"] else {
            throw XCTSkip("Opt-in headless layout evidence")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [UILanguage.chinese, .english] {
            Loc.use(language)
            let fixture = try await ModelSourceIntegration.start()
            let catalog = ModelCatalogProjection(service: fixture.catalog)
            let lifecycle = ModelLifecycleProjection(service: Audio8WindowLifecycle())
            let state = AppState()
            fixture.settings.speechEngine = .audio8
            fixture.settings.uiLanguage = language

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for width in [760.0, 560.0] {
                    let view = ModelManagementView(
                        catalog: catalog,
                        storage: fixture.storage,
                        lifecycle: lifecycle,
                        remoteConnection: nil
                    )
                    .environmentObject(fixture.settings)
                    .environmentObject(state)
                    let host = NSHostingView(rootView: view)
                    host.appearance = NSAppearance(named: appearance)
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 1400)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let name = "audio8-\(language.rawValue)-\(appearance.rawValue)-\(Int(width)).png"
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
private final class Audio8WindowLifecycle: ModelLifecycleService {
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
