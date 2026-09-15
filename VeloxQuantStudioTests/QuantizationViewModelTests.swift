import Foundation
import Testing
@testable import VeloxQuantStudio

@MainActor
private final class FakeModelService: ModelServiceProtocol {
    var methodsResponse = MethodsResponse(
        schemaVersion: 1,
        defaultServeMethod: "turboquant_rvq",
        accountingOnly: true,
        accountingNote: nil,
        methods: []
    )
    var models: [LocalModel] = []

    func discoverCachedModels() async throws -> [LocalModel] { models }
    func importLocalModel(at url: URL) async throws -> LocalModel {
        LocalModel(repoID: url.lastPathComponent, sizeBytes: 0, sizeLabel: "0", isMLXCommunity: false)
    }
    func fetchAvailableMethods() async throws -> MethodsResponse { methodsResponse }
    func deleteModel(_ model: LocalModel) async throws {}
}

@MainActor
private final class FakeQuantizationService: QuantizationServiceProtocol {
    func startJob(request: QuantizationRequest) -> QuantizationJobHandle {
        QuantizationJobHandle(request: request, processController: StreamingProcessController())
    }
    func stopJob(_ handle: QuantizationJobHandle) {}
}

@MainActor
private final class FakeAutoConfigService: AutoConfigServiceProtocol {
    var result: Result<AutoConfigResponse, Error> = .failure(ServiceError.pythonNotConfigured)
    private(set) var lastRequest: AutoConfigRequest?

    func recommendConfig(request: AutoConfigRequest) async throws -> AutoConfigResponse {
        lastRequest = request
        return try result.get()
    }
}

private struct FakeHardwareService: HardwareServiceProtocol {
    var hardware = HardwareInfo(
        chipName: "Apple M3",
        chipFamily: .m3,
        performanceCoreCount: 4,
        efficiencyCoreCount: 4,
        gpuCoreCount: nil,
        unifiedMemoryBytes: 16 * 1024 * 1024 * 1024,
        macOSVersion: "macOS 15.0.0"
    )
    func currentHardware() -> HardwareInfo { hardware }
}

private final class FakeStorageService: StorageServiceProtocol, @unchecked Sendable {
    var modelStorageLocation: URL = FileManager.default.temporaryDirectory
    func setModelStorageLocation(_ url: URL) { modelStorageLocation = url }
    var telemetryEnabled: Bool = false
    func setTelemetryEnabled(_ enabled: Bool) { telemetryEnabled = enabled }
    var generationProfile: GenerationProfile = .default
    func setGenerationProfile(_ profile: GenerationProfile) { generationProfile = profile }
}

private func makeMethod(
    name: String,
    family: MethodFamily = .quantization,
    serveTier: QuantizationMethod.ServeTier = .accountingOnly,
    fieldSchema: [ConfigField] = []
) -> QuantizationMethod {
    QuantizationMethod(
        name: name,
        family: family,
        serveTier: serveTier,
        serveTierLabel: serveTier == .crashes ? "Crashes" : "Serves (accounting-only)",
        isServable: serveTier.isServable,
        blurb: "\(name) blurb",
        configFields: fieldSchema.map(\.name),
        fieldSchema: fieldSchema,
        coverage: "none",
        coverageLabel: "Not reported",
        paperDeviation: nil,
        isAdapted: false,
        // Mirrors registry.py's _run_probe: NOT_TRIMMABLE is servable but
        // still carries a reason (Python reuses this field for a
        // servable-but-limited tier's explanation, not only for why a
        // crashes-tier method is blocked — see issue #3).
        unsupportedReason: {
            switch serveTier {
            case .crashes: "\(name) does not subclass mlx_lm KVCache"
            case .notTrimmable: "\(name) reports is_trimmable() == False"
            case .honestBytes, .accountingOnly: nil
            }
        }(),
        docsURLString: nil
    )
}

@MainActor
struct QuantizationViewModelTests {
    private func makeViewModel(
        methods: [QuantizationMethod],
        models: [LocalModel] = [LocalModel(repoID: "m", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: false)],
        autoConfigService: FakeAutoConfigService = FakeAutoConfigService()
    ) async -> QuantizationViewModel {
        let modelService = FakeModelService()
        modelService.methodsResponse = MethodsResponse(
            schemaVersion: 1,
            defaultServeMethod: "turboquant_rvq",
            accountingOnly: true,
            accountingNote: nil,
            methods: methods
        )
        modelService.models = models
        let viewModel = QuantizationViewModel(
            quantizationService: FakeQuantizationService(),
            modelService: modelService,
            storageService: FakeStorageService(),
            autoConfigService: autoConfigService,
            hardwareService: FakeHardwareService()
        )
        await viewModel.loadContext()
        return viewModel
    }

    @Test func applyPresetSetsMethodBitsAndOverridesAtomically() async {
        let rvq = makeMethod(
            name: "turboquant_rvq",
            fieldSchema: [ConfigField(name: "bit_width_inlier", type: "int", optional: false, defaultValue: .int(2), help: nil)]
        )
        let viewModel = await makeViewModel(methods: [rvq])

        let preset = MethodPreset(
            name: "Balanced (RVQ-1bit)",
            methodName: "turboquant_rvq",
            bitWidth: 1,
            parameterOverrides: ["bit_width_inlier": "1"],
            blurb: "test"
        )
        viewModel.applyPreset(preset)

        #expect(viewModel.selectedMethod?.name == "turboquant_rvq")
        #expect(viewModel.bitWidth == 1)
        #expect(viewModel.parameterOverrides["bit_width_inlier"] == "1")
    }

    @Test func availablePresetsHidesPresetsForMissingMethods() async {
        let viewModel = await makeViewModel(methods: [makeMethod(name: "turboquant_rvq")])
        // Only turboquant_rvq is in the registry response; kivi/vecinfer presets
        // should not be offered since those methods aren't in this build.
        #expect(viewModel.availablePresets.map(\.methodName) == ["turboquant_rvq"])
    }

    @Test func selectingMethodClearsPreviousMethodOverrides() async {
        let methodA = makeMethod(name: "a", fieldSchema: [ConfigField(name: "seed", type: "int", optional: false, defaultValue: .int(1), help: nil)])
        let methodB = makeMethod(name: "b", fieldSchema: [ConfigField(name: "budget", type: "int", optional: false, defaultValue: .int(64), help: nil)])
        let viewModel = await makeViewModel(methods: [methodA, methodB])

        viewModel.selectMethod(methodA)
        #expect(viewModel.parameterOverrides["seed"] == "1")

        viewModel.selectMethod(methodB)
        #expect(viewModel.parameterOverrides["seed"] == nil)
        #expect(viewModel.parameterOverrides["budget"] == "64")
    }

    /// Issue #9 (`gear`): before VeloxQuant-MLX #355, `gear`'s field_schema
    /// only ever contained `bit_width_inlier`/`seed` (both network-owned, so
    /// the parameter editor showed nothing) even though the method has 6 real
    /// knobs. Confirms that once the real fields decode, they all survive
    /// `selectMethod`'s prefill: defaulted fields get their default as a
    /// string, and the one optional field with a `null` default
    /// (`gear_rank`) is correctly left unset rather than prefilled "null".
    @Test func selectingGearPrefillsAllSixRealFieldsExceptNullDefault() async {
        let gear = makeMethod(name: "gear", fieldSchema: [
            ConfigField(name: "bit_width_inlier", type: "int", optional: false, defaultValue: .int(2), help: nil),
            ConfigField(name: "seed", type: "int", optional: false, defaultValue: .int(42), help: nil),
            ConfigField(name: "gear_bits", type: "int", optional: false, defaultValue: .int(2), help: nil),
            ConfigField(name: "gear_energy_threshold", type: "float", optional: false, defaultValue: .double(0.9), help: nil),
            ConfigField(name: "gear_group_size", type: "int", optional: false, defaultValue: .int(32), help: nil),
            ConfigField(name: "gear_quantize_values", type: "bool", optional: false, defaultValue: .bool(true), help: nil),
            ConfigField(name: "gear_rank", type: "int", optional: true, defaultValue: nil, help: nil),
            ConfigField(name: "gear_sparse_fraction", type: "float", optional: false, defaultValue: .double(0.01), help: nil),
        ])
        let viewModel = await makeViewModel(methods: [gear])

        viewModel.selectMethod(gear)

        #expect(viewModel.parameterOverrides["gear_bits"] == "2")
        #expect(viewModel.parameterOverrides["gear_energy_threshold"] == "0.9")
        #expect(viewModel.parameterOverrides["gear_group_size"] == "32")
        #expect(viewModel.parameterOverrides["gear_quantize_values"] == "true")
        #expect(viewModel.parameterOverrides["gear_sparse_fraction"] == "0.01")
        #expect(viewModel.parameterOverrides["gear_rank"] == nil)
    }

    /// Issue #44: recommendConfig() populates recommendedConfig on success,
    /// and applyRecommendedConfig() then applies method/bits/knobs atomically
    /// to the manual form, mirroring applyPreset's atomic-apply guarantee.
    @Test func recommendConfigPopulatesRecommendationOnSuccess() async {
        let auto = FakeAutoConfigService()
        auto.result = .success(
            AutoConfigResponse(
                config: AutoConfigResponse.RecommendedConfig(
                    method: "turboquant_rvq",
                    headDim: 128,
                    knobs: ["bit_width_inlier": .int(4)]
                ),
                reason: "short context"
            )
        )
        let viewModel = await makeViewModel(methods: [makeMethod(name: "turboquant_rvq")], autoConfigService: auto)

        await viewModel.recommendConfig()

        #expect(viewModel.recommendedConfig?.config.method == "turboquant_rvq")
        #expect(viewModel.recommendationError == nil)
        #expect(viewModel.isLoadingRecommendation == false)
    }

    @Test func recommendConfigSurfacesPythonNotConfiguredError() async {
        let auto = FakeAutoConfigService()
        auto.result = .failure(ServiceError.pythonNotConfigured)
        let viewModel = await makeViewModel(methods: [makeMethod(name: "turboquant_rvq")], autoConfigService: auto)

        await viewModel.recommendConfig()

        #expect(viewModel.recommendedConfig == nil)
        #expect(viewModel.recommendationError != nil)
    }

    @Test func applyRecommendedConfigSetsMethodAndBitsAtomically() async {
        let auto = FakeAutoConfigService()
        auto.result = .success(
            AutoConfigResponse(
                config: AutoConfigResponse.RecommendedConfig(
                    method: "kivi_method",
                    headDim: 128,
                    knobs: ["bit_width_inlier": .int(2), "kivi_group_size": .int(64)]
                ),
                reason: "mid-length context"
            )
        )
        let kivi = makeMethod(name: "kivi_method")
        let viewModel = await makeViewModel(methods: [kivi], autoConfigService: auto)

        await viewModel.recommendConfig()
        viewModel.applyRecommendedConfig()

        #expect(viewModel.selectedMethod?.name == "kivi_method")
        #expect(viewModel.bitWidth == 2)
        #expect(viewModel.parameterOverrides["kivi_group_size"] == "64")
    }

    @Test func applyRecommendedConfigDoesNothingWithoutARecommendation() async {
        let viewModel = await makeViewModel(methods: [makeMethod(name: "turboquant_rvq")])
        let originalMethod = viewModel.selectedMethod

        viewModel.applyRecommendedConfig()

        #expect(viewModel.selectedMethod?.name == originalMethod?.name)
    }

    /// Issue #42: a method in an unrecognized family (e.g. a future
    /// cross-model transfer entry, which works structurally differently
    /// from every single-model cache method) must never surface in the
    /// picker, even though the underlying registry fetch succeeds.
    @Test func unknownFamilyMethodsAreExcludedFromAvailableMethods() async {
        let quant = makeMethod(name: "turboquant_rvq", family: .quantization)
        let transfer = makeMethod(name: "cross_model_transfer", family: .unknown, serveTier: .notTrimmable)
        let viewModel = await makeViewModel(methods: [quant, transfer])

        #expect(viewModel.availableMethods.map(\.name) == ["turboquant_rvq"])
        #expect(viewModel.servableMethods.map(\.name) == ["turboquant_rvq"])
        #expect(viewModel.unsupportedMethods.isEmpty)
    }

    @Test func familyFilterNarrowsServableAndUnsupportedLists() async {
        let quant = makeMethod(name: "quant_method", family: .quantization)
        let evict = makeMethod(name: "evict_method", family: .eviction)
        let viewModel = await makeViewModel(methods: [quant, evict])

        #expect(viewModel.filteredMethods.count == 2)

        viewModel.familyFilter = .eviction
        #expect(viewModel.filteredMethods.map(\.name) == ["evict_method"])
        #expect(viewModel.servableMethods.map(\.name) == ["evict_method"])
    }

    /// Issue #3 (`amc`, eviction), #4 (`anchorkv`, hybrid), #6 (`cam`,
    /// eviction), #7 (`chunkkv`, eviction), #8 (`curdkv`, eviction), #10
    /// (`h2o`, eviction), #11 (`keyformer`, eviction), #18 (`kvzip`,
    /// eviction), #20 (`morphkv`, eviction), #21 (`nestedkv`,
    /// quantization), #24 (`pyramidkv`, eviction), #25 (`qfilters`,
    /// eviction), and #27 (`snapkv`, eviction): all decode to
    /// `not_trimmable` with the exact same generic `unsupported_reason`
    /// template from `registry.py`, so the fix must be generic across
    /// families and methods, not keyed to one name. `not_trimmable` is
    /// still `is_servable == true` — the method belongs in the "Servable"
    /// section of the picker, and Start must stay enabled, even though it
    /// carries a non-nil `unsupportedReason` (Python reuses that field for
    /// the tier's explanatory text, not only for why a `crashes`-tier
    /// method is blocked). This is exactly the guarantee issues #24, #25,
    /// and #27 asked to confirm: the picker and detail banner must make the
    /// method's limitation clear *before* Start Job, not only as a server
    /// crash after. `snapkv` is a notable case: its `is_trimmable() ==
    /// False` was newly added by the same fix that guards its `merge()` —
    /// previously `trim()` silently corrupted the cache (see the decoding
    /// test below) rather than merely rolling back bookkeeping, making the
    /// picker/banner warning even more load-bearing than for the generic
    /// case.
    @Test(arguments: [
        ("amc", MethodFamily.eviction),
        ("anchorkv", MethodFamily.hybrid),
        ("cam", MethodFamily.eviction),
        ("chunkkv", MethodFamily.eviction),
        ("curdkv", MethodFamily.eviction),
        ("h2o", MethodFamily.eviction),
        ("keyformer", MethodFamily.eviction),
        ("kvzip", MethodFamily.eviction),
        ("morphkv", MethodFamily.eviction),
        ("nestedkv", MethodFamily.quantization),
        ("pyramidkv", MethodFamily.eviction),
        ("qfilters", MethodFamily.eviction),
        ("snapkv", MethodFamily.eviction),
    ])
    func notTrimmableMethodIsServableAndDoesNotBlockStart(name: String, family: MethodFamily) async {
        let method = makeMethod(name: name, family: family, serveTier: .notTrimmable)
        let viewModel = await makeViewModel(methods: [method])
        viewModel.selectMethod(method)

        #expect(viewModel.servableMethods.map(\.name) == [name])
        #expect(viewModel.unsupportedMethods.isEmpty)
        #expect(viewModel.startBlockedReason == nil)
        #expect(viewModel.canStart)
    }

    @Test func startBlockedReasonNamesTierForCrashingMethod() async {
        let crashing = makeMethod(name: "turboquant_prod", serveTier: .crashes)
        let viewModel = await makeViewModel(methods: [crashing])
        viewModel.selectMethod(crashing)

        #expect(!viewModel.canStart)
        #expect(viewModel.startBlockedReason == "turboquant_prod does not subclass mlx_lm KVCache")
    }

    @Test func startBlockedReasonIsNilForServableMethod() async {
        let servable = makeMethod(name: "turboquant_rvq", serveTier: .accountingOnly)
        let viewModel = await makeViewModel(methods: [servable])
        viewModel.selectMethod(servable)

        #expect(viewModel.startBlockedReason == nil)
    }

    /// Issue #37 (`polar`, quantization): `PolarQuantKVCache` doesn't subclass
    /// `mlx_lm` KVCache at all (it's a standalone `core.abstractions.KVCache`
    /// with its own append_key/append_value/attend interface, not an adapter
    /// gap) — `veloxquant serve --method polar` refuses upfront with this
    /// exact text (verified live) rather than crashing mid-request. The app
    /// must surface that *before* Start Job is pressed, not just let the CLI's
    /// refusal be the user's first signal. Covered generically above via
    /// `turboquant_prod`; this pins the same guarantees to polar's own name
    /// and real `unsupported_reason` text so a regression here is caught even
    /// if the generic crashes-tier test is ever narrowed.
    @Test func polarIsUnsupportedAndBlocksStartBeforeSubmission() async {
        let polar = makeMethod(name: "polar", family: .quantization, serveTier: .crashes)
        let viewModel = await makeViewModel(methods: [polar], models: [
            LocalModel(repoID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: true),
        ])
        viewModel.selectMethod(polar)

        #expect(viewModel.servableMethods.isEmpty)
        #expect(viewModel.unsupportedMethods.map(\.name) == ["polar"])
        #expect(!viewModel.canStart)
        #expect(viewModel.startBlockedReason == "polar does not subclass mlx_lm KVCache")

        // Defense in depth: even if a caller reaches startJob() directly
        // (bypassing the disabled button), the method-level isServable guard
        // inside startJob() itself must still refuse to launch a job.
        viewModel.startJob()
        #expect(viewModel.activeJob == nil)
    }

    /// Issue #38 (`qjl`, quantization): same architecture as polar (#37) —
    /// `QJLKVCache` is a standalone `core.abstractions.KVCache` (JL-sketch
    /// signs + int8 values via append_key/append_value/attend), not an
    /// `mlx_lm` KVCache subclass, so it's explicitly listed in
    /// `STANDALONE_METHODS` rather than being a small adapter gap.
    /// `veloxquant serve --method qjl` refuses upfront with this exact text
    /// (verified live). Pins the same crashes-tier gating guarantees to
    /// qjl's own name and real `unsupported_reason` text.
    @Test func qjlIsUnsupportedAndBlocksStartBeforeSubmission() async {
        let qjl = makeMethod(name: "qjl", family: .quantization, serveTier: .crashes)
        let viewModel = await makeViewModel(methods: [qjl], models: [
            LocalModel(repoID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: true),
        ])
        viewModel.selectMethod(qjl)

        #expect(viewModel.servableMethods.isEmpty)
        #expect(viewModel.unsupportedMethods.map(\.name) == ["qjl"])
        #expect(!viewModel.canStart)
        #expect(viewModel.startBlockedReason == "qjl does not subclass mlx_lm KVCache")

        // Defense in depth: even if a caller reaches startJob() directly
        // (bypassing the disabled button), the method-level isServable guard
        // inside startJob() itself must still refuse to launch a job.
        viewModel.startJob()
        #expect(viewModel.activeJob == nil)
    }

    /// Issue #2: VeloxQuant-MLX #31 fixed `adakv`'s degenerate default
    /// (`target_avg_bits == lo_bit`, which flattens every head to the same
    /// bit-width) by moving the default off the boundary — but a user can
    /// still retype that exact degeneracy into the free-text parameter
    /// editor, and Python only warns to logs, not the app. `parameterWarning`
    /// catches it client-side before Start is pressed.
    private func adakvFields() -> [ConfigField] {
        [
            ConfigField(name: "adakv_target_avg_bits", type: "float", optional: false, defaultValue: .double(2.5), help: nil),
            ConfigField(name: "adakv_lo_bit", type: "int", optional: false, defaultValue: .int(2), help: nil),
            ConfigField(name: "adakv_hi_bit", type: "int", optional: false, defaultValue: .int(4), help: nil),
        ]
    }

    @Test func parameterWarningFlagsDegenerateAdaKVTarget() async {
        let adakv = makeMethod(name: "adakv", fieldSchema: adakvFields())
        let viewModel = await makeViewModel(methods: [adakv])
        viewModel.selectMethod(adakv)

        viewModel.parameterOverrides["adakv_target_avg_bits"] = "2"

        #expect(viewModel.parameterWarning != nil)
    }

    @Test func parameterWarningIsNilForAdaptiveAdaKVTarget() async {
        let adakv = makeMethod(name: "adakv", fieldSchema: adakvFields())
        let viewModel = await makeViewModel(methods: [adakv])
        viewModel.selectMethod(adakv)

        #expect(viewModel.parameterWarning == nil)
    }

    @Test func parameterWarningIsNilForOtherMethods() async {
        let rvq = makeMethod(
            name: "turboquant_rvq",
            fieldSchema: [ConfigField(name: "bit_width_inlier", type: "int", optional: false, defaultValue: .int(2), help: nil)]
        )
        let viewModel = await makeViewModel(methods: [rvq])
        viewModel.selectMethod(rvq)

        #expect(viewModel.parameterWarning == nil)
    }

    @Test func serveArgumentsNeverDuplicateServerOwnedKeys() {
        let model = LocalModel(repoID: "mlx-community/Qwen3-8B-4bit", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: true)
        let method = makeMethod(
            name: "turboquant_rvq",
            fieldSchema: [ConfigField(name: "bit_width_inlier", type: "int", optional: false, defaultValue: .int(2), help: nil)]
        )
        let request = QuantizationRequest(
            model: model,
            method: method,
            bitWidth: 1,
            parameterOverrides: ["bit_width_inlier": "2", "seed": "42"],
            port: 8000
        )

        let arguments = QuantizationService.serveArguments(for: request)

        #expect(arguments.filter { $0 == "--bits" }.count == 1)
        #expect(!arguments.contains("bit_width_inlier=2"))
        #expect(!arguments.contains("seed=42"))
    }

    @Test func generationProfilePersistsThroughStorageService() async {
        let storage = FakeStorageService()
        let modelService = FakeModelService()
        let viewModel = QuantizationViewModel(
            quantizationService: FakeQuantizationService(),
            modelService: modelService,
            storageService: storage,
            autoConfigService: FakeAutoConfigService(),
            hardwareService: FakeHardwareService()
        )

        viewModel.generationProfile.temperature = 1.1
        #expect(storage.generationProfile.temperature == 1.1)
    }
}
