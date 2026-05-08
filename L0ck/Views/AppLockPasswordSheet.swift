import SwiftUI

struct AppLockPasswordSheet: View {
    enum Mode: String, Identifiable {
        case create
        case change

        var id: String { rawValue }

        var title: String {
            switch self {
            case .create:
                return L10n.string("Turn On App Password")
            case .change:
                return L10n.string("Change App Password")
            }
        }

        var message: String {
            switch self {
            case .create:
                return L10n.string("Create the password that unlocks L0ck each time it opens.")
            case .change:
                return L10n.string("Set a new password for unlocking L0ck on launch.")
            }
        }

        var actionTitle: String {
            switch self {
            case .create:
                return L10n.string("Turn On")
            case .change:
                return L10n.string("Save")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSaved: () -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var isValid: Bool {
        password.count >= PasswordPolicy.appLockMinimumLength && passwordsMatch
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(mode.message)
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
                    passwordField("Confirm Password", text: $confirmPassword)
                    Toggle("Show password", isOn: $showPassword)

                    Text("Use at least 4 characters. You can change this later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !password.isEmpty && password.count < PasswordPolicy.appLockMinimumLength {
                        Label("Use at least 4 characters.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if !password.isEmpty && !confirmPassword.isEmpty && !passwordsMatch {
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
                    savePassword()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(mode.actionTitle)
                            .frame(minWidth: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSaving)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 420)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? L10n.string("Unknown error"))
        }
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

    private func savePassword() {
        isSaving = true

        do {
            try KeychainService.shared.saveAppLockPassword(password)
            onSaved()
            isSaving = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isSaving = false
        }
    }
}
