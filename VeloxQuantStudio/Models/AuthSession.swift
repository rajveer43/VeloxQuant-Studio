import Foundation

/// Local representation of an authenticated session. Deliberately narrow —
/// only what the UI needs — so a future licensing/subscription field can be
/// added without reshaping every call site.
struct AuthSession: Equatable, Codable {
    let userID: String
    let email: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// Reserved for the subscriptions/licensing work called out in the MVP
    /// brief. Unused today; `nil` means "no plan info yet", not "free tier".
    var planIdentifier: String?
}
