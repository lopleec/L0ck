import SwiftUI

// MARK: - Setup View

/// First-launch setup wizard for key generation and backup guidance.
struct SetupView: View {
    @Environment(AppSessionState.self) private var appSession
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    let onSetupStateChanged: () -> Void
    let onFinished: () -> Void

    @State private var currentStep: SetupStep = .welcome
    @State private var keysGenerated = false
    @State private var hasStartedGeneration = false
    @State private var showBackupSheet = false
    @State private var errorMessage: String?
    @State private var appPassword = ""
    @State private var confirmAppPassword = ""
    @State private var showAppPassword = false
    @State private var appPasswordError: String?

    private enum SetupStep: Int, CaseIterable {
        case welcome
        case keys
        case appLock
        case backup

        var title: String {
            switch self {
            case .welcome: return L10n.string("Welcome")
            case .keys: return L10n.string("Set Up Device Keys")
            case .appLock: return L10n.string("Set App Password")
            case .backup: return L10n.string("Create a Backup")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: return L10n.string("A quick overview before you import your first file.")
            case .keys: return L10n.string("L0ck stores its local keys in your login keychain.")
            case .appLock: return L10n.string("Set the password L0ck asks for every time the app opens.")
            case .backup: return L10n.string("Save a recovery file before you rely on this Mac.")
            }
        }

        var systemImage: String {
            switch self {
            case .welcome: return "hand.wave"
            case .keys: return "key.horizontal"
            case .appLock: return "lock"
            case .backup: return "externaldrive.badge.timemachine"
            }
        }
    }

    private var needsAppPasswordSetup: Bool {
        appLockEnabled && !KeychainService.shared.hasAppLockPassword
    }

    private var appPasswordsMatch: Bool {
        !appPassword.isEmpty && appPassword == confirmAppPassword
    }

    private var isAppPasswordValid: Bool {
        appPassword.count >= PasswordPolicy.appLockMinimumLength && appPasswordsMatch
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            currentStepContent
            Divider()
            footer
        }
        .frame(width: 620, height: 460)
        .sheet(isPresented: $showBackupSheet) {
            KeyBackupView {
                showBackupSheet = false
                finishSetup()
            }
        }
        .task(id: currentStep) {
            if currentStep == .keys {
                await generateKeysIfNeeded()
            }
        }
    }

    // MARK: - Layout

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Set Up L0ck", systemImage: "lock.shield")
                    .font(.headline)

                Spacer()

                Text(L10n.format("Step %@ of %@", String(currentStep.rawValue + 1), String(SetupStep.allCases.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(SetupStep.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 6)
                }
            }

            Text(currentStep.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(currentStep.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        VStack {
            Spacer(minLength: 0)

            switch currentStep {
            case .welcome:
                welcomeContent
            case .keys:
                keyGenerationContent
            case .appLock:
                appLockContent
            case .backup:
                backupContent
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepPanel<Content: View>(
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.accent)

            content()
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func bulletRow(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step Content

    private var welcomeContent: some View {
        stepPanel(symbol: SetupStep.welcome.systemImage) {
            Text("L0ck keeps each file tied to your password and the keys stored on this Mac.")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    bulletRow("Choose a password when you encrypt a file.", systemImage: "checkmark.circle")
                    bulletRow("L0ck stores device keys in your login keychain.", systemImage: "key.horizontal")
                    bulletRow("L0ck can also ask for an app password each time it opens.", systemImage: "lock")
                    bulletRow("You can manage key backups later from the main window.", systemImage: "externaldrive")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("How It Works", systemImage: "checklist")
            }
        }
    }

    private var keyGenerationContent: some View {
        stepPanel(symbol: SetupStep.keys.systemImage) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if keysGenerated {
                        Label("Device keys are ready.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("L0ck can now use this Mac's keychain automatically when you import or unlock files.")
                            .foregroundStyle(.secondary)
                    } else if let errorMessage {
                        Label("L0ck couldn't prepare the local keys.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)

                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Try Again") {
                            resetKeyGeneration()
                            Task { await generateKeysIfNeeded() }
                        }
                    } else {
                        ProgressView("Creating device keys…")
                        Text("This runs once on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Login Keychain", systemImage: "key.horizontal")
            }

            GroupBox {
                Text("These keys stay in your login keychain. You normally won't need to manage them unless you move to a new Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("What Happens Next", systemImage: "info.circle")
            }
        }
    }

    private var appLockContent: some View {
        stepPanel(symbol: SetupStep.appLock.systemImage) {
            if needsAppPasswordSetup {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        passwordField("Password", text: $appPassword)
                        passwordField("Confirm Password", text: $confirmAppPassword)
                        Toggle("Show password", isOn: $showAppPassword)

                        Text("Use at least 4 characters. You can change or turn this off later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !appPassword.isEmpty && appPassword.count < PasswordPolicy.appLockMinimumLength {
                            Label("Use at least 4 characters.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }

                        if !appPassword.isEmpty && !confirmAppPassword.isEmpty && !appPasswordsMatch {
                            Label("Passwords do not match", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }

                        if let appPasswordError {
                            Label(appPasswordError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("App Lock", systemImage: "lock")
                }
            } else if appLockEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("App password is ready.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("L0ck will ask for this password each time you open the app.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("App Lock", systemImage: "lock")
                }
            } else {
                GroupBox {
                    Text("App password is currently off. You can turn it on later in Settings.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("App Lock", systemImage: "lock.open")
                }
            }
        }
    }

    private var backupContent: some View {
        stepPanel(symbol: SetupStep.backup.systemImage) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    bulletRow("Export saves an encrypted .l0ckkeys recovery file.", systemImage: "square.and.arrow.down")
                    bulletRow("You need both the backup file and its password to restore access.", systemImage: "lock")
                    bulletRow("You can skip this now and open Key Backup later.", systemImage: "clock")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Recovery Backup", systemImage: "externaldrive.badge.timemachine")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if currentStep != .welcome {
                Button("Back") {
                    if let previous = SetupStep(rawValue: currentStep.rawValue - 1) {
                        currentStep = previous
                    }
                }
            }

            Spacer()

            switch currentStep {
            case .welcome:
                Button("Continue") {
                    currentStep = .keys
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .keys:
                Button("Continue") {
                    currentStep = .appLock
                }
                .buttonStyle(.borderedProminent)
                .disabled(!keysGenerated)
                .keyboardShortcut(.defaultAction)
            case .appLock:
                Button("Continue") {
                    continueFromAppLockStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(needsAppPasswordSetup && !isAppPasswordValid)
                .keyboardShortcut(.defaultAction)
            case .backup:
                Button("Back Up Keys…") {
                    showBackupSheet = true
                }

                Button("Finish") {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: - Actions

    @MainActor
    private func resetKeyGeneration() {
        keysGenerated = false
        hasStartedGeneration = false
        errorMessage = nil
    }

    @MainActor
    private func generateKeysIfNeeded() async {
        guard !hasStartedGeneration else { return }
        hasStartedGeneration = true

        do {
            _ = try KeychainService.shared.getMasterSecret()
            _ = try KeychainService.shared.getPrivateKey()
            try? await Task.sleep(for: .milliseconds(500))
            keysGenerated = true
            errorMessage = nil
            onSetupStateChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func passwordField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        Group {
            if showAppPassword {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
    }

    private func continueFromAppLockStep() {
        guard needsAppPasswordSetup else {
            currentStep = .backup
            return
        }

        guard isAppPasswordValid else { return }

        do {
            try KeychainService.shared.saveAppLockPassword(appPassword)
            appLockEnabled = true
            appSession.unlockForCurrentSession()
            appPasswordError = nil
            onSetupStateChanged()
            currentStep = .backup
        } catch {
            appPasswordError = error.localizedDescription
        }
    }

    private func finishSetup() {
        hasCompletedOnboarding = true
        appSession.unlockForCurrentSession()
        onFinished()
    }
}
