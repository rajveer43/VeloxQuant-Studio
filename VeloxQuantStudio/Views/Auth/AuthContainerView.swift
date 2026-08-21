import SwiftUI

struct AuthContainerView: View {
    @Environment(AuthViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(minWidth: 380, idealWidth: 440)

            VStack {
                Spacer()
                AuthFormCard(viewModel: viewModel)
                    .frame(maxWidth: 380)
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

                SecureField("Password", text: $viewModel.password)
                    .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
                    .textFieldStyle(.roundedBorder)

                if viewModel.mode == .signUp {
                    SecureField("Confirm password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }
            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
