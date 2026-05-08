import Foundation
import CryptoKit

// MARK: - L0ck File Format

struct L0ckFileFormat {
    enum SerializedPayload {
        case deviceBound(EncryptedPayload)
        case universal(UniversalEncryptedPayload)
    }

    /// Magic bytes identifying a .l0ck file: ASCII "L0CK"
    static let magic: [UInt8] = [0x4C, 0x30, 0x43, 0x4B]

    /// Device-bound multi-factor format version.
    static let deviceBoundVersion: UInt8 = 0x02

    /// Portable password-only format version.
    static let universalVersion: UInt8 = 0x03

    /// File extension for encrypted files
    static let fileExtension = "l0ck"

    // MARK: - Serialize

    /// Serialize an ``EncryptedPayload`` into binary .l0ck file data.
    ///
    /// - Parameter payload: The encrypted payload to serialize
    /// - Returns: Binary data ready to write to a .l0ck file
    static func serialize(_ payload: EncryptedPayload) -> Data {
        var data = Data()

        appendHeader(&data, version: deviceBoundVersion)

        // ── PBKDF2 Parameters ──
        data.append(payload.salt)            // 32 bytes
        appendUInt32(&data, payload.iterations) // 4 bytes

        // ── AES-GCM Nonce ──
        payload.aesNonce.withUnsafeBytes {
            data.append(contentsOf: $0)      // 12 bytes
        }

        // ── ECIES Envelope ──
        let ephPubKeyData = payload.eciesEnvelope.ephemeralPublicKey.rawRepresentation
        data.append(ephPubKeyData)           // 32 bytes

        payload.eciesEnvelope.nonce.withUnsafeBytes {
            data.append(contentsOf: $0)      // 12 bytes
        }

        appendUInt32(&data, UInt32(payload.eciesEnvelope.ciphertext.count)) // 4 bytes
        data.append(payload.eciesEnvelope.ciphertext)  // variable
        data.append(payload.eciesEnvelope.tag)          // 16 bytes

        // ── AES-GCM Encrypted Data ──
        appendUInt32(&data, UInt32(payload.aesCiphertext.count)) // 4 bytes
        data.append(payload.aesCiphertext)   // variable
        data.append(payload.aesTag)          // 16 bytes

        return data
    }

    static func serializeUniversal(_ payload: UniversalEncryptedPayload) -> Data {
        var data = Data()

        appendHeader(&data, version: universalVersion)
        data.append(payload.salt)
        appendUInt32(&data, payload.iterations)

        payload.aesNonce.withUnsafeBytes {
            data.append(contentsOf: $0)
        }

        appendUInt32(&data, UInt32(payload.aesCiphertext.count))
        data.append(payload.aesCiphertext)
        data.append(payload.aesTag)

        return data
    }

    // MARK: - Deserialize

    /// Deserialize binary .l0ck file data into an ``EncryptedPayload``.
    ///
    /// - Parameter data: Binary data from a .l0ck file
    /// - Returns: The deserialized ``EncryptedPayload``
    /// - Throws: ``CryptoError/invalidFileFormat`` if the data is malformed
    static func deserialize(_ data: Data) throws -> EncryptedPayload {
        guard case let .deviceBound(payload) = try deserializePayload(data) else {
            throw CryptoError.invalidFileFormat
        }

        return payload
    }

    static func deserializePayload(_ data: Data) throws -> SerializedPayload {
        var offset = 0

        // Helper: read N bytes and advance offset
        func readBytes(_ count: Int) throws -> Data {
            guard offset + count <= data.count else {
                throw CryptoError.invalidFileFormat
            }
            let result = data.subdata(in: offset..<(offset + count))
            offset += count
            return result
        }

        // Helper: read big-endian UInt32
        func readUInt32() throws -> UInt32 {
            let bytes = try readBytes(4)
            return bytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }

        func readByte() throws -> UInt8 {
            let bytes = try readBytes(1)
            return bytes[bytes.startIndex]
        }

        // ── Validate Magic ──
        let magicBytes = try readBytes(4)
        guard Array(magicBytes) == magic else {
            throw CryptoError.invalidFileFormat
        }

        switch try readByte() {
        case deviceBoundVersion:
            let salt = try readBytes(32)
            let iterations = try readUInt32()

            let aesNonceData = try readBytes(12)
            let aesNonce = try AES.GCM.Nonce(data: aesNonceData)

            let ephPubKeyData = try readBytes(32)
            let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: ephPubKeyData
            )

            let eciesNonceData = try readBytes(12)
            let eciesNonce = try AES.GCM.Nonce(data: eciesNonceData)

            let eciesCTLen = try readUInt32()
            let eciesCiphertext = try readBytes(Int(eciesCTLen))
            let eciesTag = try readBytes(16)

            let aesCTLen = try readUInt32()
            let aesCiphertext = try readBytes(Int(aesCTLen))
            let aesTag = try readBytes(16)

            let eciesEnvelope = ECIESEnvelope(
                ephemeralPublicKey: ephemeralPublicKey,
                nonce: eciesNonce,
                ciphertext: eciesCiphertext,
                tag: eciesTag
            )

            return .deviceBound(
                EncryptedPayload(
                    salt: salt,
                    iterations: iterations,
                    aesNonce: aesNonce,
                    eciesEnvelope: eciesEnvelope,
                    aesCiphertext: aesCiphertext,
                    aesTag: aesTag
                )
            )
        case universalVersion:
            let salt = try readBytes(32)
            let iterations = try readUInt32()
            let aesNonceData = try readBytes(12)
            let aesNonce = try AES.GCM.Nonce(data: aesNonceData)
            let aesCTLen = try readUInt32()
            let aesCiphertext = try readBytes(Int(aesCTLen))
            let aesTag = try readBytes(16)

            return .universal(
                UniversalEncryptedPayload(
                    salt: salt,
                    iterations: iterations,
                    aesNonce: aesNonce,
                    aesCiphertext: aesCiphertext,
                    aesTag: aesTag
                )
            )
        default:
            throw CryptoError.invalidFileFormat
        }
    }

    // MARK: - Helpers

    private static func appendHeader(_ data: inout Data, version: UInt8) {
        data.append(contentsOf: magic)
        data.append(version)
    }

    /// Append a UInt32 in big-endian format to data.
    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var be = value.bigEndian
        data.append(Data(bytes: &be, count: 4))
    }
}
