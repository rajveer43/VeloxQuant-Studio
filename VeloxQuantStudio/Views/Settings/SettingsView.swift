import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettingsTab()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            ComputeSettingsTab()
                .tabItem { Label("Compute", systemImage: "cpu") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
        .scenePadding()
    }
}

private struct AccountSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            if let session = appState.authViewModel.session {
                LabeledContent("Email", value: session.email)
                LabeledContent("Plan", value: session.planIdentifier ?? "Free")
                Button("Sign Out", role: .destructive) {
                    Task { await appState.authViewModel.signOut() }
                }
            } else {
                Text("Not signed in.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ComputeSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingPicker = false
    @State private var isShowingStoragePicker = false

    var body: some View {
        @Bindable var python = appState.pythonEnvironment

        Form {
            Section("Python Interpreter") {
                LabeledContent("Status") {
                    statusLabel
                }
                if case .valid(let path, _) = python.status {
                    LabeledContent("Path", value: path)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Auto-Detect") {
                        Task { await python.autoDetect() }
                    }
                    Button("Choose…") {
                        isShowingPicker = true
                    }
                }
            }

            Section("Model Storage") {
                LabeledContent("Location", value: appState.storageService.modelStorageLocation.path)
                    .textSelection(.enabled)
                Button("Choose Folder…") {
                    isShowingStoragePicker = true
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isShowingPicker, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case .success(let url) = result {
                Task { await python.selectInterpreter(at: url.path) }
            }
        }
        .fileImporter(isPresented: $isShowingStoragePicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                appState.storageService.setModelStorageLocation(url)
            }
        }
        .task { await python.restoreSavedInterpreter() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch appState.pythonEnvironment.status {
        case .unknown:
            Text("Not checked").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
        case .valid(_, let version):
            Label("veloxquant_mlx \(version)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

private struct PrivacySettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var telemetryEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Share anonymous usage data", isOn: $telemetryEnabled)
                    .onChange(of: telemetryEnabled) { _, newValue in
                        appState.storageService.setTelemetryEnabled(newValue)
                    }
            } footer: {
                Text("VeloxQuant Studio never uploads your models, prompts, or job logs. This toggle is reserved for future anonymous feature-usage counts — no usage data is collected or sent yet, regardless of this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link("Privacy Policy", destination: URL(string: "https://veloxquant-mlx.netlify.app/privacy.html")!)
            } footer: {
                Text("Covers what this app collects and where your account data (email, session) is stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { telemetryEnabled = appState.storageService.telemetryEnabled }
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("VeloxQuant Studio")
                .font(.title2.weight(.semibold))
            Text("Version 0.1.1")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("A native macOS control app for VeloxQuant-MLX — Apple Silicon KV-cache compression for local LLM inference.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Link("VeloxQuant-MLX on GitHub", destination: URL(string: "https://github.com/rajveer43/VeloxQuant-MLX")!)
                .font(.callout)
            Link("Privacy Policy", destination: URL(string: "https://veloxquant-mlx.netlify.app/privacy.html")!)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
