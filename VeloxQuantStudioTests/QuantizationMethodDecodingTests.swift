import Foundation
import Testing
@testable import VeloxQuantStudio

struct QuantizationMethodDecodingTests {
    @Test func decodesRealRegistryShape() throws {
        let json = """
        {
          "schema_version": 1,
          "default_serve_method": "turboquant_rvq",
          "accounting_only": true,
          "accounting_note": "Compression is accounting-only.",
          "methods": [
            {
              "name": "turboquant_rvq",
              "family": "quantization",
              "serve_tier": "accounting_only",
              "serve_tier_label": "Serves (accounting-only)",
              "is_servable": true,
              "blurb": "Residual vector quantization; the balanced default for serving.",
              "config_fields": ["bit_width_inlier", "seed"],
              "field_schema": [
                {"name": "bit_width_inlier", "type": "int", "optional": false, "default": 2, "help": "Bits per element."},
                {"name": "seed", "type": "int", "optional": false, "default": 42, "help": null}
              ],
              "coverage": "keys_only",
              "coverage_label": "Keys only",
              "paper_deviation": null,
              "is_adapted": false,
              "unsupported_reason": null,
              "docs_url": "https://veloxquant-mlx.netlify.app/docs/algorithms/rvq"
            },
            {
              "name": "turboquant_prod",
              "family": "quantization",
              "serve_tier": "crashes",
              "serve_tier_label": "Crashes",
              "is_servable": false,
              "blurb": "TurboQuant product quantization; the library default for offline study.",
              "config_fields": [],
              "field_schema": [],
              "coverage": "none",
              "coverage_label": "Not reported",
              "paper_deviation": null,
              "is_adapted": false,
              "unsupported_reason": "does not subclass mlx_lm KVCache",
              "docs_url": null
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(MethodsResponse.self, from: data)

        #expect(response.defaultServeMethod == "turboquant_rvq")
        #expect(response.methods.count == 2)

        let servable = try #require(response.methods.first { $0.name == "turboquant_rvq" })
        #expect(servable.isServable)
        #expect(servable.fieldSchema.count == 2)
        #expect(servable.docsURL == URL(string: "https://veloxquant-mlx.netlify.app/docs/algorithms/rvq"))

        let unsupported = try #require(response.methods.first { $0.name == "turboquant_prod" })
        #expect(!unsupported.isServable)
        #expect(unsupported.unsupportedReason != nil)
        #expect(unsupported.serveTier == .crashes)
        #expect(unsupported.docsURL == nil)
    }

    @Test func decodesDocsURLAndFamily() throws {
        let json = """
        {
          "name": "kivi",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "Serves (accounting-only)",
          "is_servable": true,
          "blurb": "KIVI: asymmetric per-group min/max quantization, key-per-channel.",
          "config_fields": [],
          "field_schema": [],
          "coverage": "keys_and_values",
          "coverage_label": "Keys and values",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": null,
          "docs_url": "https://veloxquant-mlx.netlify.app/docs/algorithms/kivi"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let method = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(method.family == .quantization)
        #expect(method.docsURL == URL(string: "https://veloxquant-mlx.netlify.app/docs/algorithms/kivi"))
    }

    /// Issue #9 (`gear`): captured live from `veloxquant methods --json` after
    /// fixing VeloxQuant-MLX #355, which found that `config_fields` fell back
    /// to `bit_width_inlier`/`seed` only for any method missing from the
    /// Python registry's curated list — silently hiding every method-specific
    /// knob from this exact `field_schema`, which `parameterEditor` renders
    /// inputs from. `gear` has 6 real fields, including a `bool`
    /// (`gear_quantize_values`) and an optional field with a `null` default
    /// (`gear_rank`) — types no previously-curated method's schema exercised
    /// in this app's tests.
    @Test func decodesGearFieldSchemaWithBoolAndNullDefault() throws {
        let json = """
        {
          "name": "gear",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "GEAR: quantization plus a low-rank error-correction term.",
          "config_fields": ["bit_width_inlier", "seed", "gear_bits", "gear_energy_threshold", "gear_group_size", "gear_quantize_values", "gear_rank", "gear_sparse_fraction"],
          "field_schema": [
            {"name": "bit_width_inlier", "type": "int", "default": 2, "optional": false, "help": "Bits per element for the main quantizer."},
            {"name": "seed", "type": "int", "default": 42, "optional": false, "help": "Random seed for rotations / sketches."},
            {"name": "gear_bits", "type": "int", "default": 2, "optional": false, "help": null},
            {"name": "gear_energy_threshold", "type": "float", "default": 0.9, "optional": false, "help": null},
            {"name": "gear_group_size", "type": "int", "default": 32, "optional": false, "help": null},
            {"name": "gear_quantize_values", "type": "bool", "default": true, "optional": false, "help": null},
            {"name": "gear_rank", "type": "int", "default": null, "optional": true, "help": null},
            {"name": "gear_sparse_fraction", "type": "float", "default": 0.01, "optional": false, "help": null}
          ],
          "coverage": "keys_and_values",
          "coverage_label": "full estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": null,
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let gear = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(gear.fieldSchema.count == 8)

        let quantizeValues = try #require(gear.fieldSchema.first { $0.name == "gear_quantize_values" })
        #expect(quantizeValues.defaultValue == .bool(true))

        let rank = try #require(gear.fieldSchema.first { $0.name == "gear_rank" })
        #expect(rank.optional)
        #expect(rank.defaultValue == nil)
    }

    /// Issue #10 (`h2o`): also missing from `_CONFIG_FIELDS` before #355 —
    /// same bug as `gear` (#9), different method. Captured live from
    /// `veloxquant methods --json` with the fix applied. `h2o` is
    /// `not_trimmable` (eviction) *and* had its 5 real budget/decay fields
    /// hidden, so this method exercises both bugs found across #9 and #3.
    @Test func decodesH2OFieldSchemaAndNotTrimmableTier() throws {
        let json = """
        {
          "name": "h2o",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "H2O: keeps 'heavy hitter' tokens by accumulated attention.",
          "config_fields": ["bit_width_inlier", "seed", "h2o_budget", "h2o_decay", "h2o_grace", "h2o_n_sink", "h2o_rope_base"],
          "field_schema": [
            {"name": "bit_width_inlier", "type": "int", "default": 2, "optional": false, "help": "Bits per element for the main quantizer."},
            {"name": "seed", "type": "int", "default": 42, "optional": false, "help": "Random seed for rotations / sketches."},
            {"name": "h2o_budget", "type": "int", "default": 512, "optional": false, "help": null},
            {"name": "h2o_decay", "type": "float", "default": 0.98, "optional": false, "help": null},
            {"name": "h2o_grace", "type": "int", "default": 16, "optional": false, "help": null},
            {"name": "h2o_n_sink", "type": "int", "default": 4, "optional": false, "help": null},
            {"name": "h2o_rope_base", "type": "float", "default": 10000.0, "optional": false, "help": null}
          ],
          "coverage": "none",
          "coverage_label": "no estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": "serves correctly, but reports is_trimmable() == False, so mlx_lm.server cannot trim its prompt cache — trim() would roll back offset bookkeeping without reverting internal eviction state. Expected for eviction/compression caches (#152).",
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let h2o = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(h2o.fieldSchema.count == 7)
        #expect(h2o.fieldSchema.map(\.name).contains("h2o_budget"))
        #expect(h2o.serveTier == .notTrimmable)
        #expect(h2o.isServable)
    }

    /// Issue #11 (`keyformer`): also missing from `_CONFIG_FIELDS` before
    /// #355. Notable because it has *both* the generic `seed` field
    /// (network-owned, filtered from the parameter editor) *and* its own
    /// distinct `keyformer_seed` field — `networkOwnedFields` is an exact-
    /// match `Set<String>`, so `keyformer_seed` must survive filtering
    /// rather than being caught by a prefix/substring check against `seed`.
    /// Also exercises `keyformer_tau`: optional with a `null` default, same
    /// shape as `gear_rank` (#9).
    @Test func decodesKeyformerFieldSchemaWithDistinctSeedField() throws {
        let json = """
        {
          "name": "keyformer",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "Keyformer: Gumbel-softmax scoring for key-token selection.",
          "config_fields": ["bit_width_inlier", "seed", "keyformer_anneal_steps", "keyformer_budget", "keyformer_n_sink", "keyformer_recent", "keyformer_rope_base", "keyformer_seed", "keyformer_tau", "keyformer_tau_end", "keyformer_tau_init"],
          "field_schema": [
            {"name": "bit_width_inlier", "type": "int", "default": 2, "optional": false, "help": "Bits per element for the main quantizer."},
            {"name": "seed", "type": "int", "default": 42, "optional": false, "help": "Random seed for rotations / sketches."},
            {"name": "keyformer_anneal_steps", "type": "int", "default": 0, "optional": false, "help": null},
            {"name": "keyformer_budget", "type": "int", "default": 512, "optional": false, "help": null},
            {"name": "keyformer_n_sink", "type": "int", "default": 4, "optional": false, "help": null},
            {"name": "keyformer_recent", "type": "int", "default": 0, "optional": false, "help": null},
            {"name": "keyformer_rope_base", "type": "float", "default": 10000.0, "optional": false, "help": null},
            {"name": "keyformer_seed", "type": "int", "default": 0, "optional": false, "help": null},
            {"name": "keyformer_tau", "type": "float", "default": null, "optional": true, "help": null},
            {"name": "keyformer_tau_end", "type": "float", "default": 1.0, "optional": false, "help": null},
            {"name": "keyformer_tau_init", "type": "float", "default": 1.0, "optional": false, "help": null}
          ],
          "coverage": "none",
          "coverage_label": "no estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": "serves correctly, but reports is_trimmable() == False, so mlx_lm.server cannot trim its prompt cache — trim() would roll back offset bookkeeping without reverting internal eviction state. Expected for eviction/compression caches (#152).",
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let keyformer = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(keyformer.fieldSchema.count == 11)
        #expect(keyformer.fieldSchema.map(\.name).contains("keyformer_seed"))

        let tau = try #require(keyformer.fieldSchema.first { $0.name == "keyformer_tau" })
        #expect(tau.optional)
        #expect(tau.defaultValue == nil)
    }

    /// Guards against the failure mode fixed for issue #42: a method whose
    /// `family` the app doesn't recognize yet (e.g. a future cross-model
    /// `transfer` entry) must decode as `.unknown` rather than throwing and
    /// dropping the whole `methods --json` array, since `[QuantizationMethod]`
    /// decode is all-or-nothing.
    @Test func unrecognizedFamilyDecodesAsUnknownRatherThanFailing() throws {
        let json = """
        {
          "schema_version": 1,
          "default_serve_method": "turboquant_rvq",
          "accounting_only": true,
          "accounting_note": null,
          "methods": [
            {
              "name": "cross_model_transfer",
              "family": "transfer",
              "serve_tier": "not_trimmable",
              "serve_tier_label": "Not trimmable",
              "is_servable": false,
              "blurb": "Cross-model KV cache transfer.",
              "config_fields": [],
              "field_schema": [],
              "coverage": "none",
              "coverage_label": "Not reported",
              "paper_deviation": null,
              "is_adapted": true,
              "unsupported_reason": null,
              "docs_url": null
            },
            {
              "name": "turboquant_rvq",
              "family": "quantization",
              "serve_tier": "accounting_only",
              "serve_tier_label": "Serves (accounting-only)",
              "is_servable": true,
              "blurb": "Residual vector quantization.",
              "config_fields": [],
              "field_schema": [],
              "coverage": "keys_only",
              "coverage_label": "Keys only",
              "paper_deviation": null,
              "is_adapted": false,
              "unsupported_reason": null,
              "docs_url": null
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(MethodsResponse.self, from: data)

        #expect(response.methods.count == 2)
        let transfer = try #require(response.methods.first { $0.name == "cross_model_transfer" })
        #expect(transfer.family == .unknown)
    }

    /// Issue #1: `serve_tier_label` collapses `honest_bytes`, `accounting_only`,
    /// and `not_trimmable` into the same "available" string, so a method like
    /// `a2ats` (accounting-only) looked identical in the picker to a fully
    /// honest one. `serveTierCaption` surfaces the distinction the label hides.
    @Test func serveTierCaptionDistinguishesNonHonestTiers() throws {
        func method(serveTier: String) throws -> QuantizationMethod {
            let json = """
            {
              "name": "a2ats",
              "family": "hybrid",
              "serve_tier": "\(serveTier)",
              "serve_tier_label": "available",
              "is_servable": true,
              "blurb": "A2ATS-adapted: rotary-aware vector quantization with distance gating.",
              "config_fields": [],
              "field_schema": [],
              "coverage": "keys_and_values",
              "coverage_label": "full estimate",
              "paper_deviation": null,
              "is_adapted": true,
              "unsupported_reason": null,
              "docs_url": null
            }
            """
            let data = try #require(json.data(using: .utf8))
            return try JSONDecoder().decode(QuantizationMethod.self, from: data)
        }

        #expect(try method(serveTier: "accounting_only").serveTierCaption != nil)
        #expect(try method(serveTier: "not_trimmable").serveTierCaption != nil)
        #expect(try method(serveTier: "honest_bytes").serveTierCaption == nil)
        #expect(try method(serveTier: "crashes").serveTierCaption == nil)
    }

    /// Issue #3: `amc` is `is_servable == true` (a user can pick it and hit
    /// Start) *and* carries a non-nil `unsupported_reason` — Python's field
    /// is dual-purpose, reused for a servable-but-limited tier's
    /// explanation, not just for why Start is blocked. The view must not
    /// treat a servable method's `unsupported_reason` as a blocking error
    /// (red text, "Unsupported" section): `isServable` is the only signal
    /// that should govern that, `unsupported_reason` being non-nil is not.
    @Test func servableMethodCanCarryNonNilUnsupportedReason() throws {
        let json = """
        {
          "name": "amc",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "AMC: adaptive memory compression.",
          "config_fields": ["bit_width_inlier", "seed"],
          "field_schema": [],
          "coverage": "none",
          "coverage_label": "no estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": "serves correctly, but reports is_trimmable() == False, so mlx_lm.server cannot trim its prompt cache.",
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let amc = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(amc.isServable)
        #expect(amc.unsupportedReason != nil)
        #expect(amc.serveTier == .notTrimmable)
    }

    /// Issue #4: `anchorkv` (family `hybrid`) decodes to the exact same
    /// `not_trimmable` shape as `amc` (family `eviction`, issue #3) — same
    /// `unsupported_reason` template straight from `registry.py`'s
    /// `_run_probe`. Confirms the fix generalizes across families rather
    /// than happening to work for one method name.
    @Test func hybridFamilyMethodCanAlsoBeNotTrimmableAndServable() throws {
        let json = """
        {
          "name": "anchorkv",
          "family": "hybrid",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "AnchorKV-adapted: anchor-residual compression, no eviction.",
          "config_fields": ["bit_width_inlier", "seed"],
          "field_schema": [],
          "coverage": "none",
          "coverage_label": "no estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": "serves correctly, but reports is_trimmable() == False, so mlx_lm.server cannot trim its prompt cache — trim() would roll back offset bookkeeping without reverting internal eviction state. Expected for eviction/compression caches (#152).",
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let anchorkv = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(anchorkv.family == .hybrid)
        #expect(anchorkv.isServable)
        #expect(anchorkv.unsupportedReason != nil)
        #expect(anchorkv.serveTier == .notTrimmable)
        #expect(anchorkv.serveTierCaption != nil)
    }

    @Test func decodesServeReadyHandshake() throws {
        let json = """
        {
          "schema_version": 1,
          "model": "mlx-community/Llama-3.2-1B-Instruct-4bit",
          "method": "turboquant_rvq",
          "bits": 2,
          "host": "127.0.0.1",
          "port": 8000,
          "layer_caches": 16,
          "endpoints": {
            "openai_base_url": "http://127.0.0.1:8000/v1",
            "chat_completions": "http://127.0.0.1:8000/v1/chat/completions",
            "completions": "http://127.0.0.1:8000/v1/completions",
            "models": "http://127.0.0.1:8000/v1/models"
          },
          "accounting_only": true,
          "accounting_note": "compression is accounting-only."
        }
        """

        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(ServeReadyPayload.self, from: data)

        #expect(payload.model == "mlx-community/Llama-3.2-1B-Instruct-4bit")
        #expect(payload.layerCaches == 16)
        #expect(payload.endpoints.openaiBaseURL == "http://127.0.0.1:8000/v1")
        #expect(payload.endpoints.kvStats == nil)
    }

    /// Issue #5: confirmed against a real `veloxquant serve --method cachegen`
    /// run — `schema_version: 2` adds `kv_stats` to the handshake's
    /// `endpoints`, which decoding must pick up so `JobProgressView` can
    /// start polling it.
    @Test func decodesServeReadyHandshakeWithKVStatsEndpoint() throws {
        let json = """
        {
          "schema_version": 2,
          "model": "mlx-community/Llama-3.2-1B-Instruct-4bit",
          "method": "cachegen",
          "bits": 2,
          "host": "127.0.0.1",
          "port": 8971,
          "layer_caches": 16,
          "endpoints": {
            "openai_base_url": "http://127.0.0.1:8971/v1",
            "chat_completions": "http://127.0.0.1:8971/v1/chat/completions",
            "completions": "http://127.0.0.1:8971/v1/completions",
            "models": "http://127.0.0.1:8971/v1/models",
            "kv_stats": "http://127.0.0.1:8971/v1/kv/stats"
          },
          "accounting_only": true,
          "accounting_note": "compression is accounting-only."
        }
        """
        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(ServeReadyPayload.self, from: data)

        #expect(payload.endpoints.kvStats == "http://127.0.0.1:8971/v1/kv/stats")
    }
}
