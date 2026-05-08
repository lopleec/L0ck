import SwiftUI

// MARK: - Import Sheet

/// Standard form sheet for importing and encrypting a file.
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FileStore.self) private var fileStore

    @State private var selectedFileURL: URL?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var storageMode: StorageMode = StorageMode(
        rawValue: UserDefaults.standard.string(forKey: "defaultStorageMode") ?? StorageMode.appFolder.rawValue
    ) ?? .appFolder
    @State private var deleteOriginal = UserDefaults.standard.object(forKey: "deleteOriginalByDefault") as? Bool ?? false
    @State private var isEncrypting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPassword = false

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var passwordMeetsMinimumLength: Bool {
        password.count >= PasswordPolicy.fileEncryptionMinimumLength
    }

    private var isValid: Bool {
        selectedFileURL != nil &&
        passwordsMatch &&
        passwordMeetsMinimumLength
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import File")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Choose a file and create the password used to unlock it later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            Form {
                Section("File") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedFileURL?.lastPathComponent ?? L10n.string("No file selected"))

                            if let url = selectedFileURL {
                                Text(FileType.from(fileName: url.lastPathComponent).displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if selectedFileURL == nil {
                            Button("Choose…") {
                                chooseFile()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Choose…") {
                                chooseFile()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let url = selectedFileURL {
                        LabeledContent("Folder") {
                            Text(url.deletingLastPathComponent().path)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Password") {
                    passwordField("Password", text: $password)
                    passwordField("Confirm Password", text: $confirmPassword)

                    Toggle("Show password", isOn: $showPassword)

                    Text("Use at least 8 characters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !password.isEmpty {
                        LabeledContent("Strength") {
                            HStack(spacing: 8) {
                                passwordStrengthBar
                                Text(passwordStrengthText)
                                    .foregroundStyle(passwordStrengthColor)
                            }
                        }
                    }

                    if !password.isEmpty && !passwordMeetsMinimumLength {
                        Label("Use at least 8 characters.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if !password.isEmpty && !confirmPassword.isEmpty && !passwordsMatch {
                        Label("Passwords do not match", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Storage") {
                    Picker("Store In", selection: $storageMode) {
                        Text("App Folder").tag(StorageMode.appFolder)
                        Text("Same Folder").tag(StorageMode.originalDirectory)
                    }
                    .pickerStyle(.segmented)

                    Text(storageDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Options") {
                    Toggle("Delete original file after encryption", isOn: $deleteOriginal)

                    if deleteOriginal {
                        Text("The source file will be removed after the encrypted copy has been created.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isEncrypting {
                    ProgressView("Encrypting…")
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await encryptFile() }
                } label: {
                    Text("Encrypt")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isEncrypting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 500)
        .alert("Encryption Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? L10n.string("Unknown error"))
        }
    }

    // MARK: - Password Strength

    private var passwordStrength: Int {
        PasswordPolicy.strengthScore(for: password)
    }

    private var passwordStrengthColor: Color {
        switch passwordStrength {
        case 0...1: return .red
        case 2...3: return .orange
        case 4: return .yellow
        default: return .green
        }
    }

    private var passwordStrengthText: String {
        switch passwordStrength {
        case 0...1: return L10n.string("Weak")
        case 2...3: return L10n.string("Medium")
        case 4: return L10n.string("Strong")
        default: return L10n.string("Very Strong")
        }
    }

    private var passwordStrengthBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < passwordStrength ? passwordStrengthColor : Color.secondary.opacity(0.25))
                    .frame(width: 20, height: 5)
            }
        }
    }

    private var storageDescription: String {
        switch storageMode {
        case .appFolder:
            return L10n.string("Keep encrypted files in the protected L0ck vault under ~/Documents/L0ck.")
        case .originalDirectory:
            return L10n.string("Save next to the source file. The encrypted file is locked, but the surrounding folder remains user-managed.")
        }
    }

    // MARK: - Subviews

    private func passwordField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        Group {
            if showPassword {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
    }

    // MARK: - Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L10n.string("Select a file to encrypt")

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
        }
    }

    private func encryptFile() async {
        guard let url = selectedFileURL else { return }

        isEncrypting = true
        errorMessage = nil

        do {
            let record = try await FileService.shared.importAndEncrypt(
                sourceURL: url,
                password: password,
                storageMode: storageMode,
                deleteOriginal: deleteOriginal
            )

            await MainActor.run {
                fileStore.addRecord(record)
                isEncrypting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isEncrypting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
