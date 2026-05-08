import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppSessionState.self) private var appSession
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("lockWhenAppInactive") private var lockWhenAppInactive = false
    @AppStorage("defaultStorageMode") private var defaultStorageModeRawValue = StorageMode.appFolder.rawValue
    @AppStorage("deleteOriginalByDefault") private var deleteOriginalByDefault = false
    @AppStorage("previewAutoClearSeconds") private var previewAutoClearSeconds = 10
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var appLockSheetMode: AppLockPasswordSheet.Mode?
    @State private var showDisableAppLockConfirm = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var previewAutoClearSecondsBinding: Binding<Int> {
        Binding(
            get: { max(0, previewAutoClearSeconds) },
            set: { previewAutoClearSeconds = max(0, $0) }
        )
    }

    private var appLockStatusText: String {
        appLockEnabled ? L10n.string("On") : L10n.string("Off")
    }

    private var appLockSummaryText: String {
        appLockEnabled
            ? L10n.string("L0ck asks for this password every time the app opens.")
            : L10n.string("L0ck opens directly until you turn the app password back on.")
    }

    private var appLockInactiveText: String {
        appLockEnabled
            ? L10n.string("When enabled, switching away from L0ck will require the app password again.")
            : L10n.string("Turn on the app password to use automatic locking.")
    }

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }

                Text("Language changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App Lock") {
                LabeledContent("Launch Password", value: appLockStatusText)

                if appLockEnabled {
                    HStack {
                        Button("Change App Password…") {
                            appLockSheetMode = .change
                        }

                        Button("Turn Off App Password", role: .destructive) {
                            showDisableAppLockConfirm = true
                        }
                    }

                    Toggle("Lock when L0ck goes inactive", isOn: $lockWhenAppInactive)
                } else {
                    Button("Turn On App Password…") {
                        appLockSheetMode = .create
                    }
                }

                Text(appLockSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(appLockInactiveText)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Import Defaults") {
                Picker("Default Storage", selection: $defaultStorageModeRawValue) {
                    Text(StorageMode.appFolder.displayName).tag(StorageMode.appFolder.rawValue)
                    Text(StorageMode.originalDirectory.displayName).tag(StorageMode.originalDirectory.rawValue)
                }
                .pickerStyle(.segmented)

                Text("Store new encrypted files in the location you prefer by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("App Folder provides the strongest system protection for delete and move operations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Delete original file after encryption", isOn: $deleteOriginalByDefault)
            }

            Section("Preview") {
                LabeledContent("Auto-clear Preview") {
                    HStack(spacing: 8) {
                        TextField("Seconds", value: previewAutoClearSecondsBinding, format: .number)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)

                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Set 0 to keep previews until you clear them manually. L0ck still removes all preview copies when it quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Temporary system preview copies are hidden and locked while they exist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                Button("Show Onboarding Again") {
                    hasCompletedOnboarding = false
                }

                Text("Review setup and key backup guidance again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 500)
        .sheet(item: $appLockSheetMode) { mode in
            AppLockPasswordSheet(mode: mode) {
                appLockEnabled = true
                appSession.unlockForCurrentSession()
            }
        }
        .alert("Turn Off App Password", isPresented: $showDisableAppLockConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Turn Off", role: .destructive) {
                disableAppLock()
            }
        } message: {
            Text("L0ck will open without asking for the app password next time.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? L10n.string("Unknown error"))
        }
    }

    private func disableAppLock() {
        do {
            try KeychainService.shared.clearAppLockPassword()
            appLockEnabled = false
            lockWhenAppInactive = false
            appSession.unlockForCurrentSession()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
