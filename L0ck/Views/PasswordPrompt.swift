import SwiftUI

// MARK: - Password Mode

enum PasswordMode {
    case encrypt
    case decrypt

    var actionTitle: String {
        switch self {
        case .encrypt:
            return L10n.string("Encrypt")
        case .decrypt:
            return L10n.string("Decrypt")
        }
    }
}

// MARK: - Password Prompt

/// Standard password sheet for encryption and decryption actions.
struct PasswordPrompt: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    let mode: PasswordMode
    let onSubmit: (String) async -> Bool

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isProcessing = false

    private var isValid: Bool {
        switch mode {
        case .encrypt:
            return password.count >= PasswordPolicy.fileEncryptionMinimumLength && password == confirmPassword
        case .decrypt:
            return !password.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            Form {
                Section {
                    passwordField("Password", text: $password)

                    if mode == .encrypt {
                        passwordField("Confirm Password", text: $confirmPassword)
                    }

                    Toggle("Show password", isOn: $showPassword)

                    if mode == .encrypt {
                        Text("Use at least 8 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if mode == .encrypt && !password.isEmpty && password.count < PasswordPolicy.fileEncryptionMinimumLength {
                        Label("Use at least 8 characters.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if mode == .encrypt && !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                        Label("Passwords do not match", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        isProcessing = true
                        let shouldDismiss = await onSubmit(password)
                        isProcessing = false
                        if shouldDismiss {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(mode.actionTitle)
                            .frame(minWidth: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isProcessing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 440)
    }

    private func passwordField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        Group {
            if showPassword {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
    }
}
