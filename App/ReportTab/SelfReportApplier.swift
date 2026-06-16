import Foundation
import SafariServices

/// 自己報告ファストレーン: 報告した広告URLを、その端末で即ブロックに反映する。
/// サーバの3人閾値を待たずに「自分の報告は自分の端末で即効く」体験を実現する。
@MainActor
protocol SelfReportApplying {
    func apply(reportedURL: URL)
}

/// 本番実装: 報告URLを host-block ルール化 → App Group の自己報告ストアへ追記 →
/// 報告Extension(`com.kureho.adblockkeshi.reportedblocker`)を reload。
@MainActor
struct SelfReportApplier: SelfReportApplying {
    func apply(reportedURL: URL) {
        guard let rule = ReportedRuleBuilder.blockRule(forURL: reportedURL.absoluteString),
              let store = SelfReportedRulesStore()
        else { return }
        // 追記 + merged 再構築。失敗してもサーバ報告自体は成立しているので握り潰す。
        try? store.appendSelfRule(rule)
        SFContentBlockerManager.reloadContentBlocker(
            withIdentifier: SFContentBlockerStateChecker.reportedID
        ) { _ in }
    }
}
