import Foundation

/// A model available to the app — either discovered in the Hugging Face
/// cache (mirrors `veloxquant_mlx/ui/models.py:local_models()`) or imported
/// by hand from a local directory.
struct LocalModel: Identifiable, Codable, Hashable {
    var id: String { repoID }

    let repoID: String
    let sizeBytes: Int64
    let sizeLabel: String
    let isMLXCommunity: Bool
    var localPath: String?
    var quantizationStatus: QuantizationStatus
    var importedAt: Date?

    enum CodingKeys: String, CodingKey {
        case repoID = "repo_id"
        case sizeBytes = "size_bytes"
        case sizeLabel = "size_label"
        case isMLXCommunity = "is_mlx"
    }

    init(
        repoID: String,
        sizeBytes: Int64,
        sizeLabel: String,
        isMLXCommunity: Bool,
        localPath: String? = nil,
        quantizationStatus: QuantizationStatus = .original,
        importedAt: Date? = nil
    ) {
        self.repoID = repoID
        self.sizeBytes = sizeBytes
        self.sizeLabel = sizeLabel
        self.isMLXCommunity = isMLXCommunity
        self.localPath = localPath
        self.quantizationStatus = quantizationStatus
        self.importedAt = importedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repoID = try container.decode(String.self, forKey: .repoID)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        sizeLabel = try container.decode(String.self, forKey: .sizeLabel)
        isMLXCommunity = try container.decode(Bool.self, forKey: .isMLXCommunity)
        localPath = nil
        quantizationStatus = .original
        importedAt = nil
    }
}

enum QuantizationStatus: String, Codable, Hashable {
    case original
    case quantized
    case processing

    var label: String {
        switch self {
        case .original: "Original"
        case .quantized: "Quantized"
        case .processing: "Processing…"
        }
    }
}
