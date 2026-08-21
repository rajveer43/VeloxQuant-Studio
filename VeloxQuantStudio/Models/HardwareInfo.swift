import Foundation

/// Snapshot of the local Mac's hardware, read via `sysctl`/`ProcessInfo`.
/// Purely local — no Python round-trip needed for this.
struct HardwareInfo: Equatable {
    let chipName: String
    let chipFamily: MacChipFamily?
    let performanceCoreCount: Int
    let efficiencyCoreCount: Int
    let gpuCoreCount: Int?
    let unifiedMemoryBytes: UInt64
    let macOSVersion: String

    var unifiedMemoryGB: Double {
        Double(unifiedMemoryBytes) / 1_073_741_824
    }

    static let placeholder = HardwareInfo(
        chipName: "Unknown",
        chipFamily: nil,
        performanceCoreCount: 0,
        efficiencyCoreCount: 0,
        gpuCoreCount: nil,
        unifiedMemoryBytes: 0,
        macOSVersion: "Unknown"
    )
}

/// Chip family as understood by `veloxquant recommend --chip`. Pro/Max/Ultra
/// are RAM tiers, not separate chips, per `mac_recommender.py`.
enum MacChipFamily: String, CaseIterable {
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case m5 = "M5"

    /// `veloxquant recommend` only accepts M1–M4 today; newer chips fall
    /// back to the closest known generation rather than failing the call.
    var recommenderArgument: String {
        switch self {
        case .m5: MacChipFamily.m4.rawValue
        default: rawValue
        }
    }
}
