import XCTest
@testable import UtterRemoteMic

/// Read-only check against the real machine; it never writes a mapping. It passes with or
/// without the remote connected and only asserts the native calls neither crash nor mislead.
@MainActor
final class RemoteHIDServiceProviderSmokeTests: XCTestCase {
    func testEnumeratingRepeatedlyDoesNotCrashAndReturnsOnlyReadableRemoteServices() {
        let provider = RemoteHIDServiceProvider()
        var ids = Set<UInt64>()
        for _ in 0..<20 {
            for service in provider.matchingServices() {
                ids.insert(service.id)
                XCTAssertNotNil(service.mappings(), "the remote's mapping property should decode")
            }
        }
        print("RemoteHIDServiceProviderSmoke matched services: \(ids.sorted())")
        XCTAssertLessThanOrEqual(ids.count, 2, "one physical remote exposes at most a couple of services")
    }
}
