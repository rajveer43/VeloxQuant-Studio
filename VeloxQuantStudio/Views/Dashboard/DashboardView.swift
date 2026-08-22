import SwiftUI

struct DashboardView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                SectionHeader(title: "Dashboard", subtitle: "Your Mac, your models, and what's been running.")

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                hardwareSection
                statusSection
                recentJobsSection
            }
            .padding(Metrics.pagePadding)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await viewModel.onAppear() }
    }

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Mac").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Metrics.cardSpacing)], spacing: Metrics.cardSpacing) {
                StatCard(title: "Chip", value: viewModel.hardware.chipName, symbol: "cpu", tint: .blue)
                StatCard(
                    title: "Unified Memory",
                    value: String(format: "%.0f GB", viewModel.hardware.unifiedMemoryGB),
                    subtitle: "\(viewModel.hardware.performanceCoreCount)P + \(viewModel.hardware.efficiencyCoreCount)E cores",
                    symbol: "memorychip",
                    tint: .purple
                )
                StatCard(title: "macOS", value: viewModel.hardware.macOSVersion, symbol: "apple.logo", tint: .secondary)
                StatCard(
                    title: "VeloxQuant-MLX",
                    value: viewModel.veloxquantVersion,
                    subtitle: pythonStatusSubtitle,
                    symbol: pythonStatusSymbol,
                    tint: pythonStatusTint
                )
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Metrics.cardSpacing)], spacing: Metrics.cardSpacing) {
                Button {
                    appState.selectedSection = .models
                } label: {
                    StatCard(
                        title: "Installed Models",
                        value: viewModel.isLoadingModels ? "…" : "\(viewModel.installedModelCount)",
                        symbol: "shippingbox.fill",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    appState.selectedSection = .history
                } label: {
                    StatCard(
                        title: "Recent Jobs",
                        value: "\(viewModel.recentJobs.count)",
                        subtitle: jobsSummarySubtitle,
                        symbol: "clock.arrow.circlepath",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var jobsSummarySubtitle: String? {
        let running = viewModel.recentJobs.filter { $0.status == .running }.count
        return running > 0 ? "\(running) running now" : nil
    }

    private var recentJobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Jobs").font(.headline)
                Spacer()
                Button("View All") { appState.selectedSection = .history }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            if viewModel.recentJobs.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "No jobs yet",
                    message: "Start a quantization job to see it appear here.",
                    actionTitle: "Open Quantization Workspace"
                ) {
                    appState.selectedSection = .quantization
                }
                .frame(height: 220)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(viewModel.recentJobs.enumerated()), id: \.element.id) { index, job in
                        Button {
                            appState.selectedSection = .history
                        } label: {
                            JobRow(job: job)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.recentJobs.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                        .strokeBorder(.quaternary.opacity(0.4), lineWidth: 1)
                )
            }
        }
    }

    private var pythonStatusSubtitle: String {
        switch viewModel.pythonStatus {
        case .unknown, .checking: "Checking…"
        case .valid: "Ready"
        case .invalid: "Not configured"
        }
    }

    private var pythonStatusTint: Color {
        switch viewModel.pythonStatus {
        case .valid: .green
        case .invalid: .orange
        default: .secondary
        }
    }

    private var pythonStatusSymbol: String {
        switch viewModel.pythonStatus {
        case .valid: "checkmark.seal.fill"
        case .invalid: "exclamationmark.triangle.fill"
        default: "shippingbox"
        }
    }
}

struct JobRow: View {
    let job: QuantizationJob
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.callout)
                .foregroundStyle(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.modelName).font(.callout.weight(.medium))
                HStack(spacing: 4) {
                    Text("\(job.method) · \(job.bitWidth)-bit")
                    if let reason = job.errorMessage, job.status == .failed {
                        Text("· \(reason)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption)
                .foregroundStyle(job.status == .failed ? .red.opacity(0.85) : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(job.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let duration = job.duration {
                    Text(formattedDuration(duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            StatusBadge(text: job.status.label, tint: statusColor)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return String(format: "%dm %ds", minutes, remaining)
    }

    private var statusSymbol: String {
        switch job.status {
        case .running: "circle.dotted"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
