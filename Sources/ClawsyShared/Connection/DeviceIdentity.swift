import Foundation
import CryptoKit

// MARK: - Device Identity

/// Manages the Curve25519 signing keypair for device authentication.
/// Compatible with OpenClaw Protocol V3 device identity.
///
/// Key storage: Keychain (primary) with App Group fallback.
/// Device ID: SHA256(publicKey.rawRepresentation) as hex string.
public final class DeviceIdentity {

    // MARK: - Singleton

    public static let shared = DeviceIdentity()

    // MARK: - Properties

    /// The device's unique identifier (hex-encoded SHA256 of public key)
    public private(set) var deviceId: String = ""

    /// Base64url-encoded public key for transmission to gateway
    public private(set) var publicKeyBase64URL: String = ""

    /// Raw public key bytes
    public private(set) var publicKeyRaw: Data = Data()

    private var privateKey: Curve25519.Signing.PrivateKey?

    // MARK: - Constants

    private let keychainService = "ai.clawsy.device-identity"
    private let keychainAccount = "signing-key"

    // MARK: - Init

    private init() {
        loadOrCreateIdentity()
    }

    // MARK: - Public API

    /// Sign a payload with the device's private key.
    /// Returns base64url-encoded signature, or nil if no key available.
    public func sign(_ payload: String) -> String? {
        guard let key = privateKey else { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let signature = try? key.signature(for: data) else { return nil }
        return signature.rawRepresentation.base64URLEncoded()
    }

    /// Construct a V3 signature payload as per OpenClaw Protocol V3.
    ///
    /// Format: `v3|{deviceId}|{clientId}|{clientMode}|{role}|{scopes}|{signedAtMs}|{authToken}|{nonce}|{platform}|{deviceFamily}`
    public func signV3(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        authToken: String,
        nonce: String,
        platform: String = "macos",
        deviceFamily: String = "mac"
    ) -> (signature: String, signedAt: Int64)? {
        let signedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let scopeStr = scopes.joined(separator: ",")

        // Normalize platform and device family: lowercase ASCII only
        let normalizedPlatform = platform.lowercased()
        let normalizedFamily = deviceFamily.lowercased()

        let payload = [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopeStr,
            String(signedAt),
            authToken,
            nonce,
            normalizedPlatform,
            normalizedFamily
        ].joined(separator: "|")

        guard let sig = sign(payload) else { return nil }
        return (sig, signedAt)
    }

    /// Build the `device` dictionary for the connect request.
    public func deviceAuthPayload(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        authToken: String,
        nonce: String
    ) -> [String: Any]? {
        guard let result = signV3(
            clientId: clientId,
            clientMode: clientMode,
            role: role,
            scopes: scopes,
            authToken: authToken,
            nonce: nonce
        ) else { return nil }

        return [
            "id": deviceId,
            "publicKey": publicKeyBase64URL,
            "signature": result.signature,
            "signedAt": result.signedAt,
            "nonce": nonce
        ]
    }

    // MARK: - Key Management

    private func loadOrCreateIdentity() {
        if let keyData = loadFromKeychain() {
            privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        }

        if privateKey == nil {
            // Try App Group migration (from legacy Clawsy)
            if let legacyKey = loadFromAppGroup() {
                privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: legacyKey)
                if privateKey != nil {
                    // Migrate to Keychain
                    saveToKeychain(legacyKey)
                }
            }
        }

        if privateKey == nil {
            // Generate new key
            let newKey = Curve25519.Signing.PrivateKey()
            privateKey = newKey
            saveToKeychain(newKey.rawRepresentation)
        }

        // Derive public info
        if let key = privateKey {
            publicKeyRaw = key.publicKey.rawRepresentation
            publicKeyBase64URL = publicKeyRaw.base64URLEncoded()
            deviceId = SHA256.hash(data: publicKeyRaw)
                .compactMap { String(format: "%02x", $0) }
                .joined()
        }
    }

    // MARK: - Keychain Storage

    private func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func saveToKeychain(_ keyData: Data) {
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - App Group Migration (Legacy)

    private func loadFromAppGroup() -> Data? {
        guard let defaults = UserDefaults(suiteName: "group.ai.openclaw.clawsy") else { return nil }
        guard let b64 = defaults.string(forKey: "devicePrivateKey") else { return nil }
        return Data(base64Encoded: b64)
    }
}

// MARK: - Data Extensions

extension Data {
    /// Base64url encoding (RFC 4648 §5): +→-, /→_, no padding
    func base64URLEncoded() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
