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

    /// Set right after a sign-up call that requires the user to click a
    /// confirmation link before they can sign in. While non-nil, the auth
    /// screen shows a dedicated "check your email" state instead of the form.
    var pendingConfirmationEmail: String?
    var isResendingConfirmation: Bool = false
    var resendMessage: String?

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
            pendingConfirmationEmail = email
            password = ""
            confirmPassword = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resendConfirmationEmail() async {
        guard let pendingConfirmationEmail else { return }
        isResendingConfirmation = true
        resendMessage = nil
        defer { isResendingConfirmation = false }

        do {
            try await authService.resendConfirmationEmail(email: pendingConfirmationEmail)
            resendMessage = "Confirmation email sent again."
        } catch {
            resendMessage = error.localizedDescription
        }
    }

    /// Returns to the sign-in form from the "check your email" state.
    func cancelPendingConfirmation() {
        pendingConfirmationEmail = nil
        resendMessage = nil
        mode = .signIn
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
    }
}
