import Foundation
import CryptoKit

// MARK: - Crypto Errors

enum CryptoError: Error, LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidFileFormat
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let msg):
            return L10n.format("Encryption failed: %@", msg)
        case .decryptionFailed(let msg):
            return L10n.format("Decryption failed: %@", msg)
        case .invalidFileFormat:
            return L10n.string("Invalid .l0ck file format")
        case .authenticationFailed:
            return L10n.string("Authentication failed — incorrect password or corrupted keys")
        }
    }
}

// MARK: - Encrypted Payload

/// Contains all components produced by the three-layer encryption pipeline.
///
/// This is an intermediate representation used between ``CryptoEngine`` and
/// ``L0ckFileFormat`` for serialization.
struct EncryptedPayload {
    let salt: Data                      // 32 bytes — PBKDF2 salt
    let iterations: UInt32              // PBKDF2 iteration count
    let aesNonce: AES.GCM.Nonce         // 12 bytes — Layer 1 nonce
    let eciesEnvelope: ECIESEnvelope    // Layer 3 envelope
    let aesCiphertext: Data             // Layer 1 ciphertext (variable)
    let aesTag: Data                    // 16 bytes — Layer 1 auth tag
}

/// Contains the password-only encrypted payload used for portable exports.
struct UniversalEncryptedPayload {
    let salt: Data
    let iterations: UInt32
    let aesNonce: AES.GCM.Nonce
    let aesCiphertext: Data
    let aesTag: Data
}

// MARK: - Crypto Engine

/// Three-layer encryption/decryption engine for L0ck.
///
/// Encryption Pipeline:
/// ```
/// Layer 1: AES-256-GCM — encrypts file data with random DEK
/// Layer 2: ChaCha20-Poly1305 — wraps DEK with Combined KEK (password + master secret)
/// Layer 3: ECIES (Curve25519) — protects wrapped DEK with app key pair
/// ```
///
/// All three factors (password, master secret, private key) are required to decrypt.
struct CryptoEngine {
    /// Portable exports rely on password-only protection, so use a stronger KDF cost.
    static let universalExportPBKDF2Iterations: UInt32 = 1_000_000

    // MARK: - Encrypt

    /// Encrypt file data using the three-layer encryption pipeline.
    ///
    /// - Parameters:
    ///   - fileData: Raw file content to encrypt
    ///   - fileName: Original filename (embedded in encrypted data)
    ///   - password: User-provided password for KEK₁
    ///   - masterSecret: App Master Secret from Keychain for KEK₂
    ///   - publicKey: App's Curve25519 public key for Layer 3
    /// - Returns: ``EncryptedPayload`` containing all encrypted components
    static func encrypt(
        fileData: Data,
        fileName: String,
        password: String,
        masterSecret: Data,
        publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> EncryptedPayload {
        let plaintext = serializePlaintext(fileData: fileData, fileName: fileName)

        // === Layer 1: AES-256-GCM with random DEK ===
        let dek = KeyDerivation.generateDEK()
        let aesNonce = AES.GCM.Nonce()
        let aesSealedBox = try AES.GCM.seal(plaintext, using: dek, nonce: aesNonce)

        // === Layer 2: ChaCha20-Poly1305 wrapping DEK ===
        let salt = KeyDerivation.generateSalt()
        let iterations = KeyDerivation.defaultPBKDF2Iterations

        // Derive Combined KEK from password + master secret
        let kek1 = try KeyDerivation.deriveFromPassword(password, salt: salt, iterations: iterations)
        let kek2 = KeyDerivation.deriveFromMasterSecret(masterSecret)
        let combinedKEK = KeyDerivation.combinedKEK(kek1: kek1, kek2: kek2)

        // Serialize DEK to raw bytes
        var dekData = Data()
        dek.withUnsafeBytes { dekData.append(contentsOf: $0) }

        // Wrap DEK with ChaCha20-Poly1305
        let chachaSealedBox = try ChaChaPoly.seal(dekData, using: combinedKEK)
        // combined = nonce(12) + ciphertext(32) + tag(16) = 60 bytes
        let wrappedDEK = chachaSealedBox.combined

        // === Layer 3: ECIES protecting wrapped DEK ===
        let eciesEnvelope = try ECIESEngine.encrypt(wrappedDEK, to: publicKey)

        return EncryptedPayload(
            salt: salt,
            iterations: iterations,
            aesNonce: aesNonce,
            eciesEnvelope: eciesEnvelope,
            aesCiphertext: Data(aesSealedBox.ciphertext),
            aesTag: Data(aesSealedBox.tag)
        )
    }

    static func encryptUniversal(
        fileData: Data,
        fileName: String,
        password: String
    ) throws -> UniversalEncryptedPayload {
        let plaintext = serializePlaintext(fileData: fileData, fileName: fileName)
        let salt = KeyDerivation.generateSalt()
        let iterations = universalExportPBKDF2Iterations
        let key = try KeyDerivation.deriveFromPassword(password, salt: salt, iterations: iterations)
        let aesNonce = AES.GCM.Nonce()
        let aesSealedBox = try AES.GCM.seal(plaintext, using: key, nonce: aesNonce)

        return UniversalEncryptedPayload(
            salt: salt,
            iterations: iterations,
            aesNonce: aesNonce,
            aesCiphertext: Data(aesSealedBox.ciphertext),
            aesTag: Data(aesSealedBox.tag)
        )
    }

    // MARK: - Decrypt

    /// Decrypt file data using the three-layer decryption pipeline.
    ///
    /// - Parameters:
    ///   - payload: ``EncryptedPayload`` from deserialized .l0ck file
    ///   - password: User-provided password for KEK₁
    ///   - masterSecret: App Master Secret from Keychain for KEK₂
    ///   - privateKey: App's Curve25519 private key for Layer 3
    /// - Returns: Tuple of (original filename, decrypted file data)
    static func decrypt(
        payload: EncryptedPayload,
        password: String,
        masterSecret: Data,
        privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> (fileName: String, fileData: Data) {
        // === Layer 3: ECIES decrypt to recover wrapped DEK ===
        let wrappedDEK: Data
        do {
            wrappedDEK = try ECIESEngine.decrypt(payload.eciesEnvelope, with: privateKey)
        } catch {
            throw CryptoError.authenticationFailed
        }

        // === Layer 2: ChaCha20-Poly1305 unwrap DEK ===
        let chachaSealedBox: ChaChaPoly.SealedBox
        do {
            chachaSealedBox = try ChaChaPoly.SealedBox(combined: wrappedDEK)
        } catch {
            throw CryptoError.decryptionFailed(L10n.string("Invalid wrapped DEK format"))
        }

        // Re-derive Combined KEK from password + master secret
        let kek1 = try KeyDerivation.deriveFromPassword(
            password, salt: payload.salt, iterations: payload.iterations
        )
        let kek2 = KeyDerivation.deriveFromMasterSecret(masterSecret)
        let combinedKEK = KeyDerivation.combinedKEK(kek1: kek1, kek2: kek2)

        // Unwrap DEK
        let dekData: Data
        do {
            dekData = try ChaChaPoly.open(chachaSealedBox, using: combinedKEK)
        } catch {
            throw CryptoError.authenticationFailed
        }

        let dek = SymmetricKey(data: dekData)

        // === Layer 1: AES-256-GCM decrypt file data ===
        let aesSealedBox: AES.GCM.SealedBox
        do {
            aesSealedBox = try AES.GCM.SealedBox(
                nonce: payload.aesNonce,
                ciphertext: payload.aesCiphertext,
                tag: payload.aesTag
            )
        } catch {
            throw CryptoError.decryptionFailed(L10n.string("Invalid AES sealed box"))
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(aesSealedBox, using: dek)
        } catch {
            throw CryptoError.authenticationFailed
        }

        return try parsePlaintext(plaintext)
    }

    static func decryptUniversal(
        payload: UniversalEncryptedPayload,
        password: String
    ) throws -> (fileName: String, fileData: Data) {
        let key = try KeyDerivation.deriveFromPassword(
            password,
            salt: payload.salt,
            iterations: payload.iterations
        )

        let aesSealedBox: AES.GCM.SealedBox
        do {
            aesSealedBox = try AES.GCM.SealedBox(
                nonce: payload.aesNonce,
                ciphertext: payload.aesCiphertext,
                tag: payload.aesTag
            )
        } catch {
            throw CryptoError.decryptionFailed(L10n.string("Invalid AES sealed box"))
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(aesSealedBox, using: key)
        } catch {
            throw CryptoError.authenticationFailed
        }

        return try parsePlaintext(plaintext)
    }

    private static func serializePlaintext(fileData: Data, fileName: String) -> Data {
        let fileNameData = fileName.data(using: .utf8) ?? Data()
        var plaintext = Data()
        var fnLen = UInt32(fileNameData.count).bigEndian
        plaintext.append(Data(bytes: &fnLen, count: 4))
        plaintext.append(fileNameData)
        plaintext.append(fileData)
        return plaintext
    }

    private static func parsePlaintext(_ plaintext: Data) throws -> (fileName: String, fileData: Data) {
        guard plaintext.count >= 4 else {
            throw CryptoError.invalidFileFormat
        }

        let fnLenBytes = plaintext.prefix(4)
        let fnLen = fnLenBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        guard plaintext.count >= 4 + Int(fnLen) else {
            throw CryptoError.invalidFileFormat
        }

        let fileNameData = plaintext.subdata(in: 4..<(4 + Int(fnLen)))
        let fileName = String(data: fileNameData, encoding: .utf8) ?? "unknown"
        let fileData = plaintext.subdata(in: (4 + Int(fnLen))..<plaintext.count)

        return (fileName, fileData)
    }
}
