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
    /// v4.2.0: per-site 例外（このサイトで一時オフ）があるときは、基本保護も
    /// `combined-<variant>` = 標準 + 例外ルール を生成する（無ければ従来どおり bundle variant へ戻す）。
    /// **off-main 前提**（compile-verify が semaphore で待つため main で呼ぶと deadlock）。
    static func regenerateIfNeeded() {
        guard let store = SelfReportedRulesStore(),
              let builder = CombinedRuleListBuilder(appBuildVersion: appBuildVersion()) else { return }

        // v4.2.0: per-site 例外ルール（ignore-previous-rules のみ）。
        // ★必ず各リストの最後尾に置く（ignore-previous-rules は「それ以前」にしか効かない）。
        // 予算超過時も ReportedRuleBudget は末尾（=新しい方）を保持するので例外は切られない。
        let exceptionRules = SiteExceptionRules.rules(
            for: SiteExceptionsStore.sharedAppGroup()?.readDomains() ?? [])

        // 1) 報告反映(popunder)= popunder L1+L2（base）+ 安全化 reported + 例外（最後尾）。
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
            mayTruncate: false,                 // popunder+reported+例外 ≪ 150,000・truncation 不要
            reportedSafe: reportedForPopunder + exceptionRules,
            compileVerify: compileVerify
        )
        if outcome?.rebuilt == true {
            DispatchQueue.main.async {
                SFContentBlockerManager.reloadContentBlocker(
                    withIdentifier: SFContentBlockerStateChecker.popunderID) { _ in }
            }
        }

        // 2) 基本保護:
        //    - 例外あり → combined-<activeVariant> = 標準 + 例外ルール（resolver の combined 最優先で拾われる）
        //    - 例外なし → 従来どおり combined を持たず bundle variant に戻す（旧 combined を一掃）
        //    popunder base が取れている＝報告反映が機能する状態（combined or 直 base）なので安全。
        let togglesState = StateStore.sharedAppGroup()?.read() ?? .default
        if let plan = BasicExceptionRegenPlan.plan(state: togglesState,
                                                   hasExceptions: !exceptionRules.isEmpty),
           let standardURL = BlockerListResolver().standardRulesURL(for: togglesState) {
            // 非アクティブ variant の孤児 combined を消してから、アクティブだけ再生成する。
            builder.cleanupCombined(except: plan.variantFilename)
            let basicOutcome = try? builder.rebuildIfNeeded(
                variantFilename: plan.variantFilename,
                standardRulesURL: standardURL,
                mayTruncate: plan.mayTruncate,   // ad-only は標準が上限ちょうど（budget 必須）
                reportedSafe: exceptionRules,
                compileVerify: compileVerify
            )
            if basicOutcome?.rebuilt == true {
                DispatchQueue.main.async {
                    SFContentBlockerManager.reloadContentBlocker(
                        withIdentifier: SFContentBlockerStateChecker.baseID) { _ in }
                }
            }
        } else if builder.removeBasicCombined() {
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
