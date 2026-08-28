import Foundation
import IOKit

enum DeviceCapability {
    struct Info: Sendable {
        let chipName: String
        let totalRAMGB: Double
        let gpuCoreCount: Int
        let neuralEngineCoreCount: Int
        let availableDiskGB: Double
        let totalDiskGB: Double
    }

    static let current: Info = {
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

    enum Compatibility: Sendable {
        case compatible
        case marginal(String)
        case incompatible(String)
    }

    struct ModelRequirements: Sendable {
        let minRAMGB: Double
        let recommendedRAMGB: Double
        let diskGB: Double
    }

    static func requirements(for modelID: String, downloadSizeBytes: Int64?) -> ModelRequirements {
        if let known = knownRequirements[modelID] { return known }
        let diskGB = downloadSizeBytes.map { Double($0) / 1_073_741_824 } ?? 0
        let ramNeeded = max(diskGB * 1.2, 1)
        return ModelRequirements(
            minRAMGB: ramNeeded,
            recommendedRAMGB: ramNeeded * 1.5,
            diskGB: diskGB
        )
    }

    static func check(
        modelID: String,
        downloadSizeBytes: Int64?
    ) -> Compatibility {
        let reqs = requirements(for: modelID, downloadSizeBytes: downloadSizeBytes)
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

    static func recommendedModelID(from candidates: [String]) -> String? {
        let ram = current.totalRAMGB
        for id in candidates.reversed() {
            if let reqs = knownRequirements[id], ram >= reqs.recommendedRAMGB {
                return id
            }
        }
        return candidates.first
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

    // MARK: - Known Model Requirements (RAM needed at runtime, disk for download)

    private static let knownRequirements: [String: ModelRequirements] = [
        "mlx-community/Qwen3.5-0.8B-MLX-4bit":
            ModelRequirements(minRAMGB: 2, recommendedRAMGB: 4, diskGB: 0.7),
        "mlx-community/Qwen3.5-2B-4bit":
            ModelRequirements(minRAMGB: 4, recommendedRAMGB: 6, diskGB: 1.8),
        "mlx-community/Qwen3.5-9B-5bit":
            ModelRequirements(minRAMGB: 10, recommendedRAMGB: 12, diskGB: 7.1),
        "mlx-community/Qwen3-30B-A3B-4bit":
            ModelRequirements(minRAMGB: 12, recommendedRAMGB: 18, diskGB: 17.2),
        "mlx-community/Qwen3.5-35B-A3B-4bit":
            ModelRequirements(minRAMGB: 16, recommendedRAMGB: 24, diskGB: 20.5),
        "mlx-community/Qwen2.5-0.5B-Instruct-4bit":
            ModelRequirements(minRAMGB: 2, recommendedRAMGB: 4, diskGB: 0.3),
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit":
            ModelRequirements(minRAMGB: 2, recommendedRAMGB: 4, diskGB: 0.9),
        "mlx-community/Qwen2.5-3B-Instruct-4bit":
            ModelRequirements(minRAMGB: 4, recommendedRAMGB: 6, diskGB: 1.8),
        "mlx-community/Qwen3-0.6B-4bit":
            ModelRequirements(minRAMGB: 2, recommendedRAMGB: 4, diskGB: 0.4),
        "mlx-community/Qwen3-1.7B-4bit":
            ModelRequirements(minRAMGB: 2, recommendedRAMGB: 4, diskGB: 1.0),
        "mlx-community/Qwen3-4B-4bit":
            ModelRequirements(minRAMGB: 4, recommendedRAMGB: 6, diskGB: 2.3),
        "mlx-community/gemma-4-e2b-it-4bit":
            ModelRequirements(minRAMGB: 6, recommendedRAMGB: 8, diskGB: 3.6),
        "mlx-community/gemma-4-e4b-it-4bit":
            ModelRequirements(minRAMGB: 8, recommendedRAMGB: 10, diskGB: 5.3),
        "mlx-community/gemma-3-1b-it-4bit":
            ModelRequirements(minRAMGB: 2, recommendedRAMGB: 4, diskGB: 0.8),
        "mlx-community/gemma-3-4b-it-4bit":
            ModelRequirements(minRAMGB: 6, recommendedRAMGB: 8, diskGB: 3.5),
        "mlx-community/gemma-3-12b-it-4bit":
            ModelRequirements(minRAMGB: 12, recommendedRAMGB: 16, diskGB: 8.1),
        "mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit":
            ModelRequirements(minRAMGB: 48, recommendedRAMGB: 64, diskGB: 61.2),
        "mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit":
            ModelRequirements(minRAMGB: 128, recommendedRAMGB: 192, diskGB: 226.0),
    ]
}

extension DeviceCapability.Info {
    var chipDisplayName: String { chipName }
    var ramDisplayText: String { String(format: "%.0f GB", totalRAMGB) }
    var gpuDisplayText: String { "\(gpuCoreCount)-core GPU" }
    var diskAvailableText: String { String(format: "%.1f GB", availableDiskGB) }
}

extension DeviceCapability.Compatibility {
    var isCompatible: Bool {
        if case .compatible = self { return true }
        return false
    }

    var isMarginal: Bool {
        if case .marginal = self { return true }
        return false
    }

    var isIncompatible: Bool {
        if case .incompatible = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .compatible: return nil
        case .marginal(let msg), .incompatible(let msg): return msg
        }
    }
}
