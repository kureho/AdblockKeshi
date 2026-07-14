import Foundation
import Observation
import StoreKit

/// Pro 買い切り（Non-Consumable ¥800）の状態管理 + 既存購入者の grandfather 統合（StoreKit 2）。
///
/// Pro 判定は二本立て（plan §Pro 判定）:
///   isPro = grandfather（ProEntitlementCache）**OR** `Transaction.currentEntitlements`（購入）。
/// grandfather は `AppTransaction.originalAppVersion` を GrandfatherPolicy で判定して cache へ恒久化。
/// DEBUG 限定 Pro オーバーライド（起動引数 -FORCE_PRO / UserDefaults）で sim でも Pro ゲート先を開発可能。
///
/// 構造は family-concierge `PurchaseManager`（@MainActor @Observable・checkVerified）を踏襲。
@MainActor
@Observable
final class ProStore {

    /// Pro の Product ID（ローカル .storekit / ASC 側 IAP と一致）。
    static let proProductID = "com.kureho.adblockkeshi.pro"

    /// 転換判定の既定ポリシー。conversionBuild=10000（現行 build 27 << 10000 で全既存購入を救済）。
    /// cutoffDate は転換当日に確定する運用（Chunk 6）。現行は build 主判定が全て拾うため実害なしの placeholder。
    static let defaultPolicy = GrandfatherPolicy(
        conversionBuild: 10000,
        cutoffDate: ProStore.date(2026, 9, 1))

    enum LoadState: Equatable { case idle, loading, loaded, notFound, failed(String) }

    private(set) var isPro = false
    private(set) var loadState: LoadState = .idle
    private(set) var proProduct: Product?
    private(set) var isPurchasing = false

    private let cache: ProEntitlementCache
    private let policy: GrandfatherPolicy
    private let stateStore: ProStateStore?
    private var hasPurchaseEntitlement = false
    @ObservationIgnored private var listenerTask: Task<Void, Never>?

    init(cache: ProEntitlementCache = .makeDefault(),
         policy: GrandfatherPolicy = ProStore.defaultPolicy,
         stateStore: ProStateStore? = ProStateStore.sharedAppGroup(),
         debugForcePro: Bool = ProStore.resolveDebugForcePro()) {
        self.cache = cache
        self.policy = policy
        self.stateStore = stateStore
        #if DEBUG
        if debugForcePro { cache.grantPro() }   // RELEASE では効果なし（sim の Pro ゲート開発用）
        #endif
        recompute()
    }

    /// DEBUG 限定 Pro 強制の判定（起動引数 or UserDefaults）。RELEASE では常に false。
    nonisolated static func resolveDebugForcePro() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-FORCE_PRO")
            || UserDefaults.standard.bool(forKey: "FORCE_PRO")
        #else
        return false
        #endif
    }

    // MARK: - grandfather（AppTransaction のデータを注入して純粋にテスト可能）

    /// 既存購入者なら恒久 Pro を付与する（AppTransaction の値を注入・テスト可能）。
    func applyGrandfather(originalBuild: String?, originalPurchaseDate: Date?, environment: StoreEnvironment) {
        guard policy.isLegacy(originalBuild: originalBuild,
                              originalPurchaseDate: originalPurchaseDate,
                              environment: environment) else { return }
        cache.grantPro()
        recompute()
    }

    /// 実機起動時に呼ぶ: `AppTransaction.shared`（タイムアウト付き）→ grandfather 判定 → cache。
    /// 取得失敗/ハングは黙って無料側に倒す（過少付与）。sim では取得できないので何もしない。
    func refreshGrandfatherFromAppTransaction(timeout seconds: TimeInterval = 5) async {
        let payload: (String, Date, StoreEnvironment)? = await withTaskGroup(
            of: (String, Date, StoreEnvironment)?.self
        ) { group in
            group.addTask {
                do {
                    let result = try await AppTransaction.shared
                    let tx = try Self.verified(result)
                    let env: StoreEnvironment = (tx.environment == .production) ? .production : .sandbox
                    return (tx.originalAppVersion, tx.originalPurchaseDate, env)
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil   // タイムアウト
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let (build, date, env) = payload {
            applyGrandfather(originalBuild: build, originalPurchaseDate: date, environment: env)
        }
    }

    // MARK: - StoreKit（PurchaseManager 踏襲）

    /// Pro 商品を取得する。商品なしは `.notFound`（IAP 未設定）で通信失敗 `.failed` と区別。
    func loadProduct() async {
        loadState = .loading
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            loadState = (products.first == nil) ? .notFound : .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Pro を購入する。成立で entitlement 反映 → isPro。二重押下は guard。
    @discardableResult
    func purchase() async -> Bool {
        guard !isPurchasing else { return false }
        guard let product = proProduct else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                hasPurchaseEntitlement = true
                recompute()
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// 購入の復元（Guideline 3.1.1・復元ボタンから呼ぶ）。
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// 現在の entitlement から購入保有を反映する（起動時 + Transaction 更新時）。
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.verified(result),
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        hasPurchaseEntitlement = owned
        recompute()
    }

    /// 買い切り完了・払い戻し等の Transaction 更新を購読する（起動時 1 度・多重起動 guard）。
    func startTransactionListener() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if let transaction = try? Self.verified(update) {
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    func stopTransactionListener() {
        listenerTask?.cancel()
        listenerTask = nil
    }

    // MARK: - helpers

    /// Pro 判定を再計算し、App Group state へ反映する（tunnel が読む）。
    /// isPro = grandfather(cache) OR 購入 entitlement。
    private func recompute() {
        isPro = cache.isPro() || hasPurchaseEntitlement
        try? stateStore?.write(ProState(isPro: isPro))
    }

    /// StoreKit 2 の署名検証。未検証は信用しない。
    nonisolated private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }

    nonisolated private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }
}
