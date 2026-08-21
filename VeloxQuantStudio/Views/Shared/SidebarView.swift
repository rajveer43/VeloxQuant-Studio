import SwiftUI

/// Container that switches between the full sidebar and a slim icon-only
/// rail depending on `AppState.isSidebarExpanded`. Unlike
/// `NavigationSplitView`'s native collapse, the rail stays on screen when
/// collapsed so navigation and account access are never more than one click
/// away.
struct SidebarContainer: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppSection

    var body: some View {
        if appState.isSidebarExpanded {
            SidebarView(selection: $selection)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
        } else {
            SidebarRail(selection: $selection)
                .frame(width: 52)
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppSection

    var body: some View {
        @Bindable var appState = appState

        List(selection: $selection) {
            Section {
                ForEach([AppSection.dashboard, .models, .quantization, .benchmarks, .history]) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            } header: {
                HStack {
                    Text("VeloxQuant Studio")
                        .font(.headline)
                    Spacer()
                    SidebarToggleButton(isExpanded: $appState.isSidebarExpanded)
                }
            }

            Section {
                Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                    .tag(AppSection.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            AccountFooter(isExpanded: true)
        }
    }
}

/// Slim always-visible icon rail shown when the full sidebar is collapsed.
/// Every control keeps a tooltip so the app stays fully navigable without
/// expanding.
private struct SidebarRail: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppSection

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 4) {
            SidebarToggleButton(isExpanded: $appState.isSidebarExpanded)
                .padding(.top, 8)

            Divider()
                .padding(.vertical, 4)

            ForEach([AppSection.dashboard, .models, .quantization, .benchmarks, .history]) { section in
                railButton(for: section)
            }

            Spacer()

            railButton(for: .settings)

            AccountFooter(isExpanded: false)
        }
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private func railButton(for section: AppSection) -> some View {
        Button {
            selection = section
        } label: {
            Image(systemName: section.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .background {
                    if selection == section {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                }
                .foregroundStyle(selection == section ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}

private struct SidebarToggleButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide Sidebar" : "Show Sidebar")
    }
}

private struct AccountFooter: View {
    @Environment(AppState.self) private var appState
    let isExpanded: Bool

    var body: some View {
        let session = appState.authViewModel.session

        if isExpanded {
            HStack(spacing: 10) {
                avatar(for: session?.email)

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
        } else {
            Button {
                Task { await appState.authViewModel.signOut() }
            } label: {
                avatar(for: session?.email)
            }
            .buttonStyle(.plain)
            .help(helpText(for: session?.email))
            .padding(.bottom, 10)
        }
    }

    private func avatar(for email: String?) -> some View {
        Circle()
            .fill(Color.accentColor.gradient)
            .frame(width: 28, height: 28)
            .overlay {
                Text(initials(for: email))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    private func initials(for email: String?) -> String {
        guard let email, let first = email.first else { return "?" }
        return String(first).uppercased()
    }

    private func helpText(for email: String?) -> String {
        guard let email else { return "Sign out" }
        return "\(email) — Sign out"
    }
}
