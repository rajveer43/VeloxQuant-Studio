import Foundation

/// Mirrors `MethodInfo.to_dict()` in `veloxquant_mlx/cache/registry.py`.
/// Decoded directly from `veloxquant methods --json`, so field names match
/// the Python schema exactly — the registry is the source of truth, not this
/// struct.
struct QuantizationMethod: Identifiable, Codable, Hashable {
    var id: String { name }

    let name: String
    let family: MethodFamily
    let serveTier: ServeTier
    let serveTierLabel: String
    let isServable: Bool
    let blurb: String
    let configFields: [String]
    let fieldSchema: [ConfigField]
    let coverage: String
    let coverageLabel: String
    let paperDeviation: String?
    let isAdapted: Bool
    let unsupportedReason: String?
    let docsURLString: String?

    /// `docs_url` is `nil` when `registry.py` has no published doc page for
    /// this method (most of them, currently) — decoded as `String` rather
    /// than `URL` since Foundation's `URL` decoding isn't worth the failure
    /// mode for a value we only ever use to open a link.
    var docsURL: URL? { docsURLString.flatMap(URL.init(string:)) }

    /// `serveTierLabel` collapses `honest_bytes`, `accounting_only`, and
    /// `not_trimmable` into the same "available" string (registry.py's
    /// `ServeTier.label`), so a method whose byte savings are estimated
    /// rather than measured, or whose job can't be trimmed on stop/resume,
    /// looks identical in the picker to a fully-honest method. This surfaces
    /// the distinction the generic banner otherwise hides. See issue #43.
    var serveTierCaption: String? {
        switch serveTier {
        case .accountingOnly:
            "Reported savings are estimated, not measured from live cache bytes."
        case .notTrimmable:
            "This method can't trim its prompt cache — stopping a job may not resume cleanly."
        case .honestBytes, .crashes:
            nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, family
        case serveTier = "serve_tier"
        case serveTierLabel = "serve_tier_label"
        case isServable = "is_servable"
        case blurb
        case configFields = "config_fields"
        case fieldSchema = "field_schema"
        case coverage
        case coverageLabel = "coverage_label"
        case paperDeviation = "paper_deviation"
        case isAdapted = "is_adapted"
        case unsupportedReason = "unsupported_reason"
        case docsURLString = "docs_url"
    }

    /// Mirrors `ServeTier` in `registry.py`. `crashes` was previously
    /// (incorrectly) modeled as `unsupported` here, which never matched the
    /// wire value `"crashes"` — any method in that tier would have failed to
    /// decode and dropped the whole `methods --json` response.
    enum ServeTier: String, Codable {
        case honestBytes = "honest_bytes"
        case accountingOnly = "accounting_only"
        case notTrimmable = "not_trimmable"
        case crashes = "crashes"

        var isServable: Bool {
            self == .honestBytes || self == .accountingOnly || self == .notTrimmable
        }
    }
}

/// Mirrors `MethodFamily` in `registry.py` — what the method primarily does
/// to the cache. Drives the method browser's filter control.
///
/// Decodes leniently: an unrecognized raw value (e.g. a future `transfer`
/// family for cross-model KV transfer, which works structurally differently
/// from every cache method here — see issue #42) becomes `.unknown` rather
/// than failing to decode, since `[QuantizationMethod]` decode is all-or-
/// nothing and one bad `family` would otherwise drop the entire method list.
enum MethodFamily: Codable, CaseIterable, Identifiable, Hashable {
    case quantization
    case eviction
    case hybrid
    case unknown

    static var allCases: [MethodFamily] { [.quantization, .eviction, .hybrid] }

    var id: String { rawValue }

    private var rawValue: String {
        switch self {
        case .quantization: "quantization"
        case .eviction: "eviction"
        case .hybrid: "hybrid"
        case .unknown: "unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "quantization": self = .quantization
        case "eviction": self = .eviction
        case "hybrid": self = .hybrid
        default: self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var label: String {
        switch self {
        case .quantization: "Quantization"
        case .eviction: "Eviction"
        case .hybrid: "Hybrid"
        case .unknown: "Unknown"
        }
    }
}

/// Mirrors `describe_field()` in `registry.py` — one entry per config knob a
/// method exposes (e.g. `kivi_group_size`, `svdq_rank`).
struct ConfigField: Identifiable, Codable, Hashable {
    var id: String { name }

    let name: String
    let type: String
    let optional: Bool
    let defaultValue: JSONValue?
    let help: String?

    enum CodingKeys: String, CodingKey {
        case name, type, optional
        case defaultValue = "default"
        case help
    }
}

/// A minimal JSON value box for heterogeneous `default` fields coming back
/// from Python (int, float, bool, string, or null).
enum JSONValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: ""
        }
    }
}

/// Response envelope for `veloxquant methods --json`.
struct MethodsResponse: Codable {
    let schemaVersion: Int
    let defaultServeMethod: String
    let accountingOnly: Bool
    let accountingNote: String?
    let methods: [QuantizationMethod]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case defaultServeMethod = "default_serve_method"
        case accountingOnly = "accounting_only"
        case accountingNote = "accounting_note"
        case methods
    }
}
