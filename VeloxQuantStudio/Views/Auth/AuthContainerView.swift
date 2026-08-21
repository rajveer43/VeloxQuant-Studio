import SwiftUI

struct AuthContainerView: View {
    @Environment(AuthViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(minWidth: 380, idealWidth: 440)

            VStack {
                Spacer()
                if viewModel.pendingConfirmationEmail != nil {
                    ConfirmationPendingCard(viewModel: viewModel)
                        .frame(maxWidth: 380)
                } else {
                    AuthFormCard(viewModel: viewModel)
                        .frame(maxWidth: 380)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(.background)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var brandPanel: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            CompressionAnimationView()
                .opacity(0.9)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "cpu")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                Text("VeloxQuant Studio")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Quantize, benchmark, and serve MLX models on Apple Silicon — with the full VeloxQuant-MLX method library.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 320, alignment: .leading)
            }
            .padding(40)
        }
        .clipped()
    }
}

private struct AuthFormCard: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.mode == .signIn ? "Sign in" : "Create your account")
                    .font(.title2.weight(.semibold))
                Text(viewModel.mode == .signIn ? "Welcome back." : "Get started with VeloxQuant Studio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)

                RevealablePasswordField(
                    placeholder: "Password",
                    text: $viewModel.password,
                    contentType: viewModel.mode == .signIn ? .password : .newPassword
                )

                if viewModel.mode == .signUp {
                    RevealablePasswordField(
                        placeholder: "Confirm password",
                        text: $viewModel.confirmPassword,
                        contentType: .newPassword
                    )

                    if !viewModel.confirmPassword.isEmpty && viewModel.password != viewModel.confirmPassword {
                        Label("Passwords don't match yet", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(viewModel.mode == .signIn ? "Sign In" : "Create Account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.isFormValid || viewModel.isLoading)
            .keyboardShortcut(.defaultAction)

            HStack {
                Text(viewModel.mode == .signIn ? "Don't have an account?" : "Already have an account?")
                    .foregroundStyle(.secondary)
                Button(viewModel.mode == .signIn ? "Sign up" : "Sign in") {
                    viewModel.toggleMode()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .font(.callout)
        }
        .padding(32)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
    }
}

/// Shown after sign-up when the Supabase project requires email confirmation
/// before a session is issued. Gives the user a clear next step (check
/// inbox), a way to resend the link, and a way back to the sign-in form.
private struct ConfirmationPendingCard: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 4) {
                    Text("Confirm your email")
                        .font(.title2.weight(.semibold))
                    if let email = viewModel.pendingConfirmationEmail {
                        Text("We sent a confirmation link to")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(email)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Text("Click the link in that email, then come back and sign in. It can take a minute or two to arrive — check spam if you don't see it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let resendMessage = viewModel.resendMessage {
                Text(resendMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await viewModel.resendConfirmationEmail() }
                } label: {
                    if viewModel.isResendingConfirmation {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Resend confirmation email")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isResendingConfirmation)

                Button("Back to sign in") {
                    viewModel.cancelPendingConfirmation()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.callout)
            }
        }
        .padding(32)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
    }
}

/// A password field with a show/hide toggle. Plain `SecureField` gives no
/// way to verify what was actually typed, which made mismatched
/// password/confirm-password fields look identical and the disabled
/// "Create Account" button feel unexplained.
private struct RevealablePasswordField: View {
    let placeholder: String
    @Binding var text: String
    var contentType: NSTextContentType?

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(contentType)
            .focused($isFocused)
            .textFieldStyle(.plain)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFocused ? Color.accentColor : Color(nsColor: .separatorColor))
        )
    }
}
