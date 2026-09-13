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
    }
}
