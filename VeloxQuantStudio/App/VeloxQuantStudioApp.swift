import SwiftUI

@main
struct VeloxQuantStudioApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(appState: appState)
        }
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 640, height: 480)
        }
    }
}
