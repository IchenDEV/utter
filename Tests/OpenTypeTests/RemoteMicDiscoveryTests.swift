import CoreBluetooth
import Foundation
import XCTest
@testable import OpenType

final class RemoteMicDeviceMatcherTests: XCTestCase {
    func testApprovedNamesMatchRegardlessOfCaseAndWhitespace() {
        for name in ["MI RC", " mi rc ", "Xiaomi Bluetooth Remote 2 Pro", "小米蓝牙遥控器2 Pro", "ARN9"] {
            XCTAssertTrue(RemoteMicDeviceMatcher.matches(name: name), name)
        }
    }

    func testOtherNamesAreRejected() {
        for name in [nil, "", "Xiaomi", "小米电视", "Magic Keyboard", "Android TV Remote"] {
            XCTAssertFalse(RemoteMicDeviceMatcher.matches(name: name), name ?? "nil")
        }
    }

    func testAdvertisingTheVoiceServiceMakesAnyNameACandidate() {
        let voice = CBUUID(string: RemoteMicProtocol.serviceUUID)
        XCTAssertTrue(RemoteMicDeviceMatcher.isCandidate(
            peripheralName: nil, advertisedName: nil, advertisedServiceUUIDs: [voice]
        ))
        XCTAssertTrue(RemoteMicDeviceMatcher.isCandidate(
            peripheralName: nil, advertisedName: "MI RC", advertisedServiceUUIDs: nil
        ))
        XCTAssertFalse(RemoteMicDeviceMatcher.isCandidate(
            peripheralName: "Headphones", advertisedName: nil, advertisedServiceUUIDs: [CBUUID(string: "180F")]
        ))
    }

    func testOnlyArn9ModelsUseLowNibbleFirst() {
        XCTAssertTrue(RemoteMicDeviceMatcher.usesLowNibbleFirst(modelNumber: "ARN9"))
        XCTAssertTrue(RemoteMicDeviceMatcher.usesLowNibbleFirst(modelNumber: "xiaomi-arn9-v2"))
        XCTAssertFalse(RemoteMicDeviceMatcher.usesLowNibbleFirst(modelNumber: "RC003"))
        XCTAssertFalse(RemoteMicDeviceMatcher.usesLowNibbleFirst(modelNumber: nil))
    }

    func testLowNibbleFirstDecodesTheSwappedByteLikeTheStandardOrder() {
        let standard = RemoteMicADPCMDecoder()
        let low = RemoteMicADPCMDecoder()
        low.lowNibbleFirst = true
        let payload = Data([0x1F, 0x93, 0x58, 0xA2])
        let swapped = Data(payload.map { ($0 << 4) | ($0 >> 4) })
        XCTAssertEqual(low.decode(payload), standard.decode(swapped))
    }

    func testSettingsTextKeysAreLocalized() {
        let keys = [
            RemoteMicSettingsText.discoveryKey(nil),
            RemoteMicSettingsText.discoveryKey(.connectedVoiceService),
            RemoteMicSettingsText.discoveryKey(.connectedHID),
            RemoteMicSettingsText.discoveryKey(.scan),
            RemoteMicSettingsText.captureKey(nil),
            RemoteMicSettingsText.captureKey(.remote),
            RemoteMicSettingsText.captureKey(.systemRemoteUnavailable),
            RemoteMicSettingsText.captureKey(.systemRemoteSilent),
            RemoteMicSettingsText.decoderKey(lowNibbleFirst: true),
            RemoteMicSettingsText.decoderKey(lowNibbleFirst: false),
        ]
        XCTAssertEqual(Set(keys).count, keys.count, "each state has its own key")
        for key in keys where key != "remote_mic.discovery.none" {
            XCTAssertNotEqual(L(key), key, "\(key) is missing from Localizable.strings")
        }
    }

    func testBluetoothSettingsLinkTargetsThePrivacyPaneWhenAccessWasRefused() {
        XCTAssertTrue(RemoteMicSettingsText.bluetoothSettingsURL(for: .unauthorized)
            .absoluteString.contains("Privacy_Bluetooth"))
        XCTAssertTrue(RemoteMicSettingsText.bluetoothSettingsURL(for: .scanning)
            .absoluteString.contains("BluetoothSettings"))
    }
}

private final class KnownRemoteTransportFake: XiaomiRemoteMicCentralTransport {
    let identity: AnyObject = NSObject()
    let delegateProxy: XiaomiRemoteMicCentralDelegateProxy
    var state: CBManagerState = .poweredOn
    var known: [CBUUID: [RemoteMicKnownPeripheral]] = [:]
    var scannedServices: [[CBUUID]] = []
    var connectCount = 0

    init(bridge: XiaomiRemoteMicBridge) {
        let proxy = XiaomiRemoteMicCentralDelegateProxy(bridge: bridge)
        delegateProxy = proxy
        proxy.bindManagerIdentity(identity)
    }

    func stopScan() {}
    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?) {
        scannedServices.append(services)
    }
    func connectedPeripherals(withServices services: [CBUUID]) -> [RemoteMicKnownPeripheral] {
        services.flatMap { known[$0] ?? [] }
    }
    func connect(to peripheral: AnyObject) {
        connectCount += 1
        delegateProxy.bindPeripheralIdentity(peripheral)
    }
    func cancel(peripheral: AnyObject) {}
}

@MainActor
final class RemoteMicKnownRemoteTests: XCTestCase {
    private func makeBridge(
        configure: @escaping (KnownRemoteTransportFake) -> Void
    ) -> (XiaomiRemoteMicBridge, KnownRemoteTransportFake) {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        var created: KnownRemoteTransportFake?
        bridge.installCentralTransportFactoryForTesting { [weak bridge] in
            let transport = KnownRemoteTransportFake(bridge: bridge!)
            configure(transport)
            created = transport
            return transport
        }
        bridge.activate()
        bridge.simulateCentralStateForTesting(.poweredOn)
        return (bridge, created!)
    }

    func testRemoteAlreadyConnectedInSystemSettingsIsConnectedWithoutScanning() {
        let (bridge, transport) = makeBridge { transport in
            transport.known[CBUUID(string: RemoteMicProtocol.serviceUUID)] = [
                RemoteMicKnownPeripheral(identity: NSObject(), name: "MI RC"),
            ]
        }
        XCTAssertEqual(transport.connectCount, 1)
        XCTAssertTrue(transport.scannedServices.isEmpty, "a connected remote must not wait for an advertisement")
        XCTAssertEqual(bridge.state, .connecting)
        XCTAssertEqual(bridge.diagnostics.discovery, .connectedVoiceService)
    }

    func testRemoteConnectedAsHIDKeyboardIsFoundByName() {
        let (bridge, transport) = makeBridge { transport in
            transport.known[RemoteMicDeviceMatcher.hidServiceUUID] = [
                RemoteMicKnownPeripheral(identity: NSObject(), name: "Magic Keyboard"),
                RemoteMicKnownPeripheral(identity: NSObject(), name: "小米蓝牙遥控器2 Pro"),
            ]
        }
        XCTAssertEqual(transport.connectCount, 1)
        XCTAssertEqual(bridge.diagnostics.discovery, .connectedHID)
    }

    func testUnrelatedConnectedDevicesFallBackToAnUnfilteredScan() {
        let (bridge, transport) = makeBridge { transport in
            transport.known[RemoteMicDeviceMatcher.hidServiceUUID] = [
                RemoteMicKnownPeripheral(identity: NSObject(), name: "Magic Keyboard"),
            ]
        }
        XCTAssertEqual(transport.connectCount, 0)
        XCTAssertEqual(transport.scannedServices.count, 1)
        XCTAssertEqual(transport.scannedServices.first?.isEmpty, true, "name-only advertisements must still be seen")
        XCTAssertEqual(bridge.state, .scanning)
    }

    func testModelNumberSelectsTheNibbleOrderForTheCurrentAttempt() throws {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        _ = bridge.simulateConnectForTesting()
        let proxy = try XCTUnwrap(bridge.callbackProxyForTesting())

        proxy.deliverForTesting(.modelNumber(Data("ARN9\n".utf8)))

        XCTAssertEqual(bridge.diagnostics.modelNumber, "ARN9")
        XCTAssertTrue(bridge.diagnostics.lowNibbleFirst)
    }

    func testModelNumberFromASupersededAttemptIsIgnored() throws {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        _ = bridge.simulateConnectForTesting()
        let oldProxy = try XCTUnwrap(bridge.callbackProxyForTesting())
        _ = bridge.simulateReconnectSamePeripheralForTesting()

        oldProxy.deliverForTesting(.modelNumber(Data("ARN9".utf8)))

        XCTAssertNil(bridge.diagnostics.modelNumber)
        XCTAssertFalse(bridge.diagnostics.lowNibbleFirst)
    }

    func testNoteCaptureRecordsTheLatestSource() {
        let bridge = XiaomiRemoteMicBridge()
        bridge.noteCapture(.systemRemoteUnavailable)
        bridge.noteCapture(.remote)
        XCTAssertEqual(bridge.diagnostics.lastCapture, .remote)
    }
}
