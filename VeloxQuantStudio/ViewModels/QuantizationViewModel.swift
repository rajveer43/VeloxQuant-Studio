import Foundation
import Observation

@MainActor
@Observable
final class QuantizationViewModel {
    private let quantizationService: QuantizationServiceProtocol
    private let modelService: ModelServiceProtocol

    private(set) var availableModels: [LocalModel] = []
    private(set) var availableMethods: [QuantizationMethod] = []
    private(set) var defaultServeMethod: String = "turboquant_rvq"
    private(set) var accountingNote: String?
    private(set) var isLoadingMethods = false
    private(set) var loadError: String?

    var selectedModel: LocalModel?
    var selectedMethod: QuantizationMethod?
    var bitWidth: Int = 2
    var parameterOverrides: [String: String] = [:]
    var port: Int = 8000
    var familyFilter: MethodFamily?

    private(set) var activeJob: QuantizationJobHandle?

    private let storageService: StorageServiceProtocol
    var generationProfile: GenerationProfile {
        didSet { storageService.setGenerationProfile(generationProfile) }
    }

    var filteredMethods: [QuantizationMethod] {
        guard let familyFilter else { return availableMethods }
        return availableMethods.filter { $0.family == familyFilter }
    }

    var servableMethods: [QuantizationMethod] {
        filteredMethods.filter(\.isServable)
    }

    var unsupportedMethods: [QuantizationMethod] {
        filteredMethods.filter { !$0.isServable }
    }

    /// Presets validated against the currently probed registry — a preset
    /// naming a method this build doesn't expose (removed, renamed, or not
    /// compiled in) is hidden rather than shown broken.
    var availablePresets: [MethodPreset] {
        MethodPreset.all.filter { preset in
            availableMethods.contains { $0.name == preset.methodName }
        }
    }

    /// Names the reason Start is disabled when a non-servable method is
    /// selected, so the tier that blocked it is visible at the point of
    /// failure, not just buried in the method detail card above.
    var startBlockedReason: String? {
        guard let selectedMethod else { return nil }
        guard !selectedMethod.isServable else { return nil }
        return selectedMethod.unsupportedReason
            ?? "\(selectedMethod.name) is \(selectedMethod.serveTierLabel.lowercased()) and cannot be started."
    }

    var canStart: Bool {
        selectedModel != nil && selectedMethod?.isServable == true && activeJob == nil
    }

    init(
        quantizationService: QuantizationServiceProtocol,
        modelService: ModelServiceProtocol,
        storageService: StorageServiceProtocol
    ) {
        self.quantizationService = quantizationService
        self.modelService = modelService
        self.storageService = storageService
        self.generationProfile = storageService.generationProfile
    }

    func loadContext() async {
        isLoadingMethods = true
        loadError = nil
        defer { isLoadingMethods = false }

        async let modelsTask = try? modelService.discoverCachedModels()
        do {
            let response = try await modelService.fetchAvailableMethods()
            // Methods in an unrecognized family (e.g. a future cross-model
            // transfer entry, see issue #42) work structurally differently
            // from a single-model cache method and don't belong in this
            // picker — excluded here so no derived list can surface one.
            availableMethods = response.methods
                .filter { $0.family != .unknown }
                .sorted { $0.name < $1.name }
            defaultServeMethod = response.defaultServeMethod
            accountingNote = response.accountingNote
            if selectedMethod == nil {
                selectedMethod = availableMethods.first { $0.name == response.defaultServeMethod }
            }
        } catch ServiceError.pythonNotConfigured {
            loadError = "No Python interpreter configured. Set one in Settings → Compute before starting a job."
        } catch {
            loadError = error.localizedDescription
        }

        availableModels = (await modelsTask) ?? []
        if selectedModel == nil {
            selectedModel = availableModels.first
        }
    }

    func selectMethod(_ method: QuantizationMethod) {
        selectedMethod = method
        parameterOverrides = [:]
        for field in method.fieldSchema {
            if let defaultValue = field.defaultValue {
                parameterOverrides[field.name] = defaultValue.displayString
            }
        }
    }

    /// Applies a named preset atomically: method, bit width, and its
    /// overrides land together, rather than a caller having to call
    /// `selectMethod` then patch overrides in separately (which would
    /// briefly show the method's raw defaults before the preset's values).
    func applyPreset(_ preset: MethodPreset) {
        guard let method = availableMethods.first(where: { $0.name == preset.methodName }) else { return }
        selectMethod(method)
        bitWidth = preset.bitWidth
        for (key, value) in preset.parameterOverrides {
            parameterOverrides[key] = value
        }
    }

    func startJob() {
        guard let model = selectedModel, let method = selectedMethod, method.isServable else { return }
        let request = QuantizationRequest(
            model: model,
            method: method,
            bitWidth: bitWidth,
            parameterOverrides: parameterOverrides,
            port: port
        )
        activeJob = quantizationService.startJob(request: request)
    }

    func stopJob() {
        guard let activeJob else { return }
        quantizationService.stopJob(activeJob)
        self.activeJob = nil
    }

    func clearFinishedJob() {
        guard let activeJob else { return }
        switch activeJob.processController.state {
        case .finished, .failed:
            self.activeJob = nil
        default:
            break
        }
    }
}
