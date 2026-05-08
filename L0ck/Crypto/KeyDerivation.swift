import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Key Derivation Errors

enum KeyDerivationError: Error, LocalizedError {
    case pbkdf2Failed
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .pbkdf2Failed:
            return L10n.string("PBKDF2 key derivation failed")
        case .invalidInput:
            return L10n.string("Invalid input for key derivation")
        }
    }
}

enum PasswordPolicy {
    static let appLockMinimumLength = 4
    static let fileEncryptionMinimumLength = 8
    static let universalExportMinimumLength = 12

    static func strengthScore(for password: String) -> Int {
        var score = 0

        if password.count >= fileEncryptionMinimumLength { score += 1 }
        if password.count >= universalExportMinimumLength { score += 1 }
        if containsUppercase(password) && containsLowercase(password) { score += 1 }
        if containsDigit(password) { score += 1 }
        if containsSymbol(password) { score += 1 }

        return score
    }

    static func meetsUniversalExportRequirement(_ password: String) -> Bool {
        password.count >= universalExportMinimumLength &&
        containsUppercase(password) &&
        containsLowercase(password) &&
        containsDigit(password) &&
        containsSymbol(password)
    }

    static func containsUppercase(_ password: String) -> Bool {
        password.rangeOfCharacter(from: .uppercaseLetters) != nil
    }

    static func containsLowercase(_ password: String) -> Bool {
        password.rangeOfCharacter(from: .lowercaseLetters) != nil
    }

    static func containsDigit(_ password: String) -> Bool {
        password.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func containsSymbol(_ password: String) -> Bool {
        password.rangeOfCharacter(from: .punctuationCharacters) != nil ||
        password.rangeOfCharacter(from: .symbols) != nil
    }
}

// MARK: - Key Derivation

/// Handles all key derivation operations for L0ck's multi-factor encryption.
///
/// Three-factor key combination:
/// - KEK₁: Derived from user password via PBKDF2-SHA512 (stored per-file cost)
/// - KEK₂: Derived from App Master Secret via HKDF-SHA256
/// - Combined KEK: HKDF(KEK₁ ∥ KEK₂)
struct KeyDerivation {

    /// Default PBKDF2 iteration count for new device-bound files.
    /// The count is stored per file, so older files remain decryptable.
    static let defaultPBKDF2Iterations: UInt32 = 350_000

    /// Key length in bytes (256 bits)
    static let keyLength = 32

    // MARK: - KEK₁ from Password

    /// Derive KEK₁ from user password using PBKDF2-HMAC-SHA512.
    ///
    /// - Parameters:
    ///   - password: User-provided password
    ///   - salt: Random 32-byte salt (unique per file)
    ///   - iterations: PBKDF2 iteration count for the target file payload
    /// - Returns: 256-bit symmetric key
    static func deriveFromPassword(
        _ password: String,
        salt: Data,
        iterations: UInt32 = defaultPBKDF2Iterations
    ) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            throw KeyDerivationError.invalidInput
        }

        var derivedKey = Data(count: keyLength)

        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    passwordData.count,
                    saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    iterations,
                    derivedBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    keyLength
                )
            }
        }

        guard status == kCCSuccess else {
            throw KeyDerivationError.pbkdf2Failed
        }

        return SymmetricKey(data: derivedKey)
    }

    // MARK: - KEK₂ from Master Secret

    /// Derive KEK₂ from App Master Secret using HKDF-SHA256.
    ///
    /// The master secret is stored in the macOS Keychain and acts as a
    /// "something you have" factor — without it, decryption is impossible.
    static func deriveFromMasterSecret(_ masterSecret: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: masterSecret)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: "L0ck.KEK2.v2".data(using: .utf8)!,
            info: "MasterSecretDerivation".data(using: .utf8)!,
            outputByteCount: keyLength
        )
    }

    // MARK: - Combined KEK

    /// Combine KEK₁ and KEK₂ into a single Combined KEK using HKDF.
    ///
    /// Both factors must be present for this to produce the correct key.
    /// An attacker with only one factor cannot derive the Combined KEK.
    static func combinedKEK(kek1: SymmetricKey, kek2: SymmetricKey) -> SymmetricKey {
        var combined = Data()
        kek1.withUnsafeBytes { combined.append(contentsOf: $0) }
        kek2.withUnsafeBytes { combined.append(contentsOf: $0) }

        let inputKey = SymmetricKey(data: combined)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: "L0ck.CombinedKEK.v2".data(using: .utf8)!,
            info: "KEK1+KEK2".data(using: .utf8)!,
            outputByteCount: keyLength
        )
    }

    // MARK: - Random Generation

    /// Generate a cryptographically secure random salt.
    static func generateSalt(length: Int = 32) -> Data {
        var salt = Data(count: length)
        salt.withUnsafeMutableBytes { bytes in
            _ = SecRandomCopyBytes(kSecRandomDefault, length, bytes.baseAddress!)
        }
        return salt
    }

    /// Generate a random 256-bit Data Encryption Key (DEK).
    static func generateDEK() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
}
