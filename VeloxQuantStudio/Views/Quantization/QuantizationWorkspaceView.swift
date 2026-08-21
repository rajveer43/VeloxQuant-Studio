import SwiftUI

struct QuantizationWorkspaceView: View {
    @Environment(QuantizationViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        HSplitView {
            configPane
                .frame(minWidth: 360, idealWidth: 400, maxWidth: 460)

            progressPane
                .frame(minWidth: 420)
        }
        .navigationTitle("Quantization Workspace")
        .task { await viewModel.loadContext() }
    }

    private var configPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                SectionHeader(title: "Configure Job", subtitle: "Pick a model and compression method, then start.")

                if let loadError = viewModel.loadError {
                    ErrorBanner(message: loadError)
                }
                if let note = viewModel.accountingNote {
                    accountingBanner(note)
                }

                modelPicker
                methodPicker
                if let method = viewModel.selectedMethod {
                    methodDetail(method)
                    if !method.fieldSchema.isEmpty {
                        parameterEditor(method)
                    }
                }
                networkSection

                actionButtons
            }
            .padding(Metrics.pagePadding)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model").font(.headline)
            if viewModel.availableModels.isEmpty {
                Text("No models detected. Import one from the Models tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: Binding(
                    get: { viewModel.selectedModel },
                    set: { viewModel.selectedModel = $0 }
                )) {
                    ForEach(viewModel.availableModels) { model in
                        Text(model.repoID).tag(Optional(model))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compression Method").font(.headline)

            if viewModel.isLoadingMethods {
                ProgressView().controlSize(.small)
            } else if viewModel.availableMethods.isEmpty {
                Text("No methods available. Configure a Python interpreter in Settings → Compute.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Method", selection: Binding(
                    get: { viewModel.selectedMethod },
                    set: { if let method = $0 { viewModel.selectMethod(method) } }
                )) {
                    Section("Servable") {
                        ForEach(viewModel.servableMethods) { method in
                            Text(method.name).tag(Optional(method))
                        }
                    }
                    Section("Unsupported") {
                        ForEach(viewModel.unsupportedMethods) { method in
                            Text(method.name).tag(Optional(method))
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private func methodDetail(_ method: QuantizationMethod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(method.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StatusBadge(text: method.serveTierLabel, tint: method.isServable ? .green : .red)
                StatusBadge(text: method.coverageLabel, tint: .secondary)
                if method.isAdapted {
                    StatusBadge(text: "Adapted from paper", tint: .orange)
                }
            }

            if let reason = method.unsupportedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let deviation = method.paperDeviation {
                Text(deviation)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
    }

    private func parameterEditor(_ method: QuantizationMethod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parameters").font(.headline)
            VStack(spacing: 8) {
                ForEach(method.fieldSchema) { field in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(field.name)
                                .font(.callout)
                            if let help = field.help {
                                Text(help)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        TextField(
                            "value",
                            text: Binding(
                                get: { viewModel.parameterOverrides[field.name] ?? "" },
                                set: { viewModel.parameterOverrides[field.name] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network").font(.headline)
            HStack {
                Text("Bit width")
                Spacer()
                Stepper(value: Binding(get: { viewModel.bitWidth }, set: { viewModel.bitWidth = $0 }), in: 1...8) {
                    Text("\(viewModel.bitWidth)-bit")
                        .monospacedDigit()
                }
                .frame(width: 140)
            }
            HStack {
                Text("Port")
                Spacer()
                TextField("Port", value: Binding(get: { viewModel.port }, set: { viewModel.port = $0 }), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            if viewModel.activeJob != nil {
                Button(role: .destructive) {
                    viewModel.stopJob()
                } label: {
                    Label("Stop Job", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    viewModel.startJob()
                } label: {
                    Label("Start Job", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)
            }
        }
        .controlSize(.large)
    }

    private func accountingBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Progress pane

    private var progressPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job = viewModel.activeJob {
                JobProgressView(handle: job)
            } else {
                EmptyStateView(
                    symbol: "waveform.path.ecg",
                    title: "No active job",
                    message: "Configure a model and method on the left, then start a job to see live progress and logs here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
