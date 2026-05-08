import Foundation
import Observation

@Observable
final class AppSessionState {
    var isUnlocked = false
    private var hasConfiguredLaunch = false

    func configureForLaunch(appLockEnabled: Bool, hasAppLockPassword: Bool) {
        guard !hasConfiguredLaunch else { return }
        hasConfiguredLaunch = true
        isUnlocked = !appLockEnabled || !hasAppLockPassword
    }

    func unlockForCurrentSession() {
        isUnlocked = true
    }

    func lockForCurrentSession() {
        isUnlocked = false
    }
}
