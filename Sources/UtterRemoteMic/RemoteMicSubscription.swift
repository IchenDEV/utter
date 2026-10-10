import Foundation

/// The two CoreBluetooth notifications the ATVV handshake needs before the host
/// may request capabilities.
package enum RemoteMicSubscription: Hashable {
    case audio
    case control
}
