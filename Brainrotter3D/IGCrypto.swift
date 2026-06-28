import Foundation
import CryptoKit
import Security

/// Crypto + device-identity helpers ported byte-for-byte from the reverse-engineered
/// Python client (`api_client.py`) so the device fingerprint and `enc_password` blob
/// the server sees are identical to the ones it already trusts.
enum IGCrypto {

    // MARK: Device identity

    /// Format 32 hex chars as a canonical UUID string (8-4-4-4-12), matching
    /// Python's `str(uuid.UUID(hex32))`.
    static func uuidString(fromHex32 hex: String) -> String {
        let s = Array(hex.prefix(32))
        guard s.count == 32 else { return UUID().uuidString.lowercased() }
        func part(_ a: Int, _ b: Int) -> String { String(s[a..<b]) }
        return "\(part(0,8))-\(part(8,12))-\(part(12,16))-\(part(16,20))-\(part(20,32))"
    }

    static func sha256Hex(_ s: String) -> String {
        let d = SHA256.hash(data: Data(s.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    /// `jazoest` = "2" + sum of ASCII codes of every character in `symbols`.
    static func jazoest(_ symbols: String) -> String {
        let sum = symbols.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return "2" + String(sum)
    }

    // MARK: enc_password

    /// Builds the `#PWD_INSTAGRAM:4:<ts>:<base64>` string.
    /// Layout: [0x01][keyId][iv:12][u16le(len(rsaEnc))][rsaEnc][gcmTag:16][ciphertext]
    /// where rsaEnc = RSA-2048 PKCS#1 v1.5(aesKey) and ciphertext/tag = AES-256-GCM(password).
    static func encryptPassword(_ password: String,
                                pubKeyB64: String,
                                keyId: String) throws -> String {
        guard let secKey = rsaPublicKey(fromHeaderValue: pubKeyB64) else {
            throw IGError.crypto("could not parse server password public key")
        }
        let ts = String(Int(Date().timeIntervalSince1970))
        let aesKey = randomData(32)
        let iv = randomData(12)

        // 1) RSA-PKCS1v1.5 encrypt the random AES key -> 256 bytes for RSA-2048.
        var err: Unmanaged<CFError>?
        guard let rsaEnc = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1,
                                                     aesKey as CFData, &err) as Data? else {
            throw IGError.crypto("RSA encrypt failed: \(String(describing: err?.takeRetainedValue()))")
        }

        // 2) AES-256-GCM over the password, AAD = the ASCII timestamp, nonce = iv.
        let sealed = try AES.GCM.seal(Data(password.utf8),
                                      using: SymmetricKey(data: aesKey),
                                      nonce: try AES.GCM.Nonce(data: iv),
                                      authenticating: Data(ts.utf8))
        let ct = sealed.ciphertext
        let tag = sealed.tag

        var payload = Data()
        payload.append(0x01)
        payload.append(UInt8((Int(keyId) ?? 0) & 0xff))
        payload.append(iv)
        var len = UInt16(rsaEnc.count).littleEndian
        withUnsafeBytes(of: &len) { payload.append(contentsOf: $0) }
        payload.append(rsaEnc)
        payload.append(tag)
        payload.append(ct)

        return "#PWD_INSTAGRAM:4:\(ts):\(payload.base64EncodedString())"
    }

    // MARK: RSA key parsing

    /// The `ig-set-password-encryption-pub-key` header is base64 that decodes to a PEM
    /// "BEGIN PUBLIC KEY" (SPKI). Strip the PEM armor + the SPKI wrapper to recover the
    /// raw PKCS#1 RSAPublicKey that `SecKeyCreateWithData` expects.
    static func rsaPublicKey(fromHeaderValue headerB64: String) -> SecKey? {
        guard let pemData = Data(base64Encoded: headerB64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let pem = String(data: pemData, encoding: .utf8) else { return nil }

        let body = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let spki = Data(base64Encoded: body),
              let pkcs1 = pkcs1FromSPKI([UInt8](spki)) else { return nil }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        return SecKeyCreateWithData(Data(pkcs1) as CFData, attrs as CFDictionary, nil)
    }

    /// Walk the SPKI DER (SEQUENCE { AlgorithmIdentifier, BIT STRING { RSAPublicKey } })
    /// and return the RSAPublicKey bytes inside the BIT STRING.
    private static func pkcs1FromSPKI(_ b: [UInt8]) -> [UInt8]? {
        var o = 0
        guard let outer = readTLV(b, &o), outer.tag == 0x30 else { return nil }
        var p = outer.start
        guard let alg = readTLV(b, &p), alg.tag == 0x30 else { return nil }
        p = alg.start + alg.len                                  // skip AlgorithmIdentifier
        guard let bit = readTLV(b, &p), bit.tag == 0x03 else { return nil }
        // BIT STRING content begins with an "unused bits" byte (0x00) we drop.
        let from = bit.start + 1
        let to = bit.start + bit.len
        guard from <= to, to <= b.count else { return nil }
        return Array(b[from..<to])
    }

    /// Reads one DER TLV. Returns the tag plus the content's start index and length, and
    /// advances `offset` past the tag+length header (to the first content byte).
    private static func readTLV(_ b: [UInt8], _ offset: inout Int) -> (tag: UInt8, start: Int, len: Int)? {
        guard offset + 1 < b.count else { return nil }
        let tag = b[offset]; offset += 1
        var len = Int(b[offset]); offset += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard offset + n <= b.count else { return nil }
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(b[offset]); offset += 1 }
        }
        return (tag, offset, len)
    }

    static func randomData(_ count: Int) -> Data {
        var d = Data(count: count)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return d
    }
}

enum IGError: Error, LocalizedError {
    case crypto(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .crypto(let m), .network(let m), .server(let m): return m
        }
    }
}
