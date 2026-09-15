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
    /// rather than measured, or whose cache can't be trimmed, looks
    /// identical in the picker to a fully-honest method. This surfaces the
    /// distinction the generic banner otherwise hides. See issue #43.
    ///
    /// `notTrimmable`'s caption was previously worded around stop/resume,
    /// which isn't what `is_trimmable() == False` actually affects (see
    /// `registry.py`'s `_run_probe`, and issue #3's `amc` verification):
    /// `mlx_lm.server`'s LRU prompt cache only reuses a *trimmed* longer
    /// prefix (`fetch_nearest_cache` -> `can_trim_prompt_cache`) — a
    /// not-trimmable method skips that path, so every request reprocesses
    /// its full prompt rather than reusing an overlapping prefix from an
    /// earlier request in the same server session.
    var serveTierCaption: String? {
        switch serveTier {
        case .accountingOnly:
            "Reported savings are estimated, not measured from live cache bytes."
        case .notTrimmable:
            "This method can't reuse a cached prompt prefix across requests — every request reprocesses its full prompt from scratch."
        case .honestBytes, .crashes:
            nil
        }
    }

    /// Whether this method's cache class actually reads `bit_width_inlier`
    /// (`serve.py`'s `build_config()` always sets it from the Network
    /// section's "Bit width" stepper via `--bits`, regardless of method).
    ///
    /// For a *curated* method (one with its own `_CONFIG_FIELDS` entry —
    /// e.g. `kitty`, issue #12) `configFields` alone is the source of truth:
    /// its explicit list simply omits `bit_width_inlier` when unused.
    ///
    /// That stops being true for an *uncurated* method: registry.py's
    /// `_default_config_fields()` (issue #9) unconditionally prepends
    /// `_GENERIC_FIELDS` (`bit_width_inlier`, `seed`) as a CLI-override
    /// baseline before appending the method's real prefix-matched fields —
    /// a deliberate choice so `--set bit_width_inlier=...` still validates
    /// for any method, curated or not. That baseline means every uncurated
    /// method's `configFields` contains `bit_width_inlier` whether or not
    /// its cache class reads it. Verified against every uncurated cache
    /// class's `__init__` (issue #15, `knorm`'s fp16-only cache being the
    /// trigger): none of them reference `bit_width_inlier` at all, so this
    /// exclusion list is a hand-verified snapshot, not a guess — re-check it
    /// when a listed method gets curated or a new uncurated one ships.
    private static let methodsIgnoringNetworkBitWidth: Set<String> = [
        "cachegen", "minicache", "gear", "zipcache", "snapkv", "streaming_llm",
        "h2o", "tova", "pyramidkv", "squeeze", "chunkkv", "cam", "xkv",
        "nsnquant", "knorm", "skvq", "qfilters", "keyformer", "morphkv",
        "kvzip", "kvtc", "curdkv", "nestedkv", "amc", "a2ats", "anchorkv",
    ]

    var usesNetworkBitWidth: Bool {
        configFields.contains("bit_width_inlier")
            && !Self.methodsIgnoringNetworkBitWidth.contains(name)
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
/// from Python (int, float, bool, string, array, or null).
enum JSONValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
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
        } else if let array = try? container.decode([JSONValue].self) {
            // Fields like kvtc_bit_choices / svdq_bit_schedule are Python
            // tuples, which json.dumps serializes as plain JSON arrays —
            // without this case the decoder fell through to .null, silently
            // discarding a real default (e.g. [0, 1, 2, 3, 4, 6, 8]) rather
            // than losing the whole method's decode (see #17).
            self = .array(array)
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
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .array(let value): "[" + value.map(\.displayString).joined(separator: ", ") + "]"
        case .null: ""
        }
    }

    /// Value to prefill into the parameter editor's text field — distinct
    /// from `displayString` only for `.array`. `--set`'s wire format for an
    /// array-typed field (`svdq_bit_schedule`, `kvtc_bit_choices`) is bare
    /// comma-separated ints (`serve.py`'s `parse_overrides`: `raw.split(",")`
    /// then `int(x)` per element, no brackets or spaces tolerated) — feeding
    /// it `displayString`'s bracketed `"[8, 4, 2, ...]"` fails to parse on
    /// the very first token (`"[8"`). Before this existed, both forms
    /// crashed the server either way (`--set` didn't special-case arrays at
    /// all — see issue #30), so the mismatch was invisible; now that the
    /// backend parses arrays correctly, this is what actually round-trips.
    var cliOverrideString: String {
        switch self {
        case .array(let value): value.map(\.displayString).joined(separator: ",")
        default: displayString
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
