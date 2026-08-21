import Foundation
import Supabase

protocol AuthenticationServiceProtocol: Sendable {
    func signUp(email: String, password: String) async throws -> AuthSession
    func signIn(email: String, password: String) async throws -> AuthSession
    func signOut() async throws
    /// Restores a session from Keychain and refreshes it against Supabase if
    /// needed. Returns `nil` if there is no stored session or it could not
    /// be refreshed (expired refresh token, revoked, offline with no cache).
    func restoreSession() async -> AuthSession?
}

/// Wraps the Supabase Swift SDK for email/password auth. Session tokens are
/// persisted to Keychain (never UserDefaults/SwiftData) via `KeychainService`.
///
/// The client is built lazily, not in `init()`: this type is constructed
/// unconditionally as part of `AppState`, including in unit tests and before
/// `Secrets.xcconfig` has been filled in with a real project, so failing to
/// resolve config must surface as a catchable error from a call site, not a
/// process crash at app launch.
final class AuthenticationService: AuthenticationServiceProtocol, @unchecked Sendable {
    private var _client: SupabaseClient?

    private func client() throws -> SupabaseClient {
        if let _client { return _client }
        guard let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey else {
            throw AuthError.notConfigured
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        _client = client
        return client
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        let response = try await client().auth.signUp(email: email, password: password)
        guard let session = response.session else {
            // Email confirmation required flows land here with no session yet.
            throw AuthError.confirmationRequired
        }
        let mapped = map(session: session)
        try? KeychainService.saveSession(mapped)
        return mapped
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let session = try await client().auth.signIn(email: email, password: password)
        let mapped = map(session: session)
        try? KeychainService.saveSession(mapped)
        return mapped
    }

    func signOut() async throws {
        try await client().auth.signOut()
        KeychainService.clearSession()
    }

    func restoreSession() async -> AuthSession? {
        guard let stored = KeychainService.loadSession(), let client = try? client() else { return nil }

        do {
            // `auth.session` triggers a refresh internally when the SDK's
            // in-memory session is stale; seed it from Keychain first.
            try await client.auth.setSession(
                accessToken: stored.accessToken,
                refreshToken: stored.refreshToken
            )
            let refreshed = try await client.auth.session
            let mapped = map(session: refreshed)
            try? KeychainService.saveSession(mapped)
            return mapped
        } catch {
            KeychainService.clearSession()
            return nil
        }
    }

    private func map(session: Session) -> AuthSession {
        AuthSession(
            userID: session.user.id.uuidString,
            email: session.user.email ?? "",
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }
}

enum AuthError: LocalizedError {
    case confirmationRequired
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            "Check your inbox to confirm your email before signing in."
        case .notConfigured:
            "VeloxQuant Studio isn't connected to a Supabase project yet. Copy Secrets.xcconfig.example to Secrets.xcconfig and fill in your project URL and anon key."
        }
    }
}
