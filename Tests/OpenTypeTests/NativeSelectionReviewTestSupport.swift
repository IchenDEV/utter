import AppKit
import ApplicationServices
import SwiftUI
import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
enum NativeSelectionReviewTestSupport {
    private static let finishApplicationLaunch: Void = NSApplication.shared.finishLaunching()

    // SwiftUI's virtual children need not conform to the complete NSAccessibility protocol.
    struct Node {
        let object: NSObject
        func accessibilityRole() -> NSAccessibility.Role? {
            (object as AnyObject).accessibilityRole?()
        }
        func accessibilityLabel() -> String? {
            (object as AnyObject).accessibilityLabel?()
        }
        func accessibilityValue() -> Any? { (object as AnyObject).accessibilityValue?() }
        var textValue: String {
            let value = accessibilityValue()
            return (value as? String) ?? (value as? NSAttributedString)?.string ?? ""
        }
        func isAccessibilityEnabled() throws -> Bool {
            try XCTUnwrap((object as AnyObject).isAccessibilityEnabled?())
        }
        func accessibilityFrame() -> NSRect {
            (object as AnyObject).accessibilityFrame?() ?? .zero
        }
        func accessibilityPerformPress() throws -> Bool {
            try XCTUnwrap((object as AnyObject).accessibilityPerformPress?())
        }
    }

    static func panel<Content: View>(_ content: Content, width: CGFloat, height: CGFloat,
                                    accessibility: Bool = true) async throws -> NSPanel {
        _ = NSApplication.shared
        _ = finishApplicationLaunch
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        do {
            panel.becomesKeyOnlyIfNeeded = true
            panel.contentView = NSHostingView(rootView: content.environmentObject(AppState())
                .background(Color(nsColor: panel.backgroundColor)))
            panel.orderFrontRegardless()
            try await settle(panel)
            if accessibility {
                // SwiftUI creates its virtual tree lazily after a public AX client query.
                let pid = getpid()
                let status = await Task.detached { () -> (timeout: Int32, query: Int32) in
                    let application = AXUIElementCreateApplication(pid)
                    let timeout = AXUIElementSetMessagingTimeout(application, 2).rawValue
                    guard timeout == AXError.success.rawValue else { return (timeout, AXError.failure.rawValue) }
                    var children: CFTypeRef?
                    return (timeout, AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &children).rawValue)
                }.value
                try NativeE2EUI.record("native-ax-activation-\(panel.windowNumber)",
                    ["targetPID": pid, "ownProcessOnly": true, "status": status.query,
                     "timeoutStatus": status.timeout, "permissionRequests": 0])
                XCTAssertEqual(status.timeout, AXError.success.rawValue)
                if status.query == AXError.apiDisabled.rawValue {
                    throw XCTSkip("Public AX self-query is disabled; no permission is requested. VoiceOver remains unverified.")
                }
                XCTAssertEqual(status.query, AXError.success.rawValue)
                try await settle(panel)
            }
            try NativeE2EUI.record("native-tree-\(panel.windowNumber)", ["nodes": nodes(panel).map {
                ["class": NSStringFromClass(type(of: $0.object)), "role": $0.accessibilityRole()?.rawValue ?? "",
                 "label": $0.accessibilityLabel() ?? "", "value": String(describing: $0.accessibilityValue() ?? ""),
                 "navigationChildren": navigationChildren($0.object)?.count ?? -1,
                 "structuralChildren": ($0.object as AnyObject).accessibilityChildren?()?.count ?? -1,
                 "frame": NSStringFromRect($0.accessibilityFrame())]
            }])
            return panel
        } catch {
            panel.close()
            throw error
        }
    }

    static func settle(_ panel: NSWindow) async throws {
        try await Task.sleep(for: .milliseconds(30))
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
    }

    static func nodes(_ object: Any, depth: Int = 0) -> [Node] {
        guard depth < 24, let object = object as? NSObject else { return [] }
        let ordered = navigationChildren(object)
        let children = ordered.flatMap { $0.isEmpty ? nil : $0 }
            ?? (object as AnyObject).accessibilityChildren?() ?? []
        return [Node(object: object)] + children.flatMap { nodes($0, depth: depth + 1) }
    }

    private static func navigationChildren(_ object: NSObject) -> [Any]? {
        // Preserve the public NSArray: AppKit scroller children do not match Swift's imported concrete element type.
        let getter = NSSelectorFromString("accessibilityChildrenInNavigationOrder")
        guard object.responds(to: getter) else { return nil }
        return object.perform(getter)?.takeUnretainedValue() as? [Any]
    }

    static func button(_ label: String, in panel: NSWindow) throws -> Node {
        try XCTUnwrap(nodes(panel).first { $0.accessibilityRole() == .button && $0.accessibilityLabel() == label })
    }

    static func text(_ marker: String, in panel: NSWindow) throws -> Node {
        try XCTUnwrap(nodes(panel).last {
            $0.textValue.contains(marker)
                || ($0.accessibilityLabel() ?? "").contains(marker)
        })
    }

    static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    static func scroll(by delta: CGFloat, in scroll: NSScrollView) throws {
        let document = try XCTUnwrap(scroll.documentView)
        document.scroll(NSPoint(x: scroll.contentView.bounds.minX, y: scroll.contentView.bounds.minY + delta))
        scroll.layoutSubtreeIfNeeded()
    }

    static func endIsVisible(_ node: Node, in scroll: NSScrollView) -> Bool {
        guard let window = scroll.window else { return false }
        let viewport = window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        let frame = node.accessibilityFrame()
        let tail = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(32, frame.height))
        return viewport.insetBy(dx: -1, dy: -1).contains(tail)
    }

    static func assertVisible(_ node: Node, in panel: NSWindow,
                              file: StaticString = #filePath, line: UInt = #line) {
        let frame = node.accessibilityFrame()
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertTrue(panel.frame.insetBy(dx: -1, dy: -1).contains(frame),
            "Control outside panel: \(frame), panel: \(panel.frame)", file: file, line: line)
    }
}
