import AppKit
import SwiftUI

// MARK: - L0ck App Entry Point

@main
struct L0ckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appSession = AppSessionState()
    @State private var fileStore = FileStore()
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.system.rawValue

    init() {
        UserDefaults.standard.register(defaults: [
            "previewAutoClearSeconds": 10,
            "appLockEnabled": true,
            "lockWhenAppInactive": false
        ])
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appSession)
                .environment(fileStore)
                .environment(\.locale, appLanguage.locale)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1060, height: 700)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appSession)
                .environment(\.locale, appLanguage.locale)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        FileService.shared.cleanupTemporaryPreviewFiles()
    }
}

// MARK: - Content View (Root Router)

/// Root view that routes between the setup wizard (first launch)
/// and the main application view.
struct ContentView: View {
    @Environment(AppSessionState.self) private var appSession
    @Environment(FileStore.self) private var fileStore
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("lockWhenAppInactive") private var lockWhenAppInactive = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var bootstrapRefreshToken = 0

    init() {
        UserDefaults.standard.register(defaults: [
            "hasCompletedOnboarding": KeychainService.shared.hasKeys,
            "appLockEnabled": true,
            "lockWhenAppInactive": false
        ])
    }

    private var requiresAppLockSetup: Bool {
        _ = bootstrapRefreshToken
        return appLockEnabled && !KeychainService.shared.hasAppLockPassword
    }

    private var requiresBootstrapSetup: Bool {
        _ = bootstrapRefreshToken
        return !KeychainService.shared.hasKeys || requiresAppLockSetup
    }

    private var shouldShowOnboarding: Bool {
        !requiresBootstrapSetup && !hasCompletedOnboarding
    }

    private var shouldShowUnlock: Bool {
        appLockEnabled &&
        KeychainService.shared.hasAppLockPassword &&
        !appSession.isUnlocked &&
        !requiresBootstrapSetup
    }

    var body: some View {
        Group {
            if requiresBootstrapSetup || shouldShowOnboarding {
                SetupView(
                    onSetupStateChanged: {
                        bootstrapRefreshToken += 1
                    },
                    onFinished: {
                        hasCompletedOnboarding = true
                        bootstrapRefreshToken += 1
                    }
                )
            } else if shouldShowUnlock {
                AppUnlockView()
            } else {
                MainView {
                    hasCompletedOnboarding = false
                }
            }
        }
        .task {
            appSession.configureForLaunch(
                appLockEnabled: appLockEnabled,
                hasAppLockPassword: KeychainService.shared.hasAppLockPassword
            )
        }
        .onChange(of: appLockEnabled) {
            bootstrapRefreshToken += 1
            if !appLockEnabled {
                appSession.unlockForCurrentSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            guard
                appLockEnabled,
                lockWhenAppInactive,
                KeychainService.shared.hasAppLockPassword
            else {
                return
            }

            appSession.lockForCurrentSession()
        }
        .animation(.easeInOut(duration: 0.3), value: requiresBootstrapSetup || shouldShowOnboarding)
    }
}
