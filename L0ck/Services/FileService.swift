import Foundation
import CryptoKit

// MARK: - File Service Errors

enum FileServiceError: Error, LocalizedError {
    case fileNotFound
    case writeError(String)
    case readError(String)
    case permissionError(String)
    case directoryError(String)
    case validationError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return L10n.string("File not found")
        case .writeError(let msg):
            return L10n.format("Write error: %@", msg)
        case .readError(let msg):
            return L10n.format("Read error: %@", msg)
        case .permissionError(let msg):
            return L10n.format("Permission error: %@", msg)
        case .directoryError(let msg):
            return L10n.format("Directory error: %@", msg)
        case .validationError(let msg):
            return msg
        }
    }
}

// MARK: - File Service

/// Handles all file I/O operations for L0ck.
///
/// Responsibilities:
/// - Import files → encrypt → write to disk
/// - Decrypt files → return in memory or export to disk
/// - File permission management (immutable flag, read-only)
/// - App folder management (~/Documents/L0ck/)
/// - Random filename generation
final class FileService {

    static let shared = FileService()

    private let fm = FileManager.default

    /// The app's dedicated folder for encrypted files: ~/Documents/L0ck/
    var appFolderURL: URL {
        let docs = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("L0ck", isDirectory: true)
        try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    var previewFolderURL: URL {
        fm.temporaryDirectory.appendingPathComponent("L0ckPreview", isDirectory: true)
    }

    private init() {
        // Ensure app folder exists on init
        _ = appFolderURL
        cleanupTemporaryPreviewFiles()
    }

    // MARK: - Import & Encrypt

    /// Import a file, encrypt it with three-layer encryption, and save to disk.
    ///
    /// - Parameters:
    ///   - sourceURL: URL of the file to import
    ///   - password: User-chosen encryption password
    ///   - storageMode: Where to store the encrypted file
    ///   - deleteOriginal: Whether to delete the original file after encryption
    /// - Returns: An ``EncryptedFileRecord`` representing the new encrypted file
    func importAndEncrypt(
        sourceURL: URL,
        password: String,
        storageMode: StorageMode,
        deleteOriginal: Bool = false
    ) async throws -> EncryptedFileRecord {
        // Verify source file exists
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw FileServiceError.fileNotFound
        }

        // Read source file data
        let fileData: Data
        do {
            fileData = try Data(contentsOf: sourceURL)
        } catch {
            throw FileServiceError.readError(error.localizedDescription)
        }

        let fileName = sourceURL.lastPathComponent

        // Get crypto keys from Keychain
        let masterSecret = try KeychainService.shared.getMasterSecret()
        let publicKey = try KeychainService.shared.getPublicKey()

        // Three-layer encryption
        let payload = try CryptoEngine.encrypt(
            fileData: fileData,
            fileName: fileName,
            password: password,
            masterSecret: masterSecret,
            publicKey: publicKey
        )

        // Serialize to .l0ck binary format
        let l0ckData = L0ckFileFormat.serialize(payload)

        // Determine destination path
        let destinationURL: URL
        switch storageMode {
        case .originalDirectory:
            let dir = sourceURL.deletingLastPathComponent()
            let randomName = generateRandomFileName()
            destinationURL = dir.appendingPathComponent("\(randomName).l0ck")
        case .appFolder:
            let randomName = generateRandomFileName()
            destinationURL = appFolderURL.appendingPathComponent("\(randomName).l0ck")
        }

        try await writeProtectedEncryptedFile(
            l0ckData,
            to: destinationURL,
            storageMode: storageMode
        )

        // Delete original if requested
        if deleteOriginal {
            try? fm.removeItem(at: sourceURL)
        }

        // Create and return record
        return EncryptedFileRecord(
            originalFileName: fileName,
            encryptedFilePath: destinationURL.path,
            storageMode: storageMode,
            fileSize: Int64(l0ckData.count)
        )
    }

    // MARK: - Decrypt In Memory

    /// Decrypt a file entirely in memory without writing to disk.
    ///
    /// Used for in-app preview — only requires user password
    /// (master secret and private key are read from Keychain automatically).
    ///
    /// - Parameters:
    ///   - record: The encrypted file record
    ///   - password: User-provided decryption password
    /// - Returns: Tuple of (original filename, decrypted file data)
    func decryptInMemory(
        record: EncryptedFileRecord,
        password: String
    ) throws -> (fileName: String, fileData: Data) {
        guard fm.fileExists(atPath: record.encryptedFilePath) else {
            throw FileServiceError.fileNotFound
        }

        let l0ckData = try Data(contentsOf: record.encryptedFileURL)
        let payload = try L0ckFileFormat.deserialize(l0ckData)

        let masterSecret = try KeychainService.shared.getMasterSecret()
        let privateKey = try KeychainService.shared.getPrivateKey()

        return try CryptoEngine.decrypt(
            payload: payload,
            password: password,
            masterSecret: masterSecret,
            privateKey: privateKey
        )
    }

    // MARK: - Decrypt & Export

    /// Decrypt and export the file to a user-chosen location on disk.
    ///
    /// - Parameters:
    ///   - record: The encrypted file record
    ///   - password: User-provided decryption password
    ///   - destinationURL: Where to save the decrypted file
    func decryptAndExport(
        record: EncryptedFileRecord,
        password: String,
        destinationURL: URL
    ) throws {
        let (_, fileData) = try decryptInMemory(record: record, password: password)
        do {
            try fileData.write(to: destinationURL, options: .atomic)
        } catch {
            throw FileServiceError.writeError(error.localizedDescription)
        }
    }

    func makeUniversalEncryptedFileData(
        record: EncryptedFileRecord,
        currentPassword: String,
        exportPassword: String
    ) throws -> Data {
        guard PasswordPolicy.meetsUniversalExportRequirement(exportPassword) else {
            throw FileServiceError.validationError(
                L10n.string("Use at least 12 characters with uppercase, lowercase, a number, and a symbol.")
            )
        }

        let result = try decryptInMemory(record: record, password: currentPassword)
        let payload = try CryptoEngine.encryptUniversal(
            fileData: result.fileData,
            fileName: result.fileName,
            password: exportPassword
        )
        return L0ckFileFormat.serializeUniversal(payload)
    }

    // MARK: - File Protection

    /// Delete an encrypted file from disk.
    ///
    func deleteEncryptedFile(_ record: EncryptedFileRecord) async throws {
        try await deleteL0ckFile(at: record.encryptedFileURL)
    }

    /// Delete a `.l0ck` file from any location on disk.
    func deleteL0ckFile(at url: URL) async throws {
        guard fm.fileExists(atPath: url.path) else {
            throw FileServiceError.fileNotFound
        }

        if isInProtectedAppFolder(url) {
            try await deleteProtectedAppFolderFile(at: url)
        } else {
            try await deleteProtectedFile(
                at: url,
                prompt: L10n.string("L0ck needs administrator permission to delete the encrypted file.")
            )
        }
    }

    /// Reapply root-level immutable protection to an existing encrypted file.
    func reapplyProtection(to record: EncryptedFileRecord) async throws {
        guard fm.fileExists(atPath: record.encryptedFilePath) else {
            throw FileServiceError.fileNotFound
        }

        switch record.storageMode {
        case .originalDirectory:
            try await applyRootOnlyProtection(
                to: record.encryptedFileURL,
                prompt: L10n.string("L0ck needs administrator permission to reapply file protection.")
            )
        case .appFolder:
            try await reapplyAppFolderProtection(to: record.encryptedFileURL)
        }
    }

    // MARK: - Utilities

    /// Generate a random filename (12-char hex string).
    private func generateRandomFileName() -> String {
        let bytes = KeyDerivation.generateSalt(length: 6)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func writeTemporaryPreviewFile(
        fileName: String,
        data: Data
    ) throws -> URL {
        try preparePreviewFolder()

        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let fileURL = previewFolderURL.appendingPathComponent("\(UUID().uuidString)-\(safeName)")

        do {
            try data.write(to: fileURL, options: .atomic)
            try hardenTemporaryPreviewFile(at: fileURL)
            return fileURL
        } catch {
            removeTemporaryPreviewFile(at: fileURL)

            if let fileServiceError = error as? FileServiceError {
                throw fileServiceError
            }

            throw FileServiceError.writeError(error.localizedDescription)
        }
    }

    func removeTemporaryPreviewFile(at url: URL?) {
        guard let url else { return }
        unprotectTemporaryPreviewItem(at: url)
        try? fm.removeItem(at: url)
    }

    func cleanupTemporaryPreviewFiles() {
        guard fm.fileExists(atPath: previewFolderURL.path) else { return }

        if let enumerator = fm.enumerator(at: previewFolderURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            let items = enumerator
                .compactMap { $0 as? URL }
                .sorted { $0.path.count > $1.path.count }

            for itemURL in items {
                unprotectTemporaryPreviewItem(at: itemURL)
            }
        }

        unprotectTemporaryPreviewItem(at: previewFolderURL)
        try? fm.removeItem(at: previewFolderURL)
    }

    private func preparePreviewFolder() throws {
        do {
            try fm.createDirectory(at: previewFolderURL, withIntermediateDirectories: true)
            try setPOSIXPermissions(0o700, for: previewFolderURL)
        } catch {
            throw FileServiceError.directoryError(error.localizedDescription)
        }
    }

    private func hardenTemporaryPreviewFile(at url: URL) throws {
        do {
            try setPOSIXPermissions(0o400, for: url)
            try runLocalTool("/usr/bin/chflags", arguments: ["hidden,uchg", url.path])
        } catch {
            throw FileServiceError.permissionError(error.localizedDescription)
        }
    }

    private func unprotectTemporaryPreviewItem(at url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        try? runLocalTool("/usr/bin/chflags", arguments: ["nouchg,nohidden", url.path], allowFailure: true)
        try? setPOSIXPermissions(isDirectory ? 0o700 : 0o600, for: url)
    }

    private func setPOSIXPermissions(_ permissions: Int, for url: URL) throws {
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func runLocalTool(
        _ toolPath: String,
        arguments: [String],
        allowFailure: Bool = false
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard allowFailure || process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FileServiceError.permissionError(message?.isEmpty == false ? message! : "Command failed")
        }
    }

    private func writeProtectedEncryptedFile(
        _ data: Data,
        to destinationURL: URL,
        storageMode: StorageMode
    ) async throws {
        switch storageMode {
        case .originalDirectory:
            do {
                try data.write(to: destinationURL, options: .atomic)
            } catch {
                throw FileServiceError.writeError(error.localizedDescription)
            }

            do {
                try await applyRootOnlyProtection(
                    to: destinationURL,
                    prompt: L10n.string("L0ck needs administrator permission to create an encrypted file.")
                )
            } catch {
                try? fm.removeItem(at: destinationURL)
                throw error
            }

        case .appFolder:
            try await importIntoProtectedAppFolder(data, destinationURL: destinationURL)
        }
    }

    private func importIntoProtectedAppFolder(
        _ data: Data,
        destinationURL: URL
    ) async throws {
        do {
            try fm.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        } catch {
            throw FileServiceError.directoryError(error.localizedDescription)
        }

        let tempURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("l0ck")

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            throw FileServiceError.writeError(error.localizedDescription)
        }

        defer {
            try? fm.removeItem(at: tempURL)
        }

        let script = """
        set -e
        /bin/mkdir -p \(shellQuoted(appFolderURL.path))
        /usr/bin/chflags noschg,nouchg \(shellQuoted(appFolderURL.path)) 2>/dev/null || true
        cleanup() {
          status=$?
          if [ "$status" -ne 0 ]; then
            /bin/rm -f \(shellQuoted(destinationURL.path)) 2>/dev/null || true
          fi
          /usr/bin/chflags schg \(shellQuoted(appFolderURL.path)) 2>/dev/null || true
          /bin/rm -f \(shellQuoted(tempURL.path)) 2>/dev/null || true
          exit "$status"
        }
        trap cleanup EXIT
        /usr/bin/install -m 444 \(shellQuoted(tempURL.path)) \(shellQuoted(destinationURL.path))
        /usr/bin/chflags schg \(shellQuoted(destinationURL.path))
        """

        try await AdminAuthService.shared.runPrivilegedShellCommand(
            script,
            prompt: L10n.string("L0ck needs administrator permission to create an encrypted file.")
        )
    }

    private func applyRootOnlyProtection(
        to url: URL,
        prompt: String
    ) async throws {
        let script = """
        set -e
        /bin/chmod 444 \(shellQuoted(url.path))
        /usr/bin/chflags schg \(shellQuoted(url.path))
        """

        try await AdminAuthService.shared.runPrivilegedShellCommand(script, prompt: prompt)
    }

    private func deleteProtectedFile(
        at url: URL,
        prompt: String
    ) async throws {
        let script = """
        set -e
        /bin/test -e \(shellQuoted(url.path))
        /usr/bin/chflags noschg,nouchg \(shellQuoted(url.path)) 2>/dev/null || true
        /bin/rm -f \(shellQuoted(url.path))
        """

        try await AdminAuthService.shared.runPrivilegedShellCommand(script, prompt: prompt)
    }

    private func deleteProtectedAppFolderFile(at url: URL) async throws {
        let script = """
        set -e
        /bin/test -e \(shellQuoted(url.path))
        /usr/bin/chflags noschg,nouchg \(shellQuoted(appFolderURL.path)) 2>/dev/null || true
        cleanup() {
          status=$?
          /usr/bin/chflags schg \(shellQuoted(appFolderURL.path)) 2>/dev/null || true
          exit "$status"
        }
        trap cleanup EXIT
        /usr/bin/chflags noschg,nouchg \(shellQuoted(url.path)) 2>/dev/null || true
        /bin/rm -f \(shellQuoted(url.path))
        """

        try await AdminAuthService.shared.runPrivilegedShellCommand(
            script,
            prompt: L10n.string("L0ck needs administrator permission to delete the encrypted file.")
        )
    }

    private func reapplyAppFolderProtection(to url: URL) async throws {
        let script = """
        set -e
        /bin/test -e \(shellQuoted(url.path))
        /usr/bin/chflags noschg,nouchg \(shellQuoted(appFolderURL.path)) 2>/dev/null || true
        cleanup() {
          status=$?
          /usr/bin/chflags schg \(shellQuoted(appFolderURL.path)) 2>/dev/null || true
          exit "$status"
        }
        trap cleanup EXIT
        /usr/bin/chflags noschg,nouchg \(shellQuoted(url.path)) 2>/dev/null || true
        /bin/chmod 444 \(shellQuoted(url.path))
        /usr/bin/chflags schg \(shellQuoted(url.path))
        """

        try await AdminAuthService.shared.runPrivilegedShellCommand(
            script,
            prompt: L10n.string("L0ck needs administrator permission to reapply file protection.")
        )
    }

    private func isInProtectedAppFolder(_ url: URL) -> Bool {
        let normalizedFileURL = url.standardizedFileURL
        let normalizedAppFolderURL = appFolderURL.standardizedFileURL
        let filePath = normalizedFileURL.path
        let appFolderPath = normalizedAppFolderURL.path
        return filePath == appFolderPath || filePath.hasPrefix(appFolderPath + "/")
    }

    private func shellQuoted(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
