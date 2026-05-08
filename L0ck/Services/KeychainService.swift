import Foundation
import Security
import CryptoKit

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed
    case deleteFailed(OSStatus)
    case keyGenerationFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return L10n.format("Keychain save failed (OSStatus: %@)", String(status))
        case .loadFailed:
            return L10n.string("Keychain item not found")
        case .deleteFailed(let status):
            return L10n.format("Keychain delete failed (OSStatus: %@)", String(status))
        case .keyGenerationFailed:
            return L10n.string("Key generation failed")
        }
    }
}

// MARK: - Keychain Service

/// Manages L0ck's cryptographic keys in the macOS Keychain.
///
/// Stores two secret items:
/// - **Master Secret** (256-bit random) — used to derive KEK₂
/// - **Curve25519 Private Key** (32 bytes) — used for ECIES Layer 3
///
/// Both are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// protection, meaning they're only available when the Mac is unlocked
/// and are not synced to iCloud or other devices.
///
/// Provides key backup/restore functionality for device migration.
final class KeychainService {

    static let shared = KeychainService()

    private let masterSecretKey = "com.l0ck.master-secret"
    private let privateKeyKey = "com.l0ck.curve25519-private-key"
    private let appLockPasswordKey = "com.l0ck.app-lock-password"
    private let serviceName = "L0ck"

    private init() {}

    // MARK: - Master Secret

    /// Get or create the App Master Secret.
    ///
    /// On first call, generates a new 256-bit random secret and stores it
    /// in the Keychain. Subsequent calls retrieve the existing secret.
    func getMasterSecret() throws -> Data {
        if let existing = try? loadFromKeychain(key: masterSecretKey) {
            return existing
        }
        // Generate new 256-bit master secret
        let secret = KeyDerivation.generateSalt(length: 32)
        try saveToKeychain(key: masterSecretKey, data: secret)
        return secret
    }

    // MARK: - Curve25519 Key Pair

    /// Get or create the Curve25519 private key.
    ///
    /// On first call, generates a new key pair and stores the private key
    /// in the Keychain. Subsequent calls retrieve the existing key.
    func getPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try? loadFromKeychain(key: privateKeyKey) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existing)
        }
        // Generate new key pair
        let privateKey = ECIESEngine.generateKeyPair()
        try saveToKeychain(key: privateKeyKey, data: privateKey.rawRepresentation)
        return privateKey
    }

    /// Get the Curve25519 public key (derived from private key).
    func getPublicKey() throws -> Curve25519.KeyAgreement.PublicKey {
        let privateKey = try getPrivateKey()
        return privateKey.publicKey
    }

    // MARK: - Key Status

    /// Check if both master secret and private key exist in Keychain.
    var hasKeys: Bool {
        let hasMaster = (try? loadFromKeychain(key: masterSecretKey)) != nil
        let hasPrivate = (try? loadFromKeychain(key: privateKeyKey)) != nil
        return hasMaster && hasPrivate
    }

    var hasAppLockPassword: Bool {
        (try? loadFromKeychain(key: appLockPasswordKey)) != nil
    }

    // MARK: - Key Backup & Restore

    /// Backup data structure for key export/import.
    struct KeyBackup: Codable {
        let masterSecret: Data
        let privateKey: Data
        let createdAt: Date
        let version: Int

        init(masterSecret: Data, privateKey: Data, createdAt: Date = Date(), version: Int = 2) {
            self.masterSecret = masterSecret
            self.privateKey = privateKey
            self.createdAt = createdAt
            self.version = version
        }
    }

    struct AppLockCredential: Codable {
        let salt: Data
        let verifier: Data
        let iterations: UInt32
        let updatedAt: Date
    }

    /// Export encryption keys as an encrypted backup file.
    ///
    /// The backup is encrypted with AES-256-GCM using a key derived from
    /// the backup password via PBKDF2. Format: salt(32) + AES-GCM sealed box.
    ///
    /// - Parameter backupPassword: Password to protect the backup
    /// - Returns: Encrypted backup data
    func exportKeys(backupPassword: String) throws -> Data {
        let masterSecret = try getMasterSecret()
        let privateKey = try getPrivateKey()

        let backup = KeyBackup(
            masterSecret: masterSecret,
            privateKey: privateKey.rawRepresentation
        )

        let jsonData = try JSONEncoder().encode(backup)

        // Encrypt the backup with the backup password
        let salt = KeyDerivation.generateSalt()
        let key = try KeyDerivation.deriveFromPassword(backupPassword, salt: salt)
        let sealed = try AES.GCM.seal(jsonData, using: key)

        // Format: salt(32) + sealed.combined
        var result = Data()
        result.append(salt)
        result.append(sealed.combined!)

        return result
    }

    /// Import encryption keys from an encrypted backup file.
    ///
    /// Replaces existing keys in the Keychain with the imported ones.
    ///
    /// - Parameters:
    ///   - backupData: Encrypted backup data (from ``exportKeys(backupPassword:)``)
    ///   - backupPassword: Password used when exporting
    func importKeys(backupData: Data, backupPassword: String) throws {
        guard backupData.count > 32 else {
            throw KeychainError.loadFailed
        }

        let salt = backupData.prefix(32)
        let sealedData = backupData.dropFirst(32)

        let key = try KeyDerivation.deriveFromPassword(backupPassword, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        let jsonData = try AES.GCM.open(sealedBox, using: key)

        let backup = try JSONDecoder().decode(KeyBackup.self, from: jsonData)

        // Validate the private key data is a valid Curve25519 key
        _ = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: backup.privateKey)

        // Replace existing keys
        try? deleteFromKeychain(key: masterSecretKey)
        try? deleteFromKeychain(key: privateKeyKey)
        try saveToKeychain(key: masterSecretKey, data: backup.masterSecret)
        try saveToKeychain(key: privateKeyKey, data: backup.privateKey)
    }

    func saveAppLockPassword(_ password: String) throws {
        let salt = KeyDerivation.generateSalt()
        let derivedKey = try KeyDerivation.deriveFromPassword(password, salt: salt)
        let credential = AppLockCredential(
            salt: salt,
            verifier: data(from: derivedKey),
            iterations: KeyDerivation.defaultPBKDF2Iterations,
            updatedAt: Date()
        )

        let credentialData = try JSONEncoder().encode(credential)
        try saveToKeychain(key: appLockPasswordKey, data: credentialData)
    }

    func verifyAppLockPassword(_ password: String) throws -> Bool {
        let credentialData = try loadFromKeychain(key: appLockPasswordKey)
        let credential = try JSONDecoder().decode(AppLockCredential.self, from: credentialData)
        let derivedKey = try KeyDerivation.deriveFromPassword(
            password,
            salt: credential.salt,
            iterations: credential.iterations
        )

        return data(from: derivedKey) == credential.verifier
    }

    func clearAppLockPassword() throws {
        try deleteFromKeychain(key: appLockPasswordKey)
    }

    // MARK: - Raw Keychain Operations

    private func data(from key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private func saveToKeychain(key: String, data: Data) throws {
        // Delete existing item first to avoid duplicates
        try? deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func loadFromKeychain(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed
        }

        return data
    }

    private func deleteFromKeychain(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
