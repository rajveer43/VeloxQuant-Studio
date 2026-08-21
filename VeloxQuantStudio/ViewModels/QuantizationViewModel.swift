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

    private(set) var activeJob: QuantizationJobHandle?

    var servableMethods: [QuantizationMethod] {
        availableMethods.filter(\.isServable)
    }

    var unsupportedMethods: [QuantizationMethod] {
        availableMethods.filter { !$0.isServable }
    }

    var canStart: Bool {
        selectedModel != nil && selectedMethod?.isServable == true && activeJob == nil
    }

    init(quantizationService: QuantizationServiceProtocol, modelService: ModelServiceProtocol) {
        self.quantizationService = quantizationService
        self.modelService = modelService
    }

    func loadContext() async {
        isLoadingMethods = true
        loadError = nil
        defer { isLoadingMethods = false }

        async let modelsTask = try? modelService.discoverCachedModels()
        do {
            let response = try await modelService.fetchAvailableMethods()
            availableMethods = response.methods.sorted { $0.name < $1.name }
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
