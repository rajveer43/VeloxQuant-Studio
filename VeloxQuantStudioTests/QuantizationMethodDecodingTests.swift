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

    /// Issue #12 (`kitty`): `kitty` is already curated in `_CONFIG_FIELDS`
    /// (unaffected by #355/#9), but its `config_fields` never includes
    /// `bit_width_inlier` — `KittyKVCache` only ever reads `kitty_hi_bit`/
    /// `kitty_lo_bit`. `serve.py`'s `build_config()` sets `bit_width_inlier`
    /// from `--bits` unconditionally regardless of method, so the Network
    /// section's "Bit width" stepper is a silent no-op for `kitty` (and 9
    /// other curated methods: `adakv`, `vecinfer`, `svdq`, `xquant`,
    /// `kvquant`, `palu`, `qjl`, `rocketkv`, `age_tiered`).
    /// `usesNetworkBitWidth` is what the Network section and job header key
    /// off to warn the user / avoid showing a misleading "N-bit" label.
    @Test func kittyDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "kitty",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "Kitty: dynamic channel-wise mixed precision by variance.",
          "config_fields": ["kitty_hi_fraction", "kitty_hi_bit", "kitty_lo_bit", "kitty_group_size"],
          "field_schema": [],
          "coverage": "keys_only",
          "coverage_label": "partial estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": null,
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let kitty = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(!kitty.usesNetworkBitWidth)
    }

    @Test func methodDeclaringBitWidthInlierUsesNetworkBitWidth() throws {
        let json = """
        {
          "name": "turboquant_rvq",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "Residual vector quantization.",
          "config_fields": ["bit_width_inlier", "seed"],
          "field_schema": [],
          "coverage": "keys_only",
          "coverage_label": "partial estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": null,
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let rvq = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(rvq.usesNetworkBitWidth)
    }

    /// Issue #14 (`kivi_sink`): a curated method's `_CONFIG_FIELDS` entry can
    /// itself be incomplete, a different failure mode from #9's uncurated-
    /// method bug. Before VeloxQuant-MLX #356, `kivi_sink`'s only visible
    /// fields (`bit_width_inlier`, `kivi_group_size`) were identical to
    /// plain `kivi` — its own sink-count knob (`n_sink_tokens`, the thing
    /// the blurb is actually about) was completely hidden. Captured live
    /// with #356's fix applied.
    @Test func decodesKiviSinkFieldSchemaIncludingNSinkTokens() throws {
        let json = """
        {
          "name": "kivi_sink",
          "family": "hybrid",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "KIVI with attention-sink protection for the first tokens.",
          "config_fields": ["bit_width_inlier", "kivi_group_size", "n_sink_tokens"],
          "field_schema": [
            {"name": "bit_width_inlier", "type": "int", "default": 2, "optional": false, "help": "Bits per element for the main quantizer."},
            {"name": "kivi_group_size", "type": "int", "default": 32, "optional": false, "help": "Tokens per min/max quantization group."},
            {"name": "n_sink_tokens", "type": "int", "default": 5, "optional": false, "help": "Number of early attention-sink tokens kept in fp16, never quantized."}
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
        let kiviSink = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(kiviSink.fieldSchema.count == 3)
        let sinkField = try #require(kiviSink.fieldSchema.first { $0.name == "n_sink_tokens" })
        #expect(sinkField.defaultValue == .int(5))
        #expect(sinkField.help != nil)
    }

    /// Issue #15 (`knorm`): a distinct failure mode from `kitty`'s. `kitty`
    /// is *curated* and its `_CONFIG_FIELDS` list simply omits
    /// `bit_width_inlier` — `configFields.contains` alone catches that.
    /// `knorm` is *uncurated*: registry.py's `_default_config_fields()`
    /// (issue #9) unconditionally prepends `_GENERIC_FIELDS` before the
    /// method's real `knorm_*` fields, so `bit_width_inlier` IS present in
    /// `config_fields` even though `L2NormKVCache` stores fp16 K/V directly
    /// and never reads it — `configFields.contains` alone would wrongly
    /// report `true` here. Captured against the real registry payload.
    @Test func knormDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "knorm",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "K-norm: evicts by key-norm as an attention proxy.",
          "config_fields": ["bit_width_inlier", "seed", "knorm_budget", "knorm_keep", "knorm_n_sink", "knorm_recent"],
          "field_schema": [],
          "coverage": "keys_and_values",
          "coverage_label": "full estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": null,
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let knorm = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(knorm.configFields.contains("bit_width_inlier"))
        #expect(!knorm.usesNetworkBitWidth)
    }

    /// Issue #18 (`kvzip`, eviction): same `not_trimmable` shape as `knorm`
    /// (#15) — `kvzip` is uncurated, so `_default_config_fields()` still
    /// prepends `bit_width_inlier` to `config_fields` even though
    /// `KVzipKVCache` never reads it (its three real knobs are
    /// `kvzip_budget`, `kvzip_n_sink`, `kvzip_probe`, all sharing the
    /// `kvzip_` prefix). Captured verbatim from a real
    /// `veloxquant methods --json` run, including the exact
    /// `unsupported_reason` text (trim-safety rationale, issue #152) the
    /// method detail banner must surface before Start Job. A real backend
    /// batching bug was found and fixed for this method (issue #18,
    /// upstream `KVzipKVCache.merge` hasattr guard) — that fix has no
    /// config/UI-visible surface and needs no Swift change, since `kvzip`
    /// was already correctly listed in `methodsIgnoringNetworkBitWidth`.
    @Test func kvzipDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "kvzip",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "KVzip: query-agnostic eviction via context reconstruction.",
          "config_fields": ["bit_width_inlier", "seed", "kvzip_budget", "kvzip_n_sink", "kvzip_probe"],
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
        let kvzip = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(kvzip.configFields.contains("bit_width_inlier"))
        #expect(!kvzip.usesNetworkBitWidth)
        #expect(kvzip.isServable)
        #expect(kvzip.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Issue #19 (`minicache`, hybrid): uncurated like `knorm`/`kvzip`, so
    /// `bit_width_inlier` is present in `config_fields` from the generic
    /// baseline prepend even though `MiniCacheKVCache` never reads it — its
    /// five real knobs (`minicache_group_size`, `minicache_max_ctx`,
    /// `minicache_retention_threshold`, `minicache_slerp_t`,
    /// `minicache_start_frac`) all share the `minicache_` prefix instead.
    /// Unlike `knorm`/`kvzip`, `minicache` is `accounting_only` (fully
    /// servable, no `unsupported_reason`) rather than `not_trimmable` — pins
    /// `field_schema` verbatim too, since issue #19 specifically calls out
    /// verifying the parameter editor renders every real field. Captured
    /// from a real `veloxquant methods --json` run. A real backend batching
    /// bug was found and fixed for this method (issue #19, upstream
    /// `MiniCacheKVCache.merge` hasattr guard, same bug class as
    /// `knorm`/`kvquant`/`kvtc`/`kvzip`) — that fix has no config/UI-visible
    /// surface and needs no Swift change, since `minicache` was already
    /// correctly listed in `methodsIgnoringNetworkBitWidth`.
    @Test func minicacheDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "minicache",
          "family": "hybrid",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "MiniCache: merges similar KV state across adjacent layers.",
          "config_fields": ["bit_width_inlier", "seed", "minicache_group_size", "minicache_max_ctx", "minicache_retention_threshold", "minicache_slerp_t", "minicache_start_frac"],
          "field_schema": [
            {"name": "bit_width_inlier", "type": "int", "optional": false, "default": 2, "help": "Bits per element for the main quantizer."},
            {"name": "seed", "type": "int", "optional": false, "default": 42, "help": "Random seed for rotations / sketches."},
            {"name": "minicache_group_size", "type": "int", "optional": false, "default": 2, "help": null},
            {"name": "minicache_max_ctx", "type": "int", "optional": false, "default": 8192, "help": null},
            {"name": "minicache_retention_threshold", "type": "float", "optional": false, "default": 0.9, "help": null},
            {"name": "minicache_slerp_t", "type": "float", "optional": false, "default": 0.5, "help": null},
            {"name": "minicache_start_frac", "type": "float", "optional": false, "default": 0.5, "help": null}
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
        let minicache = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(minicache.configFields.contains("bit_width_inlier"))
        #expect(!minicache.usesNetworkBitWidth)
        #expect(minicache.isServable)
        #expect(minicache.unsupportedReason == nil)
        #expect(minicache.fieldSchema.map(\.name) == [
            "bit_width_inlier", "seed", "minicache_group_size", "minicache_max_ctx",
            "minicache_retention_threshold", "minicache_slerp_t", "minicache_start_frac",
        ])
    }

    /// Issue #20 (`morphkv`, eviction): same `not_trimmable` shape as
    /// `knorm` (#15) and `kvzip` (#18) — `morphkv` is uncurated, so
    /// `_default_config_fields()` still prepends `bit_width_inlier` to
    /// `config_fields` even though `MorphKVKVCache` never reads it (its
    /// three real knobs are `morphkv_budget`, `morphkv_n_sink`,
    /// `morphkv_window`, all sharing the `morphkv_` prefix). Captured
    /// verbatim from a real `veloxquant methods --json` run, including the
    /// exact `unsupported_reason` text (trim-safety rationale, issue #152)
    /// the method detail banner must surface before Start Job — the
    /// specific ask in issue #20. A real backend batching bug was found and
    /// fixed for this method (issue #20, upstream `MorphKVKVCache.merge`
    /// hasattr guard, same bug class as knorm/kvquant/kvtc/kvzip/minicache)
    /// — that fix has no config/UI-visible surface and needs no Swift
    /// change, since `morphkv` was already correctly listed in
    /// `methodsIgnoringNetworkBitWidth`.
    @Test func morphkvDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "morphkv",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "MorphKV: correlation-aware constant-size cache.",
          "config_fields": ["bit_width_inlier", "seed", "morphkv_budget", "morphkv_n_sink", "morphkv_window"],
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
        let morphkv = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(morphkv.configFields.contains("bit_width_inlier"))
        #expect(!morphkv.usesNetworkBitWidth)
        #expect(morphkv.isServable)
        #expect(morphkv.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Issue #21 (`nestedkv`, quantization): same `not_trimmable` shape as
    /// `knorm` (#15), `kvzip` (#18), and `morphkv` (#20) — `nestedkv` is
    /// uncurated, so `_default_config_fields()` still prepends
    /// `bit_width_inlier` to `config_fields` even though `NestedKVKVCache`
    /// never reads it (its real knobs — `nestedkv_beta`, `nestedkv_budget`,
    /// `nestedkv_kappa`, `nestedkv_n_sink`, `nestedkv_safeguard_alpha`,
    /// `nestedkv_tau`, `nestedkv_window` — all share the `nestedkv_`
    /// prefix). Captured verbatim from a real `veloxquant methods --json`
    /// run, including the exact `unsupported_reason` text (trim-safety
    /// rationale, issue #152) the method detail banner must surface before
    /// Start Job — the specific ask in issue #21. A real, more substantial
    /// backend bug was found and fixed for this method (issue #21, upstream
    /// `NestedKVKVCache`): zero-padded ragged per-head lengths were
    /// corrupting attention output, fixed by dropping the cross-head budget
    /// reallocation in favor of a uniform per-head budget (same convention
    /// as H2O/CurDKV/PyramidKV); the same `merge()` hasattr-guard batching
    /// bug as knorm/kvquant/kvtc/kvzip/minicache/morphkv was fixed
    /// alongside it. Neither half changes `config_fields`/`field_schema`
    /// (`nestedkv_safeguard_alpha` is still parsed and stored, just no
    /// longer consumed internally) or needs a Swift change, since
    /// `nestedkv` was already correctly listed in
    /// `methodsIgnoringNetworkBitWidth`.
    @Test func nestedkvDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "nestedkv",
          "family": "quantization",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "NestedKV: hierarchical nested codebooks.",
          "config_fields": ["bit_width_inlier", "seed", "nestedkv_beta", "nestedkv_budget", "nestedkv_kappa", "nestedkv_n_sink", "nestedkv_safeguard_alpha", "nestedkv_tau", "nestedkv_window"],
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
        let nestedkv = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(nestedkv.configFields.contains("bit_width_inlier"))
        #expect(!nestedkv.usesNetworkBitWidth)
        #expect(nestedkv.isServable)
        #expect(nestedkv.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Issue #23 (`palu`, quantization): `palu` is *curated* in registry.py's
    /// `_CONFIG_FIELDS` (like `kitty` #12 and `kivi_sink` #14), so
    /// `config_fields` never includes `bit_width_inlier`/`seed` — no
    /// `methodsIgnoringNetworkBitWidth` entry is needed, and `configFields`
    /// alone (via `usesNetworkBitWidth`) is the source of truth.
    ///
    /// A real backend bug was found and fixed while verifying this issue
    /// (upstream VeloxQuant-MLX#366, referencing this Studio issue by
    /// number): `palu`'s `_CONFIG_FIELDS` entry had held only
    /// `["palu_rank", "palu_energy_threshold"]` since the method's original
    /// introduction, even though `PALUKVCache.__init__` consumes six more
    /// real knobs (`palu_n_head_groups`, `palu_hi_bit`, `palu_lo_bit`,
    /// `palu_hi_fraction`, `palu_group_size`, `palu_quantize_values`) — all
    /// completely invisible to the macOS app's parameter editor and to
    /// `veloxquant serve --set` validation, since a curated method gets no
    /// prefix-fallback exposure the way an uncurated one would. The fix
    /// expanded `_CONFIG_FIELDS["palu"]` to all eight real fields; this test
    /// pins the corrected payload so a future regression (a knob silently
    /// dropping back out of `config_fields`/`field_schema`) fails here too,
    /// not just in the Python registry test.
    ///
    /// The same upstream commit also fixed the #358 `merge()` hasattr-guard
    /// batching-substitution bug for `palu` (the 8th confirmed occurrence) —
    /// unrelated to `config_fields`/`field_schema` and requiring no Swift
    /// change, since the UI never special-cases `palu` by name.
    @Test func paluExposesAllEightConfigFields() throws {
        let json = """
        {
          "name": "palu",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "PALU: true low-rank latent projection of both keys and values.",
          "config_fields": ["palu_rank", "palu_energy_threshold", "palu_n_head_groups", "palu_hi_bit", "palu_lo_bit", "palu_hi_fraction", "palu_group_size", "palu_quantize_values"],
          "field_schema": [
            {"name": "palu_rank", "type": "int", "default": null, "optional": true, "help": "Latent rank; blank uses the energy threshold instead."},
            {"name": "palu_energy_threshold", "type": "float", "default": 0.9, "optional": false, "help": "Fraction of singular-value energy to retain."},
            {"name": "palu_n_head_groups", "type": "int", "default": 4, "optional": false, "help": "Number of head groups sharing a low-rank projection."},
            {"name": "palu_hi_bit", "type": "int", "default": 4, "optional": false, "help": "Mixed-bit: bits for the top latent channels."},
            {"name": "palu_lo_bit", "type": "int", "default": 2, "optional": false, "help": "Mixed-bit: bits for the remaining latent channels."},
            {"name": "palu_hi_fraction", "type": "float", "default": 0.25, "optional": false, "help": "Fraction of latent channels kept at the higher bit-width."},
            {"name": "palu_group_size", "type": "int", "default": 32, "optional": false, "help": "Tokens per latent quantization group."},
            {"name": "palu_quantize_values", "type": "bool", "default": true, "optional": false, "help": "Also mixed-bit quantize values (off keeps value latents at fp16)."}
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
        let palu = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(palu.fieldSchema.count == 8)
        #expect(palu.fieldSchema.map(\.name) == [
            "palu_rank", "palu_energy_threshold", "palu_n_head_groups", "palu_hi_bit",
            "palu_lo_bit", "palu_hi_fraction", "palu_group_size", "palu_quantize_values",
        ])
        #expect(!palu.usesNetworkBitWidth)
        #expect(palu.isServable)
        #expect(palu.unsupportedReason == nil)

        let rank = try #require(palu.fieldSchema.first { $0.name == "palu_rank" })
        #expect(rank.optional)
        #expect(rank.defaultValue == nil)

        let quantizeValues = try #require(palu.fieldSchema.first { $0.name == "palu_quantize_values" })
        #expect(quantizeValues.defaultValue == .bool(true))
    }

    /// Issue #24 (`pyramidkv`, eviction): `not_trimmable` shape, same
    /// generic `unsupported_reason` template covered by the parameterized
    /// ViewModel test — pinned here too for the decoding side.
    ///
    /// A real backend bug was found and fixed while verifying this issue
    /// (upstream VeloxQuant-MLX#367): `pyramidkv` was previously
    /// *uncurated*, so `field_is_relevant`'s `"pyramid_"` name-prefix
    /// fallback exposed `pyramid_resolved_budget` alongside the three real
    /// user-facing knobs (plus `pyramid_budget`) — an internal, per-layer
    /// field written only by `KVCacheBuilder._build_pyramidkv` (via
    /// `dataclasses.replace`) to hand each layer its own slice of the
    /// pyramid schedule, never meant to be user-settable. Left exposed,
    /// `--set pyramid_resolved_budget=N` or this app's parameter editor
    /// could have silently pinned every layer to one fixed budget,
    /// bypassing the pyramid schedule with no visible indication. The fix
    /// added a curated `_CONFIG_FIELDS["pyramidkv"]` entry listing only the
    /// four real fields (`pyramid_backend`, `pyramid_beta`,
    /// `pyramid_budget`, `pyramid_n_sink`) — this test pins that corrected,
    /// leak-free payload. Being newly curated, `config_fields` no longer
    /// contains `bit_width_inlier`/`seed` either; `pyramidkv`'s existing
    /// `methodsIgnoringNetworkBitWidth` entry is therefore redundant but
    /// harmless (`usesNetworkBitWidth` already short-circuits on
    /// `configFields.contains` alone).
    ///
    /// The same commit fixed the #358 `merge()` hasattr-guard batching bug
    /// for `pyramidkv` too (9th confirmed occurrence) — unrelated to
    /// `config_fields`/`field_schema`. Issue #24 also asked to confirm the
    /// picker/detail banner surface the not-trimmable limitation before
    /// Start Job; that's exactly what
    /// `notTrimmableMethodIsServableAndDoesNotBlockStart` verifies. No
    /// Swift change needed for either fix.
    @Test func pyramidkvExcludesInternalResolvedBudgetField() throws {
        let json = """
        {
          "name": "pyramidkv",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "PyramidKV: layer-varying budgets, wider at shallow layers.",
          "config_fields": ["pyramid_backend", "pyramid_beta", "pyramid_budget", "pyramid_n_sink"],
          "field_schema": [
            {"name": "pyramid_backend", "type": "str", "default": "reference", "optional": false, "help": null},
            {"name": "pyramid_beta", "type": "float", "default": 2.0, "optional": false, "help": null},
            {"name": "pyramid_budget", "type": "int", "default": 512, "optional": false, "help": null},
            {"name": "pyramid_n_sink", "type": "int", "default": 4, "optional": false, "help": null}
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
        let pyramidkv = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(pyramidkv.fieldSchema.count == 4)
        #expect(pyramidkv.configFields == ["pyramid_backend", "pyramid_beta", "pyramid_budget", "pyramid_n_sink"])
        #expect(!pyramidkv.configFields.contains("pyramid_resolved_budget"))
        #expect(!pyramidkv.usesNetworkBitWidth)
        #expect(pyramidkv.isServable)
        #expect(pyramidkv.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Issue #25 (`qfilters`, eviction): same `not_trimmable` shape as
    /// `knorm` (#15), `kvzip` (#18), `morphkv` (#20), and `nestedkv` (#21)
    /// — `qfilters` is uncurated, so `_default_config_fields()` still
    /// prepends `bit_width_inlier`/`seed` even though `QFiltersKVCache`
    /// never reads them (its real knobs — `qfilters_budget`,
    /// `qfilters_calib_tokens`, `qfilters_n_sink`, `qfilters_recent`,
    /// `qfilters_sign` — all share the `qfilters_` prefix). Captured
    /// verbatim from a real `veloxquant methods --json` run.
    ///
    /// Verifying this issue found the 10th confirmed occurrence of the
    /// #358 `merge()` hasattr-guard batching-substitution bug (upstream
    /// VeloxQuant-MLX#368) — unlike `palu` (#23) and `pyramidkv` (#24),
    /// `field_schema` here was checked and found NOT to need curation: all
    /// five `qfilters_*` fields are real, consumed, user-facing knobs with
    /// no internal/build-time-only field hiding behind the prefix fallback
    /// (`use_metal_kernels` is a genuine non-prefixed field the cache
    /// reads, but omitting it from `field_schema` matches established
    /// precedent for already-curated sibling methods like `kivi`/
    /// `vecinfer`). Neither the batching fix nor that check changes
    /// `config_fields`/`field_schema` or needs a Swift change, since
    /// `qfilters` was already correctly listed in
    /// `methodsIgnoringNetworkBitWidth`.
    @Test func qfiltersDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "qfilters",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "Q-Filters: projects keys onto learned filters to score them.",
          "config_fields": ["bit_width_inlier", "seed", "qfilters_budget", "qfilters_calib_tokens", "qfilters_n_sink", "qfilters_recent", "qfilters_sign"],
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
        let qfilters = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(qfilters.configFields.contains("bit_width_inlier"))
        #expect(!qfilters.usesNetworkBitWidth)
        #expect(qfilters.isServable)
        #expect(qfilters.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Issue #26 (`skvq`, hybrid): `accounting_only` tier, same shape as
    /// `minicache` (#19) and `palu` (#23) for tier gating — already covered
    /// generically by `startBlockedReasonIsNilForServableMethod`. `skvq` is
    /// uncurated, so `_default_config_fields()` still prepends
    /// `bit_width_inlier`/`seed` even though `SKVQKVCache` never reads them
    /// (its real knobs — `skvq_bits_key`, `skvq_bits_value`,
    /// `skvq_clip_alpha`, `skvq_clip_search`, `skvq_group_size`,
    /// `skvq_max_ctx`, `skvq_n_sink`, `skvq_reorder`, `skvq_window` — all
    /// share the `skvq_` prefix). Already correctly listed in
    /// `methodsIgnoringNetworkBitWidth`.
    ///
    /// Unlike the last several `not_trimmable` methods, this issue's
    /// backend bug (the #358 `merge()` hasattr-guard batching-substitution
    /// bug, 11th confirmed occurrence) had not yet been fixed upstream when
    /// this issue was picked up — fixed in this same verification pass
    /// (`VeloxQuant-MLX#383`), live-verified against a real `veloxquant
    /// serve --method skvq` process (server log: "method 'skvq' has no
    /// merge(); serving unbatched", followed by a successful chat
    /// completion). `field_schema` was checked and found not to need
    /// curation (all 9 `skvq_*` fields are real, consumed, user-facing
    /// knobs). Neither the fix nor that check changes
    /// `config_fields`/`field_schema` or needs a Swift change.
    @Test func skvqDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "skvq",
          "family": "hybrid",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "SKVQ: sliding-window quantization with clipped dynamic range.",
          "config_fields": ["bit_width_inlier", "seed", "skvq_bits_key", "skvq_bits_value", "skvq_clip_alpha", "skvq_clip_search", "skvq_group_size", "skvq_max_ctx", "skvq_n_sink", "skvq_reorder", "skvq_window"],
          "field_schema": [],
          "coverage": "keys_and_values",
          "coverage_label": "full estimate",
          "paper_deviation": null,
          "is_adapted": false,
          "unsupported_reason": null,
          "docs_url": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let skvq = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(skvq.configFields.contains("bit_width_inlier"))
        #expect(!skvq.usesNetworkBitWidth)
        #expect(skvq.isServable)
        #expect(skvq.unsupportedReason == nil)
    }

    /// Issue #27 (`snapkv`, eviction): same `not_trimmable` shape as
    /// `knorm`/`kvzip`/`morphkv`/`nestedkv`/`pyramidkv`/`qfilters` —
    /// uncurated, so `config_fields` carries `bit_width_inlier`/`seed` via
    /// `_default_config_fields()` even though `SnapKVKVCache` never reads
    /// them; already correctly listed in `methodsIgnoringNetworkBitWidth`.
    ///
    /// Unlike the prior `not_trimmable` methods in this queue, `snapkv`'s
    /// `is_trimmable() == False` was *newly added* by the fix for this
    /// issue (upstream VeloxQuant-MLX#371) — before the fix, `snapkv`
    /// inherited the base class's `is_trimmable() == True`, but its
    /// `trim(n)` was actively wrong, not just unsupported: outside
    /// `update_and_fetch` this class's `offset` property returns
    /// `_true_offset` (the absolute RoPE position) rather than
    /// `_row_offset` (the retained row count the buffer actually holds), so
    /// `trim()` clamped against the wrong, larger number and could leave
    /// `_row_offset` bigger than the number of rows ever written —
    /// `update_and_fetch` would then return a slice reaching into
    /// stale/uninitialized buffer rows as real cached tokens, corrupting
    /// generation silently rather than crashing. Reproduced upstream with
    /// budget=4, 20 real tokens: `trim(3)` left `_row_offset=17` though
    /// only 4 rows were real. Fixed by hardcoding `is_trimmable() ->
    /// False`, matching every other eviction/compression cache — this is
    /// why the picker/detail-banner guarantee below matters more here than
    /// for the generic `not_trimmable` case: pre-fix, the picker had no way
    /// to warn about this at all, since the method claimed to be trimmable.
    ///
    /// The same commit fixed the standard #358 `merge()` hasattr-guard
    /// batching bug (12th confirmed occurrence). Fixing `merge()` also
    /// exposed a third, separate, architectural bug — prefill eviction
    /// mismatching query/key lengths under MLX's `mask="causal"` fast path
    /// (upstream issue #370, also affecting `squeeze` #28 and
    /// `streaming_llm` #29) — filed separately as out of scope for this fix
    /// since it's a generation-quality bug, not a `config_fields`/UI
    /// surface. `field_schema` needed no changes for any of the three bugs;
    /// no Swift change needed either.
    @Test func snapkvDoesNotUseNetworkBitWidth() throws {
        let json = """
        {
          "name": "snapkv",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "SnapKV: keeps tokens an observation window attends to most.",
          "config_fields": ["bit_width_inlier", "seed", "snap_backend", "snap_batched_scoring", "snap_budget", "snap_dtype", "snap_n_sink", "snap_obs_window"],
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
        let snapkv = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(snapkv.configFields.contains("bit_width_inlier"))
        #expect(!snapkv.usesNetworkBitWidth)
        #expect(snapkv.isServable)
        #expect(snapkv.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Issue #28 (`squeeze`, eviction): same `not_trimmable` shape and same
    /// `field_schema`-leak bug class as `pyramidkv` (#24), but resolved
    /// differently at runtime — `KVCacheBuilder._build_squeeze` never
    /// writes `squeeze_resolved_budget` via `dataclasses.replace`; instead
    /// every layer shares a `SqueezeCoordinator` object and pulls its
    /// resolved per-layer budget from it once every layer has reported
    /// prefill concentration. `squeeze_resolved_budget` only exists as a
    /// manual override for single-cache/testing construction with no
    /// coordinator, but shared the `squeeze_` prefix with the three real
    /// knobs, so `squeeze` being uncurated let it leak into
    /// `config_fields`/`field_schema` the same way `pyramid_resolved_budget`
    /// did — flagged as still-open in the `pyramidkv` fix, now fixed
    /// upstream in `VeloxQuant-MLX#372` by curating `_CONFIG_FIELDS["squeeze"]`
    /// down to the three real fields.
    ///
    /// Unlike `snapkv` (#27), `squeeze`'s `is_trimmable()` was already
    /// correctly `False` before this fix — only `merge()` (13th confirmed
    /// #358 occurrence) and the field leak needed fixing. Live-verifying
    /// the `merge()` fix also reproduced the same eviction/causal-mask
    /// architectural bug already filed as backend issue #370 (found
    /// verifying `snapkv` #27) — confirmed systemic across the whole
    /// eviction family (none of `h2o`, `tova`, `pyramidkv`, `chunkkv`,
    /// `cam`, `snapkv`, `squeeze` override `make_mask`), deliberately left
    /// unfixed here as it needs shared mask-building changes, not a
    /// per-cache patch.
    ///
    /// `squeeze` was already correctly listed in
    /// `methodsIgnoringNetworkBitWidth`; being curated, `config_fields`
    /// never included `bit_width_inlier`/`seed` in the first place, so that
    /// entry is redundant but harmless (same situation as `pyramidkv`). No
    /// Swift change needed for any of the fixes.
    @Test func squeezeExcludesInternalResolvedBudgetField() throws {
        let json = """
        {
          "name": "squeeze",
          "family": "eviction",
          "serve_tier": "not_trimmable",
          "serve_tier_label": "available (no prompt-cache trimming)",
          "is_servable": true,
          "blurb": "SqueezeAttention: reallocates budget across layers by importance.",
          "config_fields": ["squeeze_budget", "squeeze_n_sink", "squeeze_strength"],
          "field_schema": [
            {"name": "squeeze_budget", "type": "int", "default": 512, "optional": false, "help": null},
            {"name": "squeeze_n_sink", "type": "int", "default": 4, "optional": false, "help": null},
            {"name": "squeeze_strength", "type": "float", "default": 1.0, "optional": false, "help": null}
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
        let squeeze = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(squeeze.fieldSchema.count == 3)
        #expect(squeeze.configFields == ["squeeze_budget", "squeeze_n_sink", "squeeze_strength"])
        #expect(!squeeze.configFields.contains("squeeze_resolved_budget"))
        #expect(!squeeze.usesNetworkBitWidth)
        #expect(squeeze.isServable)
        #expect(squeeze.unsupportedReason?.contains("is_trimmable() == False") == true)
    }

    /// Regression for issue #16: `kvquant` is *curated* in registry.py's
    /// `_CONFIG_FIELDS`, but that explicit list was missing `kvquant_n_sink`
    /// (`KVQuantKVCache`'s Attention Sink-Aware knob, read directly in its
    /// `__init__`) until this fix — the parameter editor never rendered a
    /// control for it. Captures the corrected payload so a future regression
    /// (the field silently dropping out of `config_fields`/`field_schema`
    /// again) fails this test rather than only being caught by the Python
    /// registry test.
    @Test func kvquantExposesNSinkField() throws {
        let json = """
        {
          "name": "kvquant",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "KVQuant-NUQ: non-uniform levels via Lloyd-Max with fp16 outliers.",
          "config_fields": ["kvquant_bits", "kvquant_outlier_fraction", "kvquant_group_size", "kvquant_lloyd_iters", "kvquant_refit_interval", "kvquant_n_sink"],
          "field_schema": [
            {"name": "kvquant_bits", "type": "int", "default": 3, "optional": false, "help": null},
            {"name": "kvquant_outlier_fraction", "type": "float", "default": 0.01, "optional": false, "help": "Top-magnitude fraction kept in fp16."},
            {"name": "kvquant_group_size", "type": "int", "default": 32, "optional": false, "help": null},
            {"name": "kvquant_lloyd_iters", "type": "int", "default": 8, "optional": false, "help": null},
            {"name": "kvquant_refit_interval", "type": "int", "default": 0, "optional": false, "help": null},
            {"name": "kvquant_n_sink", "type": "int", "default": 1, "optional": false, "help": null}
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
        let kvquant = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        #expect(kvquant.configFields.contains("kvquant_n_sink"))
        #expect(kvquant.fieldSchema.contains { $0.name == "kvquant_n_sink" })
    }

    /// Regression for issue #17: `kvtc_bit_choices` is a Python `tuple`
    /// (`(0, 1, 2, 3, 4, 6, 8)`), which `json.dumps` serializes as a plain
    /// JSON array default. Before `JSONValue` gained an `.array` case, the
    /// decoder only tried bool/int/double/string and silently fell back to
    /// `.null` for anything else — losing the real default (it would render
    /// as a blank default in the parameter editor) without failing the
    /// decode. Captures the real `veloxquant methods --json` payload for
    /// `kvtc` so a future regression is caught here, not just by the Python
    /// registry test for `describe_field`.
    @Test func kvtcBitChoicesDecodesArrayDefaultRatherThanNull() throws {
        let json = """
        {
          "name": "kvtc",
          "family": "quantization",
          "serve_tier": "accounting_only",
          "serve_tier_label": "available",
          "is_servable": true,
          "blurb": "KVTC: transform coding of the cache.",
          "config_fields": ["bit_width_inlier", "seed", "kvtc_beta", "kvtc_bit_budget", "kvtc_bit_choices"],
          "field_schema": [
            {"name": "bit_width_inlier", "type": "int", "default": 2, "optional": false, "help": "Bits per element for the main quantizer."},
            {"name": "seed", "type": "int", "default": 42, "optional": false, "help": "Random seed for rotations / sketches."},
            {"name": "kvtc_beta", "type": "float", "default": 3.5, "optional": false, "help": null},
            {"name": "kvtc_bit_budget", "type": "int", "default": 512, "optional": false, "help": null},
            {"name": "kvtc_bit_choices", "type": "array", "default": [0, 1, 2, 3, 4, 6, 8], "optional": false, "help": null}
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
        let kvtc = try JSONDecoder().decode(QuantizationMethod.self, from: data)

        let field = try #require(kvtc.fieldSchema.first { $0.name == "kvtc_bit_choices" })
        guard case .array(let values) = field.defaultValue else {
            Issue.record("expected .array default, got \(String(describing: field.defaultValue))")
            return
        }
        #expect(values.map(\.displayString) == ["0", "1", "2", "3", "4", "6", "8"])
        #expect(field.defaultValue?.displayString == "[0, 1, 2, 3, 4, 6, 8]")
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
