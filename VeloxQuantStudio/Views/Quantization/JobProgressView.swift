import SwiftUI

struct JobProgressView: View {
    @Bindable var handle: QuantizationJobHandle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let payload = handle.readyPayload {
                readyDetail(payload)
                Divider()
            }
            if handle.readyPayload != nil {
                kvStatsSection
                Divider()
            }
            logPane
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            statusPill

            VStack(alignment: .leading, spacing: 2) {
                Text(handle.request.model.repoID)
                    .font(.headline)
                Text("\(handle.request.method.name) · \(handle.request.bitWidth)-bit · port \(handle.request.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Metrics.pagePadding)
    }

    private var statusPill: some View {
        Group {
            switch handle.processController.state {
            case .idle, .starting:
                ProgressView().controlSize(.small)
            case .running:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse)
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func readyDetail(_ payload: ServeReadyPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Server Ready").font(.subheadline.weight(.semibold))

            if payload.accountingOnly {
                Text(payload.accountingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                endpointRow(label: "OpenAI Base URL", value: payload.endpoints.openaiBaseURL)
                endpointRow(label: "Chat Completions", value: payload.endpoints.chatCompletions)
                endpointRow(label: "Models", value: payload.endpoints.models)
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, 16)
    }

    /// Polls `GET /v1/kv/stats` on the running job (see
    /// `QuantizationJobHandle.startPollingKVStats`) — this is the "benchmark
    /// result" issue #5 and friends ask to confirm renders, which had no UI
    /// at all before this. Distinguishes "not reported yet" from a real
    /// zero, mirroring `build_stats_payload()`'s own honesty contract.
    @ViewBuilder
    private var kvStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cache Stats").font(.subheadline.weight(.semibold))

            if let error = handle.kvStatsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let stats = handle.kvStats {
                if let reason = stats.notReportedReason {
                    Text(reason.prefix(1).uppercased() + reason.dropFirst())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if let keys = stats.keys {
                            byteCountsRow(label: "Keys", counts: keys)
                        }
                        if let values = stats.values {
                            byteCountsRow(label: "Values", counts: values)
                        }
                        if let tokens = stats.tokens {
                            HStack {
                                Text("Tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 130, alignment: .leading)
                                Text("\(tokens.retained) retained / \(tokens.seen) seen")
                                    .font(.caption.monospaced())
                                Spacer()
                            }
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, 16)
    }

    private func byteCountsRow(label: String, counts: KVStats.ByteCounts) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            if let ratio = counts.ratio {
                Text(String(format: "%.2fx smaller (%@ vs %@)", ratio, byteCountString(counts.compressedBytes), byteCountString(counts.fp16Bytes)))
                    .font(.caption.monospaced())
            } else {
                Text("not reported")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func byteCountString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func endpointRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logs")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(handle.processController.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.contains("error") ? .red : .primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.bottom, 16)
                }
                .onChange(of: handle.processController.logLines.count) {
                    if let last = handle.processController.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .background(Color.black.opacity(0.03))
        }
    }
}
