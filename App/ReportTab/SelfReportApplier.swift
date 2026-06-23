import Foundation

/// 自己報告ファストレーン: 報告した広告URLを、その端末で即ブロックに反映する。
/// サーバの3人閾値を待たずに「自分の報告は自分の端末で即効く」体験を実現する。
@MainActor
protocol SelfReportApplying {
    func apply(reportedURL: URL)
}

/// 本番実装: 報告URLを host-block ルール化 → App Group の自己報告ストアへ追記 →
/// 統合 ContentBlocker(`com.kureho.adblockkeshi.blocker`)の combined を再生成して reload。
/// 4→3 統合後、自己学習は標準 ContentBlocker に統合された（旧 reportedblocker は廃止）。
@MainActor
struct SelfReportApplier: SelfReportApplying {
    func apply(reportedURL: URL) {
        guard let rule = ReportedRuleBuilder.blockRule(forURL: reportedURL.absoluteString),
              let store = SelfReportedRulesStore()
        else { return }
        // 追記 + merged 再構築。失敗してもサーバ報告自体は成立しているので握り潰す。
        try? store.appendSelfRule(rule)
        // combined を再生成（off-main）して標準 ContentBlocker を reload。
        CombinedRuleListCoordinator.scheduleRegenerate()
    }
}
