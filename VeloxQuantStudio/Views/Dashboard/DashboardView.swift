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
                StatCard(title: "Chip", value: viewModel.hardware.chipName, symbol: "cpu")
                StatCard(
                    title: "Unified Memory",
                    value: String(format: "%.0f GB", viewModel.hardware.unifiedMemoryGB),
                    subtitle: "\(viewModel.hardware.performanceCoreCount)P + \(viewModel.hardware.efficiencyCoreCount)E cores",
                    symbol: "memorychip"
                )
                StatCard(title: "macOS", value: viewModel.hardware.macOSVersion, symbol: "apple.logo")
                StatCard(
                    title: "VeloxQuant-MLX",
                    value: viewModel.veloxquantVersion,
                    subtitle: pythonStatusSubtitle,
                    symbol: "shippingbox",
                    tint: pythonStatusTint
                )
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Metrics.cardSpacing)], spacing: Metrics.cardSpacing) {
                StatCard(
                    title: "Installed Models",
                    value: viewModel.isLoadingModels ? "…" : "\(viewModel.installedModelCount)",
                    symbol: "shippingbox.fill"
                )
                StatCard(
                    title: "Recent Jobs",
                    value: "\(viewModel.recentJobs.count)",
                    symbol: "clock.arrow.circlepath"
                )
            }
        }
    }

    private var recentJobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Jobs").font(.headline)
                Spacer()
                Button("View All") { appState.selectedSection = .history }
                    .buttonStyle(.link)
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
                    ForEach(viewModel.recentJobs) { job in
                        JobRow(job: job)
                    }
                }
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
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
}

struct JobRow: View {
    let job: QuantizationJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.modelName).font(.callout.weight(.medium))
                Text("\(job.method) · \(job.bitWidth)-bit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(job.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            StatusBadge(text: job.status.label, tint: statusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
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
