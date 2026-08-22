import Foundation

protocol StorageServiceProtocol: Sendable {
    var modelStorageLocation: URL { get }
    func setModelStorageLocation(_ url: URL)
    var telemetryEnabled: Bool { get }
    func setTelemetryEnabled(_ enabled: Bool)
    var generationProfile: GenerationProfile { get }
    func setGenerationProfile(_ profile: GenerationProfile)
}

/// Thin `UserDefaults` wrapper for app-level settings that aren't part of a
/// job or session — storage location, telemetry opt-in. Kept as its own
/// service (rather than scattering `UserDefaults` calls across views) so a
/// future migration to a config file is a one-file change.
final class StorageService: StorageServiceProtocol, @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let storageLocationKey = "veloxquant.modelStorageLocation"
    private let telemetryKey = "veloxquant.telemetryEnabled"
    private let generationProfileKey = "veloxquant.generationProfile"

    var modelStorageLocation: URL {
        if let path = defaults.string(forKey: storageLocationKey) {
            return URL(fileURLWithPath: path)
        }
        return defaultLocation()
    }

    func setModelStorageLocation(_ url: URL) {
        defaults.set(url.path, forKey: storageLocationKey)
    }

    var telemetryEnabled: Bool {
        defaults.object(forKey: telemetryKey) == nil ? false : defaults.bool(forKey: telemetryKey)
    }

    func setTelemetryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: telemetryKey)
    }

    var generationProfile: GenerationProfile {
        guard let data = defaults.data(forKey: generationProfileKey),
              let profile = try? JSONDecoder().decode(GenerationProfile.self, from: data) else {
            return .default
        }
        return profile
    }

    func setGenerationProfile(_ profile: GenerationProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: generationProfileKey)
    }

    private func defaultLocation() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("VeloxQuant Studio/Models", isDirectory: true)
    }
}
