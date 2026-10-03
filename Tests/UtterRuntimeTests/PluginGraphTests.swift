import XCTest
@testable import UtterRuntime

@MainActor
final class PluginGraphTests: XCTestCase {
    private let a = ServiceKey<Int>("a")
    private let b = ServiceKey<Int>("b")

    func testCyclesIncludeAnActualDependencyChain() async throws {
        let first = PluginRegistration(descriptor: PluginDescriptor(id: "first", requires: [b.required], provides: [a.reference])) { _, _ in }
        let second = PluginRegistration(descriptor: PluginDescriptor(id: "second", requires: [a.required], provides: [b.reference])) { _, _ in }
        let catalog = try PluginCatalog([first, second])
        XCTAssertThrowsError(try catalog.validate([PluginSelection("first"), PluginSelection("second")])) {
            XCTAssertEqual($0 as? PluginRuntimeError, .dependencyCycle(["first", "second", "first"]))
        }
    }

    func testOptionalDependencyOrdersWhenPresentAndWorksWhenAbsent() async throws {
        let provider = PluginRegistration(descriptor: PluginDescriptor(id: "z", provides: [a.reference])) { _, _ in }
        let consumer = PluginRegistration(descriptor: PluginDescriptor(id: "a", requires: [a.optional])) { _, _ in }
        let catalog = try PluginCatalog([provider, consumer])
        XCTAssertEqual(try catalog.validate([PluginSelection("a")]).map(\.id), ["a"])
        XCTAssertEqual(try catalog.validate([PluginSelection("a"), PluginSelection("z")]).map(\.id), ["z", "a"])
    }

    func testIndependentPluginsAreOrderedByStableID() async throws {
        let registrations = ["c", "a", "b"].map { id in
            PluginRegistration(descriptor: PluginDescriptor(id: id)) { _, _ in }
        }
        let catalog = try PluginCatalog(registrations)
        XCTAssertEqual(try catalog.validate(["c", "b", "a"].map { PluginSelection($0) }).map(\.id), ["a", "b", "c"])
    }

    func testDuplicateAndMismatchedServicesFailBeforeActivation() async throws {
        let first = PluginRegistration(descriptor: PluginDescriptor(id: "first", provides: [a.reference])) { _, _ in }
        let duplicate = PluginRegistration(descriptor: PluginDescriptor(id: "duplicate", provides: [a.reference])) { _, _ in }
        let mismatch = PluginRegistration(descriptor: PluginDescriptor(id: "mismatch", requires: [ServiceKey<String>("a").required])) { _, _ in }
        let catalog = try PluginCatalog([first, duplicate, mismatch])
        XCTAssertThrowsError(try catalog.validate([PluginSelection("first"), PluginSelection("duplicate")])) {
            XCTAssertEqual($0 as? PluginRuntimeError, .duplicateService("a"))
        }
        XCTAssertThrowsError(try catalog.validate([PluginSelection("first"), PluginSelection("mismatch")])) {
            XCTAssertEqual($0 as? PluginRuntimeError, .serviceTypeMismatch("a"))
        }
        XCTAssertThrowsError(try catalog.validate([PluginSelection("first"), PluginSelection("first")]))
        XCTAssertThrowsError(try catalog.validate([PluginSelection("unknown")]))
        XCTAssertThrowsError(try PluginCatalog([first, first]))
    }

    func testConfigurationIsValidatedBeforeAnyFactoryRuns() async throws {
        var calls = 0
        let first = PluginRegistration(descriptor: PluginDescriptor(id: "first")) { _, _ in calls += 1 }
        let catalog = try PluginCatalog([first])
        XCTAssertThrowsError(try catalog.validate([PluginSelection("first", configuration: ["secret": .string("value")])]))
        XCTAssertEqual(calls, 0)
    }
}
