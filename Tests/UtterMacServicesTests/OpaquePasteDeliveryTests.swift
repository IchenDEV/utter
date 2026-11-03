import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class OpaquePasteDeliveryTests: XCTestCase {
    private func request(_ command: DeliveryCommand = .insert("hello"), clipboard: Bool = true, opaque: Bool = true) -> DeliveryRequest {
        DeliveryRequest(id: UUID(), command: command, allowsClipboardPaste: clipboard, allowsOpaquePaste: opaque)
    }

    // MARK: routing

    func testOnlyAnInsertionIntoAnAppWithoutAFocusedElementIsRoutedAndTheSwitchDecidesWhat() {
        let world = World()
        let lease = OpaqueLease()
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(), lease: lease, environment: world.environment), .paste)
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(opaque: false), lease: lease, environment: world.environment), .refuse)
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(clipboard: false), lease: lease, environment: world.environment), .refuse)
        for command in [DeliveryCommand.replaceSelection("x"), .deleteSelection, .clipboard("x")] {
            XCTAssertEqual(OpaquePasteDelivery.route(for: request(command), lease: lease, environment: world.environment), .notOpaque)
        }
    }

    func testAnythingThatLooksLikeAnOrdinaryTargetStaysOnTheExistingPath() {
        var world = World()
        let lease = OpaqueLease()
        lease.capturedWithoutFocus = false
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(), lease: lease, environment: world.environment), .notOpaque)
        lease.capturedWithoutFocus = true
        world.trusted = false
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(), lease: lease, environment: world.environment), .notOpaque)
        world = World(); world.frontmost = 999
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(), lease: lease, environment: world.environment), .notOpaque)
        world = World(); world.focusedElement = true
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(), lease: lease, environment: world.environment), .notOpaque)
        XCTAssertEqual(OpaquePasteDelivery.route(for: request(), lease: PlainLease(), environment: World().environment), .notOpaque)
    }

    // MARK: delivery

    func testExactlyOnePasteIsPostedTheTextStaysOnTheClipboardAndTheReceiptIsUnverified() async {
        let world = World()
        let clipboard = Clipboard("previous")
        var effects: Set<DeliveryEffect> = []
        let result = await OpaquePasteDelivery.deliver("hello", lease: OpaqueLease(), pasteboard: clipboard,
            environment: world.environment, canCommit: { true }, mark: { effects.insert($0).inserted })
        XCTAssertEqual(world.pastes, 1)
        XCTAssertEqual(clipboard.text, "hello")
        XCTAssertEqual(effects, [.clipboard, .paste])
        XCTAssertEqual(result.disposition, .accepted)
        XCTAssertEqual(result.confirmation, .unobservable)
        XCTAssertEqual(result.path, .compatPaste)
        XCTAssertEqual(result.target, .opaque)
        let receipt = DeliveryReceipt(operationID: UUID(), disposition: result.disposition, effect: .none,
            effects: effects, confirmation: result.confirmation)
        XCTAssertEqual(receipt.status, .uncertain)
        XCTAssertFalse(receipt.isConfirmedInsertion)
        XCTAssertNil(receipt.anchor)
    }

    func testEveryGuardPostsNothingAndLeavesTheClipboardAlone() async {
        let cases: [(String, (inout World, OpaqueLease) -> Void, Bool)] = [
            ("secure input", { w, _ in w.secure = true }, true),
            ("frontmost app changed", { w, _ in w.frontmost = 999 }, true),
            ("lease invalid", { _, l in l.isValid = false }, true),
            ("accessibility untrusted", { w, _ in w.trusted = false }, true),
            ("focused element appeared", { w, _ in w.focusedElement = true }, true),
            ("lease had a focus", { _, l in l.capturedWithoutFocus = false }, true),
            ("canCommit false", { _, _ in }, false),
        ]
        for (name, change, canCommit) in cases {
            var world = World()
            let lease = OpaqueLease()
            change(&world, lease)
            let clipboard = Clipboard("previous")
            var effects: Set<DeliveryEffect> = []
            let result = await OpaquePasteDelivery.deliver("hello", lease: lease, pasteboard: clipboard,
                environment: world.environment, canCommit: { canCommit }, mark: { effects.insert($0).inserted })
            XCTAssertEqual(world.pastes, 0, name)
            XCTAssertEqual(clipboard.text, "previous", name)
            XCTAssertTrue(effects.isEmpty, name)
            XCTAssertEqual(result.disposition, .notCommitted, name)
        }
    }

    func testASecondDeliveryWithTheSameEffectBookkeepingCannotPasteAgain() async {
        let world = World()
        let clipboard = Clipboard("previous")
        var effects: Set<DeliveryEffect> = []
        for _ in 0..<2 {
            _ = await OpaquePasteDelivery.deliver("hello", lease: OpaqueLease(), pasteboard: clipboard,
                environment: world.environment, canCommit: { true }, mark: { effects.insert($0).inserted })
        }
        XCTAssertEqual(world.pastes, 1)
    }

    func testAClipboardOverwrittenBeforeThePasteMeansNoPaste() async {
        let clipboard = Clipboard("previous")
        var pastes = 0
        let result = await ClipboardPasteTransaction.pasteUnobserved("hello", pasteboard: clipboard,
            canCommit: { true }, mark: { _ in true }, postPaste: { pastes += 1; return true },
            beforePaste: { _ = clipboard.write("third-party") })
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(clipboard.text, "third-party")
    }

    func testAFailedPostIsUncertainNotAccepted() async {
        let clipboard = Clipboard("previous")
        let result = await ClipboardPasteTransaction.pasteUnobserved("hello", pasteboard: clipboard,
            canCommit: { true }, mark: { _ in true }, postPaste: { false })
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(result.confirmation, .none)
    }

    func testWithoutKeyEventsTheTextIsOnlyCopiedAndSaysSo() async {
        var world = World()
        world.keysAvailable = false
        let clipboard = Clipboard("previous")
        var effects: Set<DeliveryEffect> = []
        let result = await OpaquePasteDelivery.deliver("hello", lease: OpaqueLease(), pasteboard: clipboard,
            environment: world.environment, canCommit: { true }, mark: { effects.insert($0).inserted })
        XCTAssertEqual(world.pastes, 0)
        XCTAssertEqual(result.path, .clipboardOnly)
        XCTAssertEqual(result.confirmation, .clipboardValue)
        XCTAssertEqual(effects, [.clipboard])
    }

    func testLogLineNamesPathAndTargetAndNeverTheText() async {
        let secret = "SECRET-DICTATION-4242"
        let world = World()
        let result = await OpaquePasteDelivery.deliver(secret, lease: OpaqueLease(), pasteboard: Clipboard("previous"),
            environment: world.environment, canCommit: { true }, mark: { _ in true })
        XCTAssertTrue(result.logSummary.hasSuffix("path: compatPaste, target: opaque"))
        XCTAssertFalse(result.logSummary.contains(secret))
    }

    // MARK: backend

    func testTheBackendPastesOnlyWhenTheSwitchIsOnAndRefusesClearlyOtherwise() async {
        for on in [false, true] {
            let world = World()
            let pasteboard = NSPasteboard(name: .init("UtterOpaque-" + UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            pasteboard.clearContents()
            _ = pasteboard.setString("original", forType: .string)
            let backend = NativeOutputBackend(log: Log(service: OpaqueDiagnostics()), isCurrent: { true },
                pasteboard: pasteboard, opaque: world.environment)
            var effects: Set<DeliveryEffect> = []
            let result = await backend.deliver(
                DeliveryRequest(id: UUID(), command: .insert("hello"), target: OpaqueLease(), allowsOpaquePaste: on),
                canCommit: { true }, markCommitted: { effects.insert($0).inserted })
            if on {
                XCTAssertEqual(world.pastes, 1)
                XCTAssertEqual(result.confirmation, .unobservable)
                XCTAssertEqual(pasteboard.string(forType: .string), "hello")
            } else {
                XCTAssertEqual(world.pastes, 0)
                XCTAssertEqual(result.disposition, .notCommitted)
                XCTAssertEqual(result.reason, L("delivery.opaque_target"))
                XCTAssertEqual(pasteboard.string(forType: .string), "original")
                XCTAssertTrue(effects.isEmpty)
            }
        }
    }
}

// MARK: fakes

@MainActor
private final class OpaqueLease: OpaqueTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 100
    let context = InputContext(outputMode: .processed, inputLanguage: .chinese, source: .menuBar)
    var isValid = true
    let isCurrent = false
    var capturedWithoutFocus = true
}

@MainActor
private final class PlainLease: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 100
    let context = InputContext(outputMode: .processed, inputLanguage: .chinese, source: .menuBar)
    let isValid = true
    let isCurrent = true
}

@MainActor
private final class Pastes { var count = 0 }

@MainActor
private struct World {
    var trusted = true
    var secure = false
    var frontmost: Int32? = 100
    var focusedElement = false
    var keysAvailable = true
    private let counter = Pastes()
    var pastes: Int { counter.count }
    var environment: OpaqueDeliveryEnvironment {
        let counter = counter, available = keysAvailable
        return OpaqueDeliveryEnvironment(
            isAccessibilityTrusted: { [trusted] in trusted }, isSecureInput: { [secure] in secure },
            frontmostProcessIdentifier: { [frontmost] in frontmost }, hasFocusedElement: { [focusedElement] in focusedElement },
            prepareKeys: { _ in available ? { counter.count += 1; return true } : nil })
    }
}

@MainActor
private final class Clipboard: DeliveryPasteboard {
    var changeCount = 0
    var text: String?
    init(_ text: String) { self.text = text }
    func snapshot() -> [[String: Data]] { text.map { [["text": Data($0.utf8)]] } ?? [] }
    func write(_ text: String) -> Bool { self.text = text; changeCount += 1; return true }
    func restore(_ items: [[String: Data]]) { text = items.first?["text"].flatMap { String(data: $0, encoding: .utf8) }; changeCount += 1 }
}

private struct OpaqueDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
