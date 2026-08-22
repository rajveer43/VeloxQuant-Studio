import Foundation

/// The app's remembered default generation knobs (VeloxQuant-MLX#35).
///
/// These are **not** passed to `veloxquant serve` — the server has no
/// startup flags for them because they're per-request OpenAI Chat
/// Completions parameters, not server config. This profile is the app's own
/// pre-filled default for wherever a request actually gets sent (a future
/// test-chat surface or generated client snippet), persisted so it survives
/// relaunch instead of resetting every session.
struct GenerationProfile: Codable, Hashable {
    var contextWindow: Int
    var maxTokens: Int
    var temperature: Double
    var topP: Double

    static let `default` = GenerationProfile(contextWindow: 4096, maxTokens: 512, temperature: 0.7, topP: 0.9)
}
