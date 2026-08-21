import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @Environment(ModelLibraryViewModel.self) private var viewModel
    @State private var isShowingImporter = false
    @State private var pendingDeletion: LocalModel?

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 0) {
            header

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) { viewModel.errorMessage = nil }
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 12)
            }

            content
        }
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingImporter = true
                } label: {
                    Label("Import Model", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $isShowingImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await viewModel.importModel(at: url) }
            }
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.repoID ?? "this model")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let model = pendingDeletion {
                    Task { await viewModel.delete(model) }
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the model files from disk. This can't be undone.")
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack {
            SectionHeader(title: "Models", subtitle: "Models detected in your Hugging Face cache, plus anything you import.")
            Spacer()
            TextField("Search models", text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }
        .padding(Metrics.pagePadding)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Scanning model cache…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredModels.isEmpty {
            EmptyStateView(
                symbol: "shippingbox",
                title: "No models found",
                message: "Import a local MLX model directory, or download one with mlx_lm / huggingface-cli — it'll show up here automatically.",
                actionTitle: "Import Model"
            ) {
                isShowingImporter = true
            }
        } else {
            Table(viewModel.filteredModels) {
                TableColumn("Model") { model in
                    HStack(spacing: 8) {
                        Image(systemName: model.isMLXCommunity ? "checkmark.seal.fill" : "shippingbox")
                            .foregroundStyle(model.isMLXCommunity ? .blue : .secondary)
                        Text(model.repoID)
                            .lineLimit(1)
                    }
                }
                TableColumn("Size") { model in
                    Text(model.sizeLabel)
                }
                .width(90)
                TableColumn("Status") { model in
                    StatusBadge(
                        text: model.quantizationStatus.label,
                        tint: model.quantizationStatus == .quantized ? .green : .secondary
                    )
                }
                .width(120)
                TableColumn("Source") { model in
                    Text(model.localPath != nil ? "Imported" : "HF Cache")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(90)
                TableColumn("") { model in
                    Button(role: .destructive) {
                        pendingDeletion = model
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled(model.localPath == nil)
                    .help(model.localPath == nil ? "Manage Hugging Face cache entries with huggingface-cli" : "Delete")
                }
                .width(32)
            }
        }
    }
}
