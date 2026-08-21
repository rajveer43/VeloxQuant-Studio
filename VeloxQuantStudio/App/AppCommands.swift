import SwiftUI

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Quantization Job") {
                appState.selectedSection = .quantization
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Navigate") {
            ForEach(AppSection.allCases) { section in
                Button(section.title) {
                    appState.selectedSection = section
                }
                .keyboardShortcut(shortcutKey(for: section), modifiers: .command)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh Hardware Info") {
                Task { await appState.dashboardViewModel.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private func shortcutKey(for section: AppSection) -> KeyEquivalent {
        switch section {
        case .dashboard: "1"
        case .models: "2"
        case .quantization: "3"
        case .benchmarks: "4"
        case .history: "5"
        case .settings: ","
        }
    }
}
