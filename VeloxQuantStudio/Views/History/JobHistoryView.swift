import SwiftUI

struct JobHistoryView: View {
    @Environment(HistoryViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            List(viewModel.jobs, selection: $viewModel.selectedJob) { job in
                HistoryRow(job: job)
                    .tag(job)
            }
            .listStyle(.inset)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Filter", selection: $viewModel.statusFilter) {
                        Text("All").tag(JobStatus?.none)
                        ForEach(JobStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(Optional(status))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } detail: {
            if let job = viewModel.selectedJob {
                JobDetailView(job: job)
            } else {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "Select a job",
                    message: "Choose a job from the list to see its parameters, logs, and benchmark results."
                )
            }
        }
        .navigationTitle("Job History")
        .task { viewModel.refresh() }
    }
}

private struct HistoryRow: View {
    let job: QuantizationJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.modelName).font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
                StatusBadge(text: job.status.label, tint: statusColor)
            }
            Text("\(job.method) · \(job.bitWidth)-bit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(job.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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

private struct JobDetailView: View {
    let job: QuantizationJob
    @Environment(HistoryViewModel.self) private var viewModel
    @State private var pendingDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header

                detailGrid

                if let error = job.errorMessage {
                    ErrorBanner(message: error)
                }

                if let result = viewModel.benchmarkResult(for: job) {
                    BenchmarkResultCard(job: job, result: result)
                }

                if !job.logOutput.isEmpty {
                    logSection
                }
            }
            .padding(Metrics.pagePadding)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    pendingDeletion = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this job record?", isPresented: $pendingDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { viewModel.delete(job) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.modelName).font(.title2.weight(.semibold))
                Text("\(job.method) · \(job.bitWidth)-bit")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: job.status.label, tint: statusColor)
        }
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            StatCard(title: "Started", value: job.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let duration = job.duration {
                StatCard(title: "Duration", value: formattedDuration(duration))
            }
            StatCard(title: "Parameters", value: job.parametersJSON == "{}" ? "Default" : "Custom")
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logs").font(.headline)
            ScrollView {
                Text(job.logOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 320)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
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

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}
