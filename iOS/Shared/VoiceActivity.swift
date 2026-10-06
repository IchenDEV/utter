import Foundation
import ActivityKit

struct VoiceActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable { var phase: String }
    let requestID: UUID
}
