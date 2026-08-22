import Foundation

/// A named, curated shortcut over method + bit width + config overrides —
/// the "pick this if you don't know what to pick" entries from
/// VeloxQuant-MLX#35. Static and Swift-only (unlike `QuantizationMethod`,
/// which is decoded from the registry): the exact set is a product/UX
/// decision, not something the CLI needs to own. Each preset is validated
/// against the live registry before being shown (see
/// `QuantizationViewModel.availablePresets`), so a rename/removal upstream
/// hides the preset instead of offering a method that no longer exists.
struct MethodPreset: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let methodName: String
    let bitWidth: Int
    let parameterOverrides: [String: String]
    let blurb: String

    static let all: [MethodPreset] = [
        MethodPreset(
            name: "Balanced (RVQ-1bit)",
            methodName: "turboquant_rvq",
            bitWidth: 1,
            parameterOverrides: [:],
            blurb: "The serve default. Good compression with minimal fidelity loss for everyday chat and coding."
        ),
        MethodPreset(
            name: "KIVI-2bit",
            methodName: "kivi",
            bitWidth: 2,
            parameterOverrides: [:],
            blurb: "Higher fidelity than 1-bit methods at a more modest compression ratio — a safer default for longer sessions."
        ),
        MethodPreset(
            name: "Max compression (VecInfer-1bit)",
            methodName: "vecinfer",
            bitWidth: 1,
            parameterOverrides: [:],
            blurb: "Prioritizes the smallest footprint. Best for constrained-memory setups where some quality loss is acceptable."
        ),
    ]
}
