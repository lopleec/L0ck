import SwiftUI
import AppKit

struct AppUnlockView: View {
    @Environment(AppSessionState.self) private var appSession

    @State private var password = ""
    @State private var showPassword = false
    @State private var isUnlocking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Label("L0ck", systemImage: "lock.shield")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Unlock L0ck")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Enter your app password to continue.")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        passwordField
                        Toggle("Show password", isOn: $showPassword)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("App Lock", systemImage: "lock")
                }

                HStack {
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }

                    Spacer()

                    Button {
                        Task { await unlockApp() }
                    } label: {
                        HStack(spacing: 6) {
                            if isUnlocking {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text("Unlock")
                                .frame(minWidth: 80)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isUnlocking)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var passwordField: some View {
        Group {
            if showPassword {
                TextField("Password", text: $password)
            } else {
                SecureField("Password", text: $password)
            }
        }
        .onSubmit {
            Task { await unlockApp() }
        }
    }

    @MainActor
    private func unlockApp() async {
        isUnlocking = true

        do {
            if try KeychainService.shared.verifyAppLockPassword(password) {
                appSession.unlockForCurrentSession()
                errorMessage = nil
            } else {
                errorMessage = L10n.string("Incorrect app password.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isUnlocking = false
    }
}
