import Foundation
import Observation

/// Top-level app state, injected via the SwiftUI environment.
///
/// Owns the service layer and the handful of view models that need to
/// outlive any single screen (auth session, active job). Screen-local state
/// lives in each view's own `@State`/view model instead of here.
@MainActor
@Observable
final class AppState {
    let authService: AuthenticationServiceProtocol
    let hardwareService: HardwareServiceProtocol
    let pythonEnvironment: PythonEnvironmentService
    let modelService: ModelServiceProtocol
    let quantizationService: QuantizationServiceProtocol
    let benchmarkService: BenchmarkServiceProtocol
    let profilingService: ProfilingServiceProtocol
    let autoConfigService: AutoConfigServiceProtocol
    let storageService: StorageServiceProtocol
    let jobHistoryStore: JobHistoryStore

    let authViewModel: AuthViewModel
    let dashboardViewModel: DashboardViewModel
    let modelLibraryViewModel: ModelLibraryViewModel
    let quantizationViewModel: QuantizationViewModel
    let historyViewModel: HistoryViewModel

    var selectedSection: AppSection = .dashboard
    var isSidebarExpanded: Bool = true

    init() {
        let storage = StorageService()
        let python = PythonEnvironmentService()
        let hardware = HardwareService()
        let auth = AuthenticationService()
        let models = ModelService(pythonEnvironment: python, storageService: storage)
        let history = JobHistoryStore()
        let quant = QuantizationService(pythonEnvironment: python, jobHistoryStore: history)
        let bench = BenchmarkService(pythonEnvironment: python, jobHistoryStore: history)
        let profiling = ProfilingService(pythonEnvironment: python, jobHistoryStore: history)
        let autoConfig = AutoConfigService(pythonEnvironment: python)

        self.storageService = storage
        self.pythonEnvironment = python
        self.hardwareService = hardware
        self.authService = auth
        self.modelService = models
        self.jobHistoryStore = history
        self.quantizationService = quant
        self.benchmarkService = bench
        self.profilingService = profiling
        self.autoConfigService = autoConfig

        self.authViewModel = AuthViewModel(authService: auth)
        self.dashboardViewModel = DashboardViewModel(
            hardwareService: hardware,
            pythonEnvironment: python,
            modelService: models,
            jobHistoryStore: history
        )
        self.modelLibraryViewModel = ModelLibraryViewModel(modelService: models)
        self.quantizationViewModel = QuantizationViewModel(
            quantizationService: quant,
            modelService: models,
            storageService: storage,
            autoConfigService: autoConfig,
            hardwareService: hardware
        )
        self.historyViewModel = HistoryViewModel(jobHistoryStore: history, profilingService: profiling)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case models
    case quantization
    case benchmarks
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .models: "Models"
        case .quantization: "Quantization"
        case .benchmarks: "Benchmarks"
        case .history: "Job History"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .models: "shippingbox"
        case .quantization: "slider.horizontal.3"
        case .benchmarks: "chart.bar.xaxis"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}
