import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Group {
            if appState.authViewModel.session == nil {
                AuthContainerView()
                    .environment(appState.authViewModel)
            } else {
                NavigationSplitView {
                    SidebarView(selection: $appState.selectedSection)
                } detail: {
                    detailView
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            }
        }
        .task {
            await appState.authViewModel.restoreSession()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .dashboard:
            DashboardView()
                .environment(appState.dashboardViewModel)
        case .models:
            ModelLibraryView()
                .environment(appState.modelLibraryViewModel)
        case .quantization:
            QuantizationWorkspaceView()
                .environment(appState.quantizationViewModel)
        case .benchmarks:
            BenchmarkView()
                .environment(appState.historyViewModel)
        case .history:
            JobHistoryView()
                .environment(appState.historyViewModel)
        case .settings:
            SettingsView()
        }
    }
}
