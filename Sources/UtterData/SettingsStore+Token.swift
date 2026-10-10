import Foundation
#if canImport(Security)
import Security
#endif

extension SettingsStore {
    static func generateDeveloperHTTPToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        #endif
        bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
    }
}
