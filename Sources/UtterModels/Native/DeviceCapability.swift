import UtterContracts
import Foundation
import IOKit

package enum DeviceCapability {
    package struct Info: Sendable {
        package let chipName: String
        package let totalRAMGB: Double
        package let gpuCoreCount: Int
        package let neuralEngineCoreCount: Int
        package let availableDiskGB: Double
        package let totalDiskGB: Double
    }

    package static let current: Info = {
        let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let (chipName, gpuCores, neCores) = readAppleSiliconInfo()
        let (availDisk, totalDisk) = diskSpace()
        return Info(
            chipName: chipName,
            totalRAMGB: ram,
            gpuCoreCount: gpuCores,
            neuralEngineCoreCount: neCores,
            availableDiskGB: availDisk,
            totalDiskGB: totalDisk
        )
    }()

    // MARK: - Model Compatibility

    package typealias Compatibility = ModelCompatibility

    package struct ModelRequirements: Sendable {
        package let minRAMGB: Double
        package let recommendedRAMGB: Double
        package let diskGB: Double
    }

    package static func requirements(downloadSizeBytes: Int64?, memory: ModelMemoryRequirements?) -> ModelRequirements {
        let diskGB = downloadSizeBytes.map { Double($0) / 1_073_741_824 } ?? 0
        let ramNeeded = max(diskGB * 1.2, memory?.minimumGB ?? 1)
        return ModelRequirements(
            minRAMGB: ramNeeded,
            recommendedRAMGB: max(ramNeeded, memory?.recommendedGB ?? ramNeeded * 1.5),
            diskGB: diskGB
        )
    }

    package static func check(
        modelID: String,
        downloadSizeBytes: Int64?, memoryRequirements: ModelMemoryRequirements? = nil
    ) -> Compatibility {
        let reqs = requirements(downloadSizeBytes: downloadSizeBytes, memory: memoryRequirements)
        let info = current

        if reqs.diskGB > 0, info.availableDiskGB < reqs.diskGB * 1.1 {
            return .incompatible(L("device.insufficient_disk"))
        }
        if info.totalRAMGB < reqs.minRAMGB {
            return .incompatible(L("device.insufficient_ram"))
        }
        if info.totalRAMGB < reqs.recommendedRAMGB {
            return .marginal(L("device.marginal_ram"))
        }
        return .compatible
    }

    package static func tier(for artifact: ModelArtifact, memoryGB: Double = current.totalRAMGB) -> CatalogModelTier {
        guard artifact.tier == .recommended else { return artifact.tier }
        guard let requirements = artifact.memoryRequirements, requirements.isValid, memoryGB >= requirements.recommendedGB else {
            return .standard
        }
        return .recommended
    }

    // MARK: - Hardware Detection

    private static func readAppleSiliconInfo() -> (chipName: String, gpuCores: Int, neCores: Int) {
        var chipName = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        if chipName.hasPrefix("Apple ") {
            chipName = String(chipName.dropFirst(6))
        }

        let gpuCores = ioRegistryInt(className: "AGXAccelerator", key: "gpu-core-count")
            ?? ioRegistryInt(className: "AGXAcceleratorG13G", key: "gpu-core-count")
            ?? gpuCoresFromChipName(chipName)
        let neCores = neuralEngineCoresFromChipName(chipName)
        return (chipName, gpuCores, neCores)
    }

    private static func diskSpace() -> (available: Double, total: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else { return (0, 0) }
        let avail = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        let total = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
        return (avail / 1_073_741_824, total / 1_073_741_824)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    private static func ioRegistryInt(className: String, key: String) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(className),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            if let cfValue = IORegistryEntryCreateCFProperty(
                entry, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? NSNumber {
                return cfValue.intValue
            }
        }
        return nil
    }

    private static func gpuCoresFromChipName(_ name: String) -> Int {
        let n = name.lowercased()
        if n.contains("ultra") { return 76 }
        if n.contains("max") { return 40 }
        if n.contains("pro") { return 18 }
        return 10
    }

    private static func neuralEngineCoresFromChipName(_ name: String) -> Int {
        let n = name.lowercased()
        if n.contains("m4") || n.contains("m3") { return 16 }
        return 16
    }


}

extension DeviceCapability.Info {
    package var chipDisplayName: String { chipName }
    package var ramDisplayText: String { String(format: "%.0f GB", totalRAMGB) }
    package var gpuDisplayText: String { "\(gpuCoreCount)-core GPU" }
    package var diskAvailableText: String { String(format: "%.1f GB", availableDiskGB) }
}
