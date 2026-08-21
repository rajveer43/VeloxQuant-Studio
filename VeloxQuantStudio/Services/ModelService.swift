import Foundation

protocol ModelServiceProtocol: Sendable {
    /// Models already in the local Hugging Face cache, via the same
    /// `scan_cache_dir()` path `veloxquant_mlx/ui/models.py` uses.
    func discoverCachedModels() async throws -> [LocalModel]
    /// User-picked local directory. Detects the format by looking for
    /// `config.json` + weight files, the same shape `mlx_lm.load` expects.
    func importLocalModel(at url: URL) async throws -> LocalModel
    func fetchAvailableMethods() async throws -> MethodsResponse
    func deleteModel(_ model: LocalModel) async throws
}

/// Bridges the model library to the Python side (`veloxquant_mlx.ui.models`)
/// and to locally imported directories. All Python calls route through
/// `PythonEnvironmentService` so a missing/invalid interpreter surfaces one
/// clear error instead of a raw process-launch failure.
final class ModelService: ModelServiceProtocol, @unchecked Sendable {
    private let pythonEnvironment: PythonEnvironmentService
    private let storageService: StorageServiceProtocol

    init(pythonEnvironment: PythonEnvironmentService, storageService: StorageServiceProtocol) {
        self.pythonEnvironment = pythonEnvironment
        self.storageService = storageService
    }

    func discoverCachedModels() async throws -> [LocalModel] {
        let interpreter = try await requireInterpreter()
        let script = """
        import json
        from veloxquant_mlx.ui.models import local_models
        print(json.dumps(local_models()))
        """
        let result = try await ProcessRunner.run(executable: interpreter, arguments: ["-c", script])
        guard result.exitCode == 0 else {
            throw ServiceError.processFailed(result.stderr.isEmpty ? "Could not list cached models." : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([LocalModel].self, from: data)
    }

    func importLocalModel(at url: URL) async throws -> LocalModel {
        let configURL = url.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ServiceError.invalidModelDirectory(
                "No config.json found at \(url.lastPathComponent). Point to an MLX model directory (the kind produced by mlx_lm's convert/quantize, containing config.json and .safetensors weights)."
            )
        }

        let size = try directorySize(url)
        return LocalModel(
            repoID: url.lastPathComponent,
            sizeBytes: size,
            sizeLabel: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
            isMLXCommunity: false,
            localPath: url.path,
            quantizationStatus: .original,
            importedAt: .now
        )
    }

    func fetchAvailableMethods() async throws -> MethodsResponse {
        let interpreter = try await requireInterpreter()
        let result = try await ProcessRunner.run(
            executable: interpreter,
            arguments: ["-m", "veloxquant_mlx", "methods", "--json"]
        )
        guard result.exitCode == 0 else {
            throw ServiceError.processFailed(result.stderr.isEmpty ? "Could not list quantization methods." : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw ServiceError.decodingFailed
        }
        return try JSONDecoder().decode(MethodsResponse.self, from: data)
    }

    func deleteModel(_ model: LocalModel) async throws {
        guard let localPath = model.localPath else {
            throw ServiceError.invalidModelDirectory("Only locally imported models can be deleted from here. Manage Hugging Face cache entries with huggingface-cli.")
        }
        try FileManager.default.removeItem(atPath: localPath)
    }

    @MainActor
    private func requireInterpreter() async throws -> String {
        if let path = pythonEnvironment.interpreterPath { return path }
        await pythonEnvironment.restoreSavedInterpreter()
        guard let path = pythonEnvironment.interpreterPath else {
            throw ServiceError.pythonNotConfigured
        }
        return path
    }

    private func directorySize(_ url: URL) throws -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}

enum ServiceError: LocalizedError {
    case pythonNotConfigured
    case processFailed(String)
    case decodingFailed
    case invalidModelDirectory(String)
    case jobNotFound

    var errorDescription: String? {
        switch self {
        case .pythonNotConfigured:
            "No valid Python interpreter is configured. Set one in Settings → Compute."
        case .processFailed(let message):
            message
        case .decodingFailed:
            "Could not parse the response from VeloxQuant-MLX."
        case .invalidModelDirectory(let message):
            message
        case .jobNotFound:
            "That job could not be found."
        }
    }
}
