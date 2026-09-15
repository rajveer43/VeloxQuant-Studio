import Foundation
import Observation

@MainActor
@Observable
final class QuantizationViewModel {
    private let quantizationService: QuantizationServiceProtocol
    private let modelService: ModelServiceProtocol
    private let autoConfigService: AutoConfigServiceProtocol
    private let hardwareService: HardwareServiceProtocol

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

    /// User-adjustable inputs for the "Recommended for this Mac" card. Only
    /// `seqLen` is exposed in the UI today (the axis `select_kv_cache_config`
    /// actually branches on for the servable pool); `headDim`/`nLayers`
    /// default to `WorkloadSpec`'s own Python defaults since Studio has no
    /// per-model architecture introspection yet (`LocalModel` carries no
    /// head_dim/n_layers — see issue #44's open question on this).
    var autoConfigSeqLen: Int = 4_096
    private(set) var recommendedConfig: AutoConfigResponse?
    private(set) var isLoadingRecommendation = false
    private(set) var recommendationError: String?

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

    /// Warns when the current parameter overrides would reproduce a known
    /// degenerate configuration, so a user typing free-text values doesn't
    /// silently recreate a bug already fixed at the default. `adakv` needs
    /// `lo_bit < target_avg_bits < hi_bit` — at or outside that range every
    /// head gets the same bit-width regardless of importance (the exact
    /// defect VeloxQuant-MLX #31 fixed by moving the default off the
    /// boundary). Python only logs this as a runtime warning; nothing
    /// surfaces it in the app before Start is pressed.
    var parameterWarning: String? {
        guard let selectedMethod, selectedMethod.name == "adakv" else { return nil }
        guard let target = Double(parameterOverrides["adakv_target_avg_bits"] ?? ""),
              let lo = Double(parameterOverrides["adakv_lo_bit"] ?? ""),
              let hi = Double(parameterOverrides["adakv_hi_bit"] ?? "")
        else { return nil }
        guard lo < hi, !(lo < target && target < hi) else { return nil }
        return "adakv_target_avg_bits (\(parameterOverrides["adakv_target_avg_bits"] ?? "")) must be strictly between adakv_lo_bit and adakv_hi_bit, or every head gets the same bit-width regardless of importance — no per-head adaptation."
    }

    init(
        quantizationService: QuantizationServiceProtocol,
        modelService: ModelServiceProtocol,
        storageService: StorageServiceProtocol,
        autoConfigService: AutoConfigServiceProtocol,
        hardwareService: HardwareServiceProtocol
    ) {
        self.quantizationService = quantizationService
        self.modelService = modelService
        self.storageService = storageService
        self.autoConfigService = autoConfigService
        self.hardwareService = hardwareService
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
                parameterOverrides[field.name] = defaultValue.cliOverrideString
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

    /// Fetches a "Recommended for this Mac" pick from `select_kv_cache_config()`
    /// for the current `autoConfigSeqLen`, using this Mac's real memory from
    /// `HardwareService` (sysctl) rather than letting the subprocess
    /// re-detect it. Additive to manual selection: the result only becomes
    /// the active method/bits/overrides if the user taps "Use this config"
    /// (`applyRecommendedConfig()`).
    func recommendConfig() async {
        isLoadingRecommendation = true
        recommendationError = nil
        defer { isLoadingRecommendation = false }

        do {
            recommendedConfig = try await autoConfigService.recommendConfig(
                request: AutoConfigRequest(seqLen: autoConfigSeqLen, hardware: hardwareService.currentHardware())
            )
        } catch ServiceError.pythonNotConfigured {
            recommendationError = "No Python interpreter configured. Set one in Settings → Compute."
        } catch {
            recommendationError = "Could not compute a recommendation. This may require a newer VeloxQuant-MLX with the auto-config CLI."
        }
    }

    /// Pre-fills the manual form from the current recommendation — mirrors
    /// `applyPreset`'s atomic apply (method + bits + overrides land together)
    /// so the auto path never leaves the form in a half-updated state.
    func applyRecommendedConfig() {
        guard let recommended = recommendedConfig,
              let method = availableMethods.first(where: { $0.name == recommended.config.method }) else { return }
        selectMethod(method)
        if let bits = recommended.config.knobs["bit_width_inlier"], case .int(let value) = bits {
            bitWidth = value
        } else if let bits = recommended.config.knobs["gear_bits"], case .int(let value) = bits {
            bitWidth = value
        } else if let bits = recommended.config.knobs["kvquant_bits"], case .int(let value) = bits {
            bitWidth = value
        }
        for (key, value) in recommended.config.knobs {
            parameterOverrides[key] = value.cliOverrideString
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
        activeJob.stopPollingKVStats()
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
