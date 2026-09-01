import SwiftUI

/// Renders one `ProfileResponse` — the per-layer latency/memory breakdown
/// from `veloxquant profile --json` (issue #45). Sortable so a slow layer or
/// a memory spike is easy to spot even with 40+ rows, the norm per the
/// method-verification sweep (#1–#41) this view doubles as a tool for.
struct ProfileResultCard: View {
    let result: ProfileResponse
    @State private var sortOrder = [KeyPathComparator(\ProfileResponse.LayerResult.layerIndex)]

    private var sortedLayers: [ProfileResponse.LayerResult] {
        result.layers.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.model).font(.headline)
                    Text("\(result.method) · \(result.bits)-bit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if result.accountingOnly {
                    StatusBadge(text: "Accounting-only", tint: .orange)
                }
            }

            if result.accountingOnly {
                Text(result.accountingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                StatCard(title: "Total Latency", value: String(format: "%.1f ms", result.summary.totalLatencyMs))
                StatCard(title: "Peak Memory", value: formatBytes(result.summary.peakMemoryBytes))
                StatCard(title: "Mean Compression", value: String(format: "%.2fx", result.summary.meanCompressionRatio))
                StatCard(title: "Throughput", value: String(format: "%.1f tok/s", result.summary.tokensPerSecond))
            }

            layerTable
        }
        .padding(16)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
    }

    private var layerTable: some View {
        Table(sortedLayers, sortOrder: $sortOrder) {
            TableColumn("Layer", value: \.layerIndex) { layer in
                Text("\(layer.layerIndex)")
            }
            .width(60)

            TableColumn("Compute", value: \.computeLatencyMs) { layer in
                Text(String(format: "%.2f ms", layer.computeLatencyMs))
            }

            TableColumn("Peak Memory", value: \.peakMemoryBytes) { layer in
                Text(formatBytes(layer.peakMemoryBytes))
            }

            TableColumn("Compression", value: \.compressionRatio) { layer in
                Text(String(format: "%.2fx", layer.compressionRatio))
            }
        }
        .frame(minHeight: 240, maxHeight: 420)
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
