import Foundation

/// Pro 権利（grandfather or 購入）を **3 冗長 + in-memory latch** で恒久保持するキャッシュ。
///
/// 設計意図（tasks/v4-freemium-dns-plan.md §grandfather 準拠）:
/// - **剥奪しない**: 一度 true になったら以後の read が false/失敗でも true を返す（memory latch）。
/// - **3 冗長**: UserDefaults + Keychain + iCloud KVS。read は「どれか1つでも true なら true」。
/// - **再インストール耐性**: iCloud KVS が Apple ID 経由で機種変・再インストール後も復元（iCloud 有効端末）。
///   iCloud OFF 端末では KVS が効かず UserDefaults/Keychain にフォールバック（過少付与に倒す）。
protocol ProFlagStore {
    func readPro() -> Bool
    func writePro()
}

final class ProEntitlementCache {

    private let stores: [ProFlagStore]
    private var latched = false

    init(stores: [ProFlagStore]) {
        self.stores = stores
    }

    /// 本番配線（UserDefaults 共有 + Keychain + iCloud KVS の 3 レール）。
    static func makeDefault() -> ProEntitlementCache {
        ProEntitlementCache(stores: [
            UserDefaultsProFlagStore(),
            KeychainProFlagStore(),
            ICloudKVSProFlagStore(),
        ])
    }

    /// Pro 権利があるか。memory latch → いずれかのレールが true → true。
    func isPro() -> Bool {
        if latched { return true }
        if stores.contains(where: { $0.readPro() }) {
            latched = true   // 一度でも true を観測したら latch（以後の flaky read で剥奪しない）
            return true
        }
        return false
    }

    /// Pro 権利を付与する（全レールへ書込 + latch）。以後 read が flaky でも剥奪しない。
    func grantPro() {
        latched = true
        for store in stores { store.writePro() }
    }
}

// MARK: - 本番レール（薄いアダプタ）

/// UserDefaults レール（App Group 共有）。
struct UserDefaultsProFlagStore: ProFlagStore {
    let defaults: UserDefaults
    let key: String
    init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.kureho.adblockkeshi.shared") ?? .standard,
         key: String = "pro_entitlement_granted") {
        self.defaults = defaults
        self.key = key
    }
    func readPro() -> Bool { defaults.bool(forKey: key) }
    func writePro() { defaults.set(true, forKey: key) }
}

/// Keychain レール（既存 KeychainHelper 利用・再インストールでも残る場合がある）。
struct KeychainProFlagStore: ProFlagStore {
    let helper: KeychainHelper
    let account: String
    init(helper: KeychainHelper = KeychainHelper(), account: String = "pro_entitlement_granted") {
        self.helper = helper
        self.account = account
    }
    func readPro() -> Bool {
        // try? は Data? を平坦化して Data? を返す（throw/未検出はどちらも nil = false）
        guard let data = try? helper.load(account: account) else { return false }
        return data == Data([1])
    }
    func writePro() { try? helper.save(account: account, data: Data([1])) }
}

/// iCloud KVS レール（Apple ID 経由で機種変・再インストール後も復元。iCloud OFF 端末では実質無効）。
struct ICloudKVSProFlagStore: ProFlagStore {
    let store: NSUbiquitousKeyValueStore
    let key: String
    init(store: NSUbiquitousKeyValueStore = .default, key: String = "pro_entitlement_granted") {
        self.store = store
        self.key = key
    }
    func readPro() -> Bool {
        store.synchronize()
        return store.bool(forKey: key)
    }
    func writePro() {
        store.set(true, forKey: key)
        store.synchronize()
    }
}
