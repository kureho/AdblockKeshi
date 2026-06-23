import Foundation
import SafariServices
import WebKit

/// 統合 ContentBlocker の combined-<variant> 再生成と標準 ContentBlocker(.blocker) の reload を束ねる。
///
/// 報告追加 / トグル変更 / global sync / 起動 migration の各トリガーから呼ぶ。
/// 重い処理（decode/splice/write/compile-verify）を含むため **off-main で実行する**
/// （`scheduleRegenerate()` 経由なら自動で global queue に載る）。reload のみ main。
/// App ターゲット専用（WKContentRuleListStore / SFContentBlockerManager を使うため Shared に置かない）。
enum CombinedRuleListCoordinator {
    enum CoordinatorError: Error { case encoding, compileTimeout }

    /// 再生成は **serial queue で直列化**する。報告追加とトグル変更が連打されても、
    /// 並行実行で「古い combined が新しい combined を上書きする」順序逆転を防ぐ（off-main も兼ねる）。
    private static let regenQueue = DispatchQueue(
        label: "com.kureho.adblockkeshi.combined-regen", qos: .utility)

    /// 任意スレッドから安全に起動。fire-and-forget。
    static func scheduleRegenerate() {
        regenQueue.async { regenerateIfNeeded() }
    }

    /// 報告反映(popunder)の combined を必要時のみ再生成し、変化時だけ報告反映 ContentBlocker を reload。
    /// あわせて、基本保護からは報告ルールを外し（combined を持たず bundle variant へ戻す）旧 combined を一掃する。
    /// **off-main 前提**（compile-verify が semaphore で待つため main で呼ぶと deadlock）。
    static func regenerateIfNeeded() {
        guard let store = SelfReportedRulesStore(),
              let builder = CombinedRuleListBuilder(appBuildVersion: appBuildVersion()) else { return }

        // 1) 報告反映(popunder)= popunder L1+L2（base）+ 安全化 reported（最後尾）。
        //    base は App 同梱/CDN の popunder-rules.json（combined ではない）。
        //    base が取れなければ報告反映を更新できないので、basic にも触らず終了する
        //    （popunder 不在時に basic を bundle へ剥がして防御を一時消失させない）。
        let popunderResolver = BlockerListResolver(filterFilename: PopunderRulesResolver.filename)
        guard let popunderBase = popunderResolver.resolveDirect(),
              let baseData = try? Data(contentsOf: popunderBase) else { return }
        let popunderRules = (try? JSONDecoder().decode([ContentBlockerRule].self, from: baseData)) ?? []
        // L2 ipr が許可するドメイン（プレーヤー等）に一致する reported は除外（再 block で破壊しない）。
        let l2Allowed = PopunderReportedFilter.l2AllowedDomains(popunderRules: popunderRules)
        let reportedForPopunder = PopunderReportedFilter.excludingL2Allowed(
            store.safeMergedReportedRules(), allowed: l2Allowed)
        let outcome = try? builder.rebuildIfNeeded(
            variantFilename: PopunderRulesResolver.filename,
            standardRulesURL: popunderBase,
            mayTruncate: false,                 // popunder+reported ≪ 150,000・truncation 不要
            reportedSafe: reportedForPopunder,
            compileVerify: compileVerify
        )
        if outcome?.rebuilt == true {
            DispatchQueue.main.async {
                SFContentBlockerManager.reloadContentBlocker(
                    withIdentifier: SFContentBlockerStateChecker.popunderID) { _ in }
            }
        }

        // 2) 基本保護は報告ルールを持たない → 旧 combined-<state> を一掃し bundle variant に戻す。
        //    popunder base が取れている＝報告反映が機能する状態（combined or 直 base）なので安全。
        if builder.removeBasicCombined() {
            DispatchQueue.main.async {
                SFContentBlockerManager.reloadContentBlocker(
                    withIdentifier: SFContentBlockerStateChecker.baseID) { _ in }
            }
        }
    }

    private static func appBuildVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    /// 生成 JSON が WebKit で compile できるか検証（移行手順 ⑤）。失敗時は throw して install を止め、
    /// 既存 combined（last-known-good）を保持する。budget で件数は保証済みのため主目的は
    /// 万一の malformed reported ルール検出（defense-in-depth）。
    private static func compileVerify(_ data: Data) throws {
        guard let json = String(data: data, encoding: .utf8) else { throw CoordinatorError.encoding }
        let sem = DispatchSemaphore(value: 0)
        var compileError: Error?
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "combined-verify",
            encodedContentRuleList: json
        ) { _, error in
            compileError = error
            sem.signal()
        }
        // off-main 前提。completion は別 queue で発火するので deadlock しない。30s でタイムアウト。
        if sem.wait(timeout: .now() + 30) == .timedOut { throw CoordinatorError.compileTimeout }
        // 検証用にコンパイルした孤児エントリを削除（WKContentRuleListStore に溜めない）。best-effort。
        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "combined-verify") { _ in }
        if let e = compileError { throw e }
    }
}
