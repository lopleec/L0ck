import Foundation

// MARK: - Admin Auth Errors

enum AdminAuthError: Error, LocalizedError {
    case authorizationDenied
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return L10n.string("Administrator authorization was denied")
        case .authorizationFailed(let msg):
            return L10n.format("Authorization failed: %@", msg)
        }
    }
}

// MARK: - Admin Auth Service

/// Handles macOS administrator authentication for privileged operations.
///
/// Uses the native macOS administrator password dialog to execute privileged
/// shell commands. Required for:
/// - Creating encrypted files on disk
/// - Exporting decrypted files to disk
/// - Deleting encrypted files
///
/// NOT required for in-app preview (which only uses user password + Keychain keys).
final class AdminAuthService {

    static let shared = AdminAuthService()

    private init() {}

    /// Request administrator authentication via macOS system dialog.
    ///
    /// Shows the native macOS admin password prompt. The user must enter
    /// a valid admin username/password to proceed.
    ///
    /// - Parameter prompt: Custom prompt text shown in the dialog
    /// - Returns: `true` if authentication succeeded
    /// - Throws: ``AdminAuthError`` if denied or failed
    func requestAdminAuth(
        prompt: String = L10n.string("L0ck needs administrator permission to perform this operation.")
    ) async throws -> Bool {
        try await runPrivilegedShellCommand("/usr/bin/true", prompt: prompt)
        return true
    }

    /// Execute a privileged shell command after the user approves the system dialog.
    func runPrivilegedShellCommand(
        _ command: String,
        prompt: String
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = [
                    "-e",
                    """
                    do shell script "\(Self.appleScriptEscaped(command))" with prompt "\(Self.appleScriptEscaped(prompt))" with administrator privileges
                    """
                ]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                        return
                    }

                    let stderr = String(
                        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if stderr.contains("User canceled") || stderr.contains("(-128)") {
                        continuation.resume(throwing: AdminAuthError.authorizationDenied)
                    } else {
                        continuation.resume(
                            throwing: AdminAuthError.authorizationFailed(
                                stderr.isEmpty ? "Unknown privileged command error" : stderr
                            )
                        )
                    }
                } catch {
                    continuation.resume(
                        throwing: AdminAuthError.authorizationFailed(error.localizedDescription)
                    )
                }
            }
        }
    }

    private static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
