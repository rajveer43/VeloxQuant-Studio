import SwiftUI

struct BenchmarkView: View {
    @Environment(HistoryViewModel.self) private var historyViewModel
    @Environment(AppState.self) private var appState
    @State private var recommendation: RecommendResponse?
    @State private var isRecommending = false
    @State private var recommendError: String?

    @State private var chip: MacChipFamily = .m3
    @State private var ramGB = 16
    @State private var modelClass = "7B"
    @State private var goal = "everyday"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                SectionHeader(title: "Benchmarks", subtitle: "Compare methods, and see before/after results from past jobs.")

                recommenderCard

                if historyViewModel.jobsWithBenchmarks.isEmpty {
                    EmptyStateView(
                        symbol: "chart.bar.xaxis",
                        title: "No benchmark results yet",
                        message: "Results from completed quantization jobs will appear here for comparison.",
                        actionTitle: "Open Quantization Workspace"
                    ) {
                        appState.selectedSection = .quantization
                    }
                    .frame(height: 260)
                } else {
                    ForEach(historyViewModel.jobsWithBenchmarks) { job in
                        if let result = historyViewModel.benchmarkResult(for: job) {
                            BenchmarkResultCard(job: job, result: result)
                        }
                    }
                }
            }
            .padding(Metrics.pagePadding)
        }
        .navigationTitle("Benchmarks")
        .task { await appState.hardwareService.currentHardware().chipFamily.map { chip = $0 } }
    }

    private var recommenderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Method Recommender").font(.headline)
            Text("Hardware-aware suggestion from VeloxQuant's Mac recommender — no model download required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Picker("Chip", selection: $chip) {
                    ForEach(MacChipFamily.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("RAM", selection: $ramGB) {
                    ForEach([8, 16, 24, 32, 36, 48, 64, 128], id: \.self) { Text("\($0) GB").tag($0) }
                }
                Picker("Model", selection: $modelClass) {
                    ForEach(["1B", "3B", "7B", "14B", "32B"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Goal", selection: $goal) {
                    Text("Everyday").tag("everyday")
                    Text("Max compression").tag("max_key_accounting")
                    Text("Max context").tag("max_context")
                    Text("Best quality").tag("best_quality")
                    Text("Constant memory").tag("constant_memory")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Button {
                Task { await runRecommendation() }
            } label: {
                if isRecommending {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Get Recommendation")
                }
            }
            .buttonStyle(.borderedProminent)

            if let recommendError {
                ErrorBanner(message: recommendError)
            }

            if let recommendation {
                recommendationResult(recommendation.recommendation)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
    }

    private func recommendationResult(_ rec: RecommendResponse.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(rec.method)
                    .font(.title3.weight(.semibold))
                StatusBadge(text: rec.residentSavingsLikely ? "Resident savings likely" : "Accounting-only", tint: rec.residentSavingsLikely ? .green : .orange)
            }
            Text(rec.rationale)
                .font(.callout)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                StatCard(title: "Key Compression", value: String(format: "%.1fx", rec.keyAccountingRatio))
                StatCard(title: "KV fp16", value: String(format: "%.0f MB", rec.kvFP16MB))
                StatCard(title: "KV Compressed (est.)", value: String(format: "%.0f MB", rec.kvCompressedMBEstimate))
            }

            if !rec.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rec.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func runRecommendation() async {
        isRecommending = true
        recommendError = nil
        defer { isRecommending = false }
        do {
            recommendation = try await appState.benchmarkService.recommend(
                request: RecommendRequest(chip: chip, ramGB: ramGB, modelClass: modelClass, goal: goal)
            )
        } catch {
            recommendError = error.localizedDescription
        }
    }
}

struct BenchmarkResultCard: View {
    let job: QuantizationJob
    let result: BenchmarkResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.modelName).font(.headline)
                    Text("\(job.method) · \(job.bitWidth)-bit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if result.isAccountingOnly {
                    StatusBadge(text: "Accounting-only", tint: .orange)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                comparisonCard("Model Size", before: result.modelSizeBeforeBytes.map(formatBytes), after: result.modelSizeAfterBytes.map(formatBytes))
                comparisonCard("Memory Usage", before: result.memoryUsageBeforeBytes.map(formatBytes), after: result.memoryUsageAfterBytes.map(formatBytes))
                if let ratio = result.compressionRatio {
                    StatCard(title: "Compression Ratio", value: String(format: "%.2fx", ratio), symbol: "arrow.down.right.circle")
                }
                comparisonCard("Load Time", before: result.loadTimeBeforeSeconds.map { String(format: "%.2fs", $0) }, after: result.loadTimeAfterSeconds.map { String(format: "%.2fs", $0) })
                comparisonCard("Inference Latency", before: result.inferenceLatencyBeforeMs.map { String(format: "%.0fms", $0) }, after: result.inferenceLatencyAfterMs.map { String(format: "%.0fms", $0) })
                comparisonCard("Throughput", before: result.tokensPerSecondBefore.map { String(format: "%.1f tok/s", $0) }, after: result.tokensPerSecondAfter.map { String(format: "%.1f tok/s", $0) })
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
    }

    private func comparisonCard(_ title: String, before: String?, after: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(before ?? "—").foregroundStyle(.secondary).strikethrough(before != nil && after != nil)
                if after != nil {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(after ?? "—").font(.body.weight(.semibold))
            }
            .font(.callout)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
