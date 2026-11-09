import Foundation
import CryptoKit
import CommonCrypto

/// Key material for pairing and per-device authentication.
///
/// The six-digit code only protects the short pairing window. The long-term
/// device key is never sent: both sides derive it from an X25519 agreement,
/// bound to the code-derived pairing key. See docs/REMOTE.md for limits.
enum RemotePairing {
    static let codeLength = 6
    static let saltLength = 16
    static let keyLength = 32
    static let iterations: UInt32 = 200_000

    static func makeCode<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000, using: &generator))
    }

    static func makeCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return makeCode(using: &generator)
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// PBKDF2-SHA256 stretches the short code so each guess against a recorded
    /// handshake costs real work; the per-window salt prevents precomputation.
    static func pairingKey(code: String, salt: Data, iterations: UInt32 = iterations) -> Data {
        var key = Data(count: keyLength)
        let password = Array(code.utf8)
        _ = key.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    password.map { CChar(bitPattern: $0) }, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    output.bindMemory(to: UInt8.self).baseAddress, keyLength)
            }
        }
        return key
    }

    /// Application-level proof of which key a peer holds. TLS only proves that
    /// one of the listener's keys matched, not which one.
    static func proof(key: Data, nonce: Data, label: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(label.utf8) + nonce, using: SymmetricKey(data: key)))
    }

    static func verify(_ proof: Data, key: Data, nonce: Data, label: String) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: Data(label.utf8) + nonce, using: SymmetricKey(data: key))
    }

    static func deviceKey(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicKey: Data,
                          pairingKey: Data, deviceID: UUID, macPublicKey: Data, phonePublicKey: Data) throws -> Data {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let info = Data("macprompter-device-v1".utf8) + Data(deviceID.uuidString.utf8) + macPublicKey + phonePublicKey
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: pairingKey, sharedInfo: info, outputByteCount: keyLength)
        return key.withUnsafeBytes { Data($0) }
    }
}

/// The Mac's pairing window: one code, a deadline and a small failure budget.
struct RemotePairingWindow: Equatable {
    let code: String
    let salt: Data
    let key: Data
    let expiresAt: Date
    private(set) var failures = 0

    init(code: String = RemotePairing.makeCode(), salt: Data = RemotePairing.randomBytes(RemotePairing.saltLength),
         now: Date = Date(), iterations: UInt32 = RemotePairing.iterations) {
        self.code = code; self.salt = salt
        key = RemotePairing.pairingKey(code: code, salt: salt, iterations: iterations)
        expiresAt = now.addingTimeInterval(RemoteProtocol.pairingDuration)
    }

    var remainingAttempts: Int { max(0, RemoteProtocol.maxPairingFailures - failures) }
    func isOpen(at date: Date) -> Bool { date < expiresAt && remainingAttempts > 0 }

    /// Returns whether the window stays open.
    mutating func registerFailure(at date: Date) -> Bool {
        failures += 1
        return isOpen(at: date)
    }
}
