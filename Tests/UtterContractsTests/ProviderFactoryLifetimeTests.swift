import XCTest
import UtterRuntime
@testable import UtterContracts

@MainActor
final class ProviderFactoryLifetimeTests: XCTestCase {
    func testRevokedFactoryDrainsBeforeItsResourceCleanupAndCannotReturnALateProvider() async throws {
        let registry = ProviderRegistry<Void, String>()
        let entered = ProviderFactorySignal()
        let release = ProviderFactorySignal()
        let revoking = ProviderFactorySignal()
        var cleaned = false
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "factory")) { context, _ in
            try context.scope.onRevoke { revoking.send() }
            try context.scope.onDispose { cleaned = true }
            try registry.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "slow", displayName: "Slow")) { _ in
                entered.send()
                await release.wait()
                XCTAssertFalse(cleaned)
                return "late"
            }, scope: context.scope)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        try await runtime.start([PluginSelection("factory")])
        let create = Task { try await registry.create(id: "slow", request: ()) }
        await entered.wait()
        var stopped = false
        let stop = Task { try await runtime.stop(); stopped = true }
        await revoking.wait()
        XCTAssertFalse(stopped)
        XCTAssertFalse(cleaned)
        do { _ = try await registry.create(id: "slow", request: ()); XCTFail("Revoked factory admitted new work") } catch {}
        release.send()
        do { _ = try await create.value; XCTFail("Late provider escaped its scope") } catch {}
        try await stop.value
        XCTAssertTrue(cleaned)
        XCTAssertTrue(stopped)
    }
}

@MainActor
private final class ProviderFactorySignal {
    private var sent = false
    private var continuation: CheckedContinuation<Void, Never>?
    func send() { sent = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if sent { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
