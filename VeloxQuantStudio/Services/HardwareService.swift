import Foundation
#if canImport(IOKit)
import IOKit
#endif

protocol HardwareServiceProtocol: Sendable {
    func currentHardware() -> HardwareInfo
}

/// Reads Apple Silicon chip name, core counts, and unified memory via
/// `sysctl`. No MLX/Python dependency — this is pure macOS.
struct HardwareService: HardwareServiceProtocol {
    func currentHardware() -> HardwareInfo {
        let chipName = sysctlString("machdep.cpu.brand_string") ?? fallbackChipName()
        let memoryBytes = sysctlUInt64("hw.memsize") ?? UInt64(ProcessInfo.processInfo.physicalMemory)
        let perfCores = sysctlInt("hw.perflevel0.physicalcpu") ?? 0
        let effCores = sysctlInt("hw.perflevel1.physicalcpu") ?? 0

        return HardwareInfo(
            chipName: chipName,
            chipFamily: detectChipFamily(from: chipName),
            performanceCoreCount: perfCores,
            efficiencyCoreCount: effCores,
            gpuCoreCount: nil,
            unifiedMemoryBytes: memoryBytes,
            macOSVersion: macOSVersionString()
        )
    }

    private func fallbackChipName() -> String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Unknown (non-Apple Silicon)"
        #endif
    }

    private func detectChipFamily(from chipName: String) -> MacChipFamily? {
        // "Apple M3 Pro", "Apple M2 Max", "Apple M1", etc.
        for family in MacChipFamily.allCases where chipName.contains(family.rawValue) {
            return family
        }
        return nil
    }

    private func macOSVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    // MARK: - sysctl helpers

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
