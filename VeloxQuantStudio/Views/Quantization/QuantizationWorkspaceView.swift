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
                if !viewModel.availablePresets.isEmpty {
                    presetPicker
                }
                methodFamilyFilter
                methodPicker
                if let method = viewModel.selectedMethod {
                    methodDetail(method)
                    if !editableFields(for: method).isEmpty {
                        parameterEditor(method)
                    }
                }
                networkSection
                generationProfileSection

                if let reason = viewModel.startBlockedReason {
                    ErrorBanner(message: reason)
                }
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

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").font(.headline)
            Text("Not sure where to start? Apply a curated method + settings combination.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(viewModel.availablePresets, id: \.id) { (preset: MethodPreset) in
                    Button {
                        viewModel.applyPreset(preset)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.callout.weight(.semibold))
                                Text(preset.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedMethod?.name == preset.methodName && viewModel.bitWidth == preset.bitWidth {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var methodFamilyFilter: some View {
        Picker("Family", selection: Binding(
            get: { viewModel.familyFilter },
            set: { viewModel.familyFilter = $0 }
        )) {
            Text("All").tag(Optional<MethodFamily>.none)
            ForEach(MethodFamily.allCases) { family in
                Text(family.label).tag(Optional(family))
            }
        }
        .pickerStyle(.segmented)
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
            // Registry blurbs are expected non-empty for every catalog entry,
            // but this keeps the row from ever rendering blank if one isn't.
            Text(method.blurb.isEmpty ? "\(method.family.label) method — \(method.serveTierLabel)." : method.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StatusBadge(text: method.serveTierLabel, tint: method.isServable ? .green : .red)
                StatusBadge(text: method.family.label, tint: .secondary)
                StatusBadge(text: method.coverageLabel, tint: .secondary)
                if method.isAdapted {
                    StatusBadge(text: "Adapted from paper", tint: .orange)
                }
                Spacer()
                if let docsURL = method.docsURL {
                    Link(destination: docsURL) {
                        Label("Docs", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
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

    /// Fields the "Bit width" stepper in `networkSection` already owns end
    /// to end (sent as `--bits`, which `serve.py` turns into
    /// `bit_width_inlier` itself) — editing them here would silently do
    /// nothing, since `QuantizationService` excludes this key from `--set`
    /// to avoid a duplicate-keyword crash in `KVCacheConfig`.
    private static let networkOwnedFields: Set<String> = ["bit_width_inlier"]

    private func editableFields(for method: QuantizationMethod) -> [ConfigField] {
        method.fieldSchema.filter { !Self.networkOwnedFields.contains($0.name) }
    }

    @ViewBuilder
    private func parameterEditor(_ method: QuantizationMethod) -> some View {
        let fields = editableFields(for: method)
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Parameters").font(.headline)
                VStack(spacing: 8) {
                    ForEach(fields) { field in
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

    private var generationProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Profile").font(.headline)
            Text("Remembered generation defaults for chats against this server. Not a server startup flag — these are sent per-request by whatever client you point at the endpoint.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Text("Context window")
                Spacer()
                TextField("Context window", value: Binding(
                    get: { viewModel.generationProfile.contextWindow },
                    set: { viewModel.generationProfile.contextWindow = $0 }
                ), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Max tokens")
                Spacer()
                TextField("Max tokens", value: Binding(
                    get: { viewModel.generationProfile.maxTokens },
                    set: { viewModel.generationProfile.maxTokens = $0 }
                ), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Temperature")
                Spacer()
                Slider(value: Binding(
                    get: { viewModel.generationProfile.temperature },
                    set: { viewModel.generationProfile.temperature = $0 }
                ), in: 0...2)
                    .frame(width: 140)
                Text(String(format: "%.2f", viewModel.generationProfile.temperature))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Top-p")
                Spacer()
                Slider(value: Binding(
                    get: { viewModel.generationProfile.topP },
                    set: { viewModel.generationProfile.topP = $0 }
                ), in: 0...1)
                    .frame(width: 140)
                Text(String(format: "%.2f", viewModel.generationProfile.topP))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
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
