import Foundation
import CryptoKit

// MARK: - ECIES Errors

enum ECIESError: Error, LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidPublicKey
    case invalidData

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let msg):
            return L10n.format("ECIES encryption failed: %@", msg)
        case .decryptionFailed(let msg):
            return L10n.format("ECIES decryption failed: %@", msg)
        case .invalidPublicKey:
            return L10n.string("Invalid Curve25519 public key")
        case .invalidData:
            return L10n.string("Invalid ECIES envelope data")
        }
    }
}

// MARK: - ECIES Envelope

/// Contains all components of an ECIES encrypted message.
///
/// Structure:
/// - Ephemeral public key (32 bytes, Curve25519)
/// - AES-GCM nonce (12 bytes)
/// - Ciphertext (variable length)
/// - Authentication tag (16 bytes)
struct ECIESEnvelope {
    let ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey
    let nonce: AES.GCM.Nonce
    let ciphertext: Data
    let tag: Data
}

// MARK: - ECIES Engine

/// Elliptic Curve Integrated Encryption Scheme using Curve25519.
///
/// Provides Layer 3 encryption in L0ck's three-layer scheme.
/// Uses ECDH key agreement + HKDF key derivation + AES-256-GCM.
///
/// Even with full source code, an attacker cannot decrypt without the
/// Curve25519 private key stored in the macOS Keychain.
struct ECIESEngine {

    private static let info = "L0ck.ECIES.v2".data(using: .utf8)!
    private static let salt = "L0ck.ECIES.Salt.v2".data(using: .utf8)!

    // MARK: - Encrypt

    /// Encrypt data using ECIES (Curve25519 ECDH + HKDF + AES-256-GCM).
    ///
    /// Generates a per-message ephemeral key pair, performs ECDH with the
    /// recipient's static public key, derives a symmetric key via HKDF,
    /// and encrypts using AES-256-GCM.
    ///
    /// - Parameters:
    ///   - plaintext: Data to encrypt
    ///   - recipientPublicKey: The recipient's Curve25519 public key
    /// - Returns: An ``ECIESEnvelope`` containing all encrypted components
    static func encrypt(
        _ plaintext: Data,
        to recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ECIESEnvelope {
        // Generate ephemeral key pair (used only for this message)
        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey

        // ECDH to compute shared secret
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientPublicKey
        )

        // Derive symmetric key from shared secret via HKDF-SHA256
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )

        // Encrypt with AES-256-GCM
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)

        return ECIESEnvelope(
            ephemeralPublicKey: ephemeralPublicKey,
            nonce: sealedBox.nonce,
            ciphertext: Data(sealedBox.ciphertext),
            tag: Data(sealedBox.tag)
        )
    }

    // MARK: - Decrypt

    /// Decrypt an ECIES envelope using the recipient's private key.
    ///
    /// - Parameters:
    ///   - envelope: The ``ECIESEnvelope`` to decrypt
    ///   - privateKey: The recipient's Curve25519 private key
    /// - Returns: Decrypted plaintext data
    static func decrypt(
        _ envelope: ECIESEnvelope,
        with privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        // ECDH to recover the shared secret
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
            with: envelope.ephemeralPublicKey
        )

        // Derive the same symmetric key
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )

        // Decrypt with AES-256-GCM
        let sealedBox = try AES.GCM.SealedBox(
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )

        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Key Generation

    /// Generate a new Curve25519 key pair for the app.
    static func generateKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        return Curve25519.KeyAgreement.PrivateKey()
    }
}
