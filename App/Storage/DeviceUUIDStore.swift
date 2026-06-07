import Foundation
import CryptoKit

/// UUID stored only in Keychain. server_salt-based SHA-256 hash sent to server
/// (spec rev4 §2 §3). Original UUID never leaves the device.
struct DeviceUUIDStore {
    static let account = "device-uuid"

    private let keychain: KeychainHelper
    private let serverSalt: String

    init(keychain: KeychainHelper = KeychainHelper(), serverSalt: String) {
        self.keychain = keychain
        self.serverSalt = serverSalt
    }

    /// Phase 2 では Info.plist の DEV_SERVER_SALT を使う。Phase 5 で feature-flags.json
    /// 経由の dynamic salt に変更 (server_salt は token response に含まれる)。
    static func loadServerSaltFromBundle() -> String {
        guard let salt = Bundle.main.object(forInfoDictionaryKey: "DEV_SERVER_SALT") as? String,
              !salt.isEmpty else {
            assertionFailure("DEV_SERVER_SALT not set in Info.plist (Phase 2 only)")
            return "placeholder-salt-phase2"
        }
        return salt
    }

    /// Read existing UUID, or generate a new one and persist to Keychain on first call.
    func getUUID() throws -> String {
        if let data = try keychain.load(account: Self.account),
           let uuid = String(data: data, encoding: .utf8) {
            return uuid
        }
        let newUUID = UUID().uuidString
        try keychain.save(account: Self.account, data: newUUID.data(using: .utf8)!)
        return newUUID
    }

    /// SHA-256("\(uuid):\(server_salt)") as lowercase hex (64 chars).
    func getUUIDHash() throws -> String {
        let uuid = try getUUID()
        let input = "\(uuid):\(serverSalt)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Test or kureho-issued reset (e.g., for reproducing user reports).
    func reset() throws {
        try keychain.delete(account: Self.account)
    }
}
