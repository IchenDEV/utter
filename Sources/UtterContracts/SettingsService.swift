import Foundation
import UtterRuntime

package protocol SettingsService: AnyObject {
    var values: SettingsValues { get }
    func update(_ mutation: (inout SettingsValues) -> Void)
    func observe(_ callback: @escaping (SettingsValues) -> Void) -> UUID
    func removeObserver(_ id: UUID)
    func resetDeveloperHTTPToken()
}

package enum DataLocations {
    package static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(ProductBrand.applicationSupportDirectoryName, isDirectory: true)
    }

    package static var models: URL {
        applicationSupport.appendingPathComponent("huggingface", isDirectory: true)
    }
}
