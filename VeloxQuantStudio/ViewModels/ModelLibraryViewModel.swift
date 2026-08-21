import Foundation
import Observation

@MainActor
@Observable
final class ModelLibraryViewModel {
    private let modelService: ModelServiceProtocol

    private(set) var models: [LocalModel] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var searchText: String = ""

    var filteredModels: [LocalModel] {
        guard !searchText.isEmpty else { return models }
        return models.filter { $0.repoID.localizedCaseInsensitiveContains(searchText) }
    }

    init(modelService: ModelServiceProtocol) {
        self.modelService = modelService
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            models = try await modelService.discoverCachedModels()
        } catch ServiceError.pythonNotConfigured {
            errorMessage = "No Python interpreter configured yet. Set one in Settings → Compute to see cached models."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importModel(at url: URL) async {
        do {
            let imported = try await modelService.importLocalModel(at: url)
            if !models.contains(where: { $0.repoID == imported.repoID }) {
                models.insert(imported, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ model: LocalModel) async {
        do {
            try await modelService.deleteModel(model)
            models.removeAll { $0.id == model.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
