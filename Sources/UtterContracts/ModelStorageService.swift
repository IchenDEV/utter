import Foundation
import UtterRuntime

package struct DeviceDisplayInformation: Equatable, Sendable {
    package let chipDisplayName: String
    package let ramDisplayText: String
    package let gpuDisplayText: String
    package let diskAvailableText: String
    package init(chip: String, ram: String, gpu: String, disk: String) {
        chipDisplayName = chip; ramDisplayText = ram; gpuDisplayText = gpu; diskAvailableText = disk
    }
}

@MainActor
package protocol ModelStorageService: AnyObject {
    var root: URL { get }
    var defaultRoot: URL { get }
    var device: DeviceDisplayInformation { get }
    func localWhisperURL(_ id: String) -> URL?
    func localLLMURL(_ id: String) -> URL?
    func directorySize(at url: URL) -> Int64
    func whisperModelIsComplete(at url: URL) -> Bool
    func llmRepoIsComplete(at url: URL) -> Bool
    func estimatedDownloadBytes(from text: String) -> Int64?
}

extension ModelServices {
    package static let storage = ServiceKey<any ModelStorageService>("models.storage")
}
