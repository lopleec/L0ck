import SwiftUI

// MARK: - Key Backup View

/// Standard form sheet for exporting and importing encryption key backups.
struct KeyBackupView: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: (() -> Void)?

    @State private var mode: BackupMode = .export
    @State private var backupPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var successMessage: String?

    enum BackupMode: CaseIterable {
        case export
        case restore

        var title: String {
            switch self {
            case .export:
                return L10n.string("Export")
            case .restore:
                return L10n.string("Import")
            }
        }
    }

    private var isExportValid: Bool {
        backupPassword.count >= 8 && backupPassword == confirmPassword
    }

    private var isPrimaryActionEnabled: Bool {
        switch mode {
        case .export:
            return isExportValid && !isProcessing
        case .restore:
            return !backupPassword.isEmpty && !isProcessing
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Key Backup")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Export your current keys or restore them from an encrypted backup file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(BackupMode.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .export {
                    Section("Backup Password") {
                        passwordField("Password", text: $backupPassword)
                        passwordField("Confirm Password", text: $confirmPassword)
                        Toggle("Show password", isOn: $showPassword)
                    }

                    Section("About Backups") {
                        Text("Backups are encrypted with the password you choose here.")
                        Text("Store the exported file somewhere safe. You will need both the file and the backup password to restore your keys.")
                    }
                } else {
                    Section("Backup Password") {
                        passwordField("Password", text: $backupPassword)
                        Toggle("Show password", isOn: $showPassword)
                    }

                    Section("Warning") {
                        Text("Importing a backup replaces the keys currently stored on this Mac.")
                        Text("Only restore a backup if you intend to use it for all future decryption on this device.")
                    }
                }

                if let successMessage {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    if mode == .export {
                        exportKeys()
                    } else {
                        importKeys()
                    }
                } label: {
                    Text(primaryActionTitle)
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isPrimaryActionEnabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 500, height: 430)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? L10n.string("Unknown error"))
        }
    }

    private var primaryActionTitle: String {
        mode == .export ? L10n.string("Export Backup") : L10n.string("Import Backup")
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

    // MARK: - Actions

    private func exportKeys() {
        isProcessing = true
        successMessage = nil

        do {
            let backupData = try KeychainService.shared.exportKeys(backupPassword: backupPassword)

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "L0ck-KeyBackup.l0ckkeys"
            panel.canCreateDirectories = true

            if panel.runModal() == .OK, let url = panel.url {
                try backupData.write(to: url, options: .atomic)
                successMessage = L10n.string("Backup exported successfully.")
                onComplete?()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isProcessing = false
    }

    private func importKeys() {
        isProcessing = true
        successMessage = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L10n.string("Select a L0ck key backup file")

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let backupData = try Data(contentsOf: url)
                try KeychainService.shared.importKeys(
                    backupData: backupData,
                    backupPassword: backupPassword
                )
                successMessage = L10n.string("Backup imported successfully.")
                onComplete?()
            } catch {
                errorMessage = L10n.string("Failed to import keys. Check the backup file and password.")
                showError = true
            }
        }

        isProcessing = false
    }
}
