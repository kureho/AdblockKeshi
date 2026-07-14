import XCTest
import StoreKit
import StoreKitTest
@testable import AdblockKeshi

/// ProStore（買い切り + grandfather 統合）のテスト。
/// 2 層: 決定論ユニット（storekitd 非依存・常時）+ StoreKitTest 統合（.storekit・CLI では skip）。
@MainActor
final class ProStoreTests: XCTestCase {

    final class FakeFlagStore: ProFlagStore {
        var stored = false
        func readPro() -> Bool { stored }
        func writePro() { stored = true }
    }

    private func makeCache() -> ProEntitlementCache {
        ProEntitlementCache(stores: [FakeFlagStore(), FakeFlagStore()])
    }

    private func tempStateStore() -> (ProStateStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prostore-\(UUID().uuidString).json")
        return (ProStateStore(stateFileURL: url), url)
    }

    // MARK: - 決定論ユニット（storekitd 非依存・常時実行）

    func test_init_notPro_whenCacheEmpty_andNoDebugForce() {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        XCTAssertFalse(store.isPro)
    }

    func test_debugForcePro_grantsProAtInit() {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: true)
        XCTAssertTrue(store.isPro, "DEBUG 強制で Pro ゲート先を sim 開発可能に")
    }

    func test_applyGrandfather_legacyProduction_setsPro() {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        store.applyGrandfather(originalBuild: "27", originalPurchaseDate: nil, environment: .production)
        XCTAssertTrue(store.isPro, "build 27 < 10000 の既存購入者は恒久 Pro")
    }

    func test_applyGrandfather_sandbox_staysFree() {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        store.applyGrandfather(originalBuild: "1", originalPurchaseDate: nil, environment: .sandbox)
        XCTAssertFalse(store.isPro, "審査/sandbox では grandfather 無効（購入導線を見せる）")
    }

    func test_applyGrandfather_newBuild_staysFree() {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        store.applyGrandfather(originalBuild: "10000", originalPurchaseDate: nil, environment: .production)
        XCTAssertFalse(store.isPro)
    }

    func test_grandfather_writesProStateTrue() {
        let (ss, url) = tempStateStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProStore(cache: makeCache(), stateStore: ss, debugForcePro: false)
        store.applyGrandfather(originalBuild: "5", originalPurchaseDate: nil, environment: .production)
        XCTAssertTrue(ss.read().isPro, "grandfather 付与が App Group state に反映される（tunnel が読む）")
    }

    func test_purchase_returnsFalse_whenNoProductLoaded() async {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        let ok = await store.purchase()
        XCTAssertFalse(ok)
        XCTAssertFalse(store.isPro)
    }

    func test_refreshEntitlements_keepsFree_whenNoEntitlements() async {
        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        await store.refreshEntitlements()
        XCTAssertFalse(store.isPro)
    }

    // MARK: - StoreKitTest 統合（.storekit 経由・実購入シミュレート・課金なし／CLI では skip）
    // ★環境注記★ Xcode 26.3+ の iOS 26 sim では xcodebuild test から storekitd へ config が push されず
    //   SKTestSession が機能しない（flutter#184678）。iOS 18.3 ランタイム sim で実 PASS する
    //   （reference_storekittest_cli_workaround）。機能しない環境では XCTSkip する。

    private var skipReason: String {
        "SKTestSession が storekitd に接続できません（Xcode 26.3+ の xcodebuild test 既知不具合）。iOS 18.3 sim / Xcode IDE では有効。"
    }

    private func makeSession() throws -> SKTestSession {
        let bundleURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "AdblockKeshi", withExtension: "storekit"),
            "AdblockKeshi.storekit が test bundle に同梱されていません"
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdblockKeshi-\(UUID().uuidString).storekit")
        try FileManager.default.copyItem(at: bundleURL, to: tempURL)
        let session: SKTestSession
        do {
            session = try SKTestSession(contentsOf: tempURL)
        } catch {
            throw XCTSkip("\(skipReason)（SKTestSession 初期化失敗: \(error.localizedDescription)）")
        }
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// storekitd 稼働確認: probe 購入が張れなければ skip（環境不良を失敗と区別）。
    private func requireWorkingStoreKitTest(_ session: SKTestSession) async throws {
        do {
            _ = try await session.buyProduct(identifier: ProStore.proProductID)
            session.clearTransactions()
        } catch {
            throw XCTSkip("\(skipReason)（session probe 失敗: \(error)）")
        }
    }

    func test_loadProduct_setsLoaded_whenConfigHasProduct() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await requireWorkingStoreKitTest(session)

        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        await store.loadProduct()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.proProduct?.id, ProStore.proProductID)
    }

    func test_purchase_setsProTrue_onSuccess() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await requireWorkingStoreKitTest(session)

        let store = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        await store.loadProduct()
        XCTAssertEqual(store.loadState, .loaded, "probe 通過後は config 商品がロードされる")
        XCTAssertFalse(store.isPro, "購入前は未保有")

        let ok = await store.purchase()
        XCTAssertTrue(ok, "購入が成立する")
        XCTAssertTrue(store.isPro, "購入で Pro=true")
    }

    /// 別インスタンス（再インストール/機種変相当）が現行 entitlement から Pro を復元できること。
    /// 遅い `product.purchase()` UI フロー（watchdog kill 誘発）ではなく高速 `session.buyProduct` で
    /// entitlement を確立し、fresh インスタンスの `refreshEntitlements()` が拾うことを検証する。
    func test_refreshEntitlements_reflectsOwnedProduct() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await requireWorkingStoreKitTest(session)

        // 高速 buy（UI フロー非経由）で entitlement を確立
        _ = try await session.buyProduct(identifier: ProStore.proProductID)

        // 別インスタンス（起動時 refreshEntitlements 相当）で Pro を復元
        let fresh = ProStore(cache: makeCache(), stateStore: nil, debugForcePro: false)
        XCTAssertFalse(fresh.isPro, "refresh 前は未反映")
        await fresh.refreshEntitlements()
        XCTAssertTrue(fresh.isPro, "所有 entitlement から Pro を復元（再インストール耐性）")
    }
}
