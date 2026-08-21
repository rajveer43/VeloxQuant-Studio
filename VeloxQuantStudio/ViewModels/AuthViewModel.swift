import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    enum Mode {
        case signIn
        case signUp
    }

    private let authService: AuthenticationServiceProtocol

    var session: AuthSession?
    var mode: Mode = .signIn
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var infoMessage: String?

    var isFormValid: Bool {
        guard email.contains("@"), password.count >= 8 else { return false }
        if mode == .signUp { return password == confirmPassword }
        return true
    }

    init(authService: AuthenticationServiceProtocol) {
        self.authService = authService
    }

    func restoreSession() async {
        isLoading = true
        defer { isLoading = false }
        session = await authService.restoreSession()
    }

    func submit() async {
        guard isFormValid else {
            errorMessage = mode == .signUp && password != confirmPassword
                ? "Passwords don't match."
                : "Enter a valid email and an 8+ character password."
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                session = try await authService.signIn(email: email, password: password)
            case .signUp:
                session = try await authService.signUp(email: email, password: password)
            }
            password = ""
            confirmPassword = ""
        } catch AuthError.confirmationRequired {
            infoMessage = "Check your inbox to confirm your email, then sign in."
            mode = .signIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        session = nil
    }

    func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
        infoMessage = nil
    }
}
