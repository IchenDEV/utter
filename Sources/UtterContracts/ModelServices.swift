import Foundation
import UtterRuntime

package protocol ModelResourceAccess: Sendable {
    func withAccess<Value>(_ operation: () async throws -> Value) async throws -> Value
}

package enum ModelResourceError: Error, Equatable {
    case closed
}

package enum ModelServices {
    package static let resourceAccess = ServiceKey<any ModelResourceAccess>("models.resource-access")
}
