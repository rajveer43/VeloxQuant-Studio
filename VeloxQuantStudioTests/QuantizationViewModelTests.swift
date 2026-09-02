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
        unsupportedReason: serveTier.isServable ? nil : "\(name) does not subclass mlx_lm KVCache",
        docsURLString: nil
    )
}

@MainActor
struct QuantizationViewModelTests {
    private func makeViewModel(methods: [QuantizationMethod], models: [LocalModel] = [LocalModel(repoID: "m", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: false)]) async -> QuantizationViewModel {
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
            storageService: FakeStorageService()
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
            storageService: storage
        )

        viewModel.generationProfile.temperature = 1.1
        #expect(storage.generationProfile.temperature == 1.1)
    }
}
