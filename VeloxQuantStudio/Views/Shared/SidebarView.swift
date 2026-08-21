import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach([AppSection.dashboard, .models, .quantization, .benchmarks, .history]) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            } header: {
                Text("VeloxQuant Studio")
                    .font(.headline)
            }

            Section {
                Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                    .tag(AppSection.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            AccountFooter()
        }
    }
}

private struct AccountFooter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let session = appState.authViewModel.session

        HStack(spacing: 10) {
            Circle()
                .fill(Color.accentColor.gradient)
                .frame(width: 28, height: 28)
                .overlay {
                    Text(initials(for: session?.email))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(session?.email ?? "Not signed in")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("Sign out")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await appState.authViewModel.signOut() }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func initials(for email: String?) -> String {
        guard let email, let first = email.first else { return "?" }
        return String(first).uppercased()
    }
}
