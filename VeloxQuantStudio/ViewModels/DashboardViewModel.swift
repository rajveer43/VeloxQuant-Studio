import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let hardwareService: HardwareServiceProtocol
    private let pythonEnvironment: PythonEnvironmentService
    private let modelService: ModelServiceProtocol
    private let jobHistoryStore: JobHistoryStore

    private(set) var hardware: HardwareInfo = .placeholder
    private(set) var installedModelCount: Int = 0
    private(set) var isLoadingModels = false
    private(set) var errorMessage: String?

    var recentJobs: [QuantizationJob] {
        Array(jobHistoryStore.jobs.prefix(5))
    }

    var veloxquantVersion: String {
        if case .valid(_, let version) = pythonEnvironment.status { return version }
        return "Not detected"
    }

    var pythonStatus: PythonEnvironmentService.Status {
        pythonEnvironment.status
    }

    init(
        hardwareService: HardwareServiceProtocol,
        pythonEnvironment: PythonEnvironmentService,
        modelService: ModelServiceProtocol,
        jobHistoryStore: JobHistoryStore
    ) {
        self.hardwareService = hardwareService
        self.pythonEnvironment = pythonEnvironment
        self.modelService = modelService
        self.jobHistoryStore = jobHistoryStore
        self.hardware = hardwareService.currentHardware()
    }

    func onAppear() async {
        hardware = hardwareService.currentHardware()
        jobHistoryStore.refresh()
        if case .unknown = pythonEnvironment.status {
            await pythonEnvironment.restoreSavedInterpreter()
        }
        await loadModelCount()
    }

    func refresh() async {
        hardware = hardwareService.currentHardware()
        await pythonEnvironment.autoDetect()
        jobHistoryStore.refresh()
        await loadModelCount()
    }

    private func loadModelCount() async {
        guard pythonEnvironment.interpreterPath != nil else {
            installedModelCount = 0
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            installedModelCount = try await modelService.discoverCachedModels().count
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
