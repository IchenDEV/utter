import AppKit

struct RecentInsertionAnchor {
    let processIdentifier: pid_t
    let element: AXUIElement
    let range: NSRange
    let text: String
}

