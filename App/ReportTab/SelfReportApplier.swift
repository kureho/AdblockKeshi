import Foundation

/// 自己報告ファストレーン: 報告した広告URLを、その端末で即ブロックに反映する。
/// サーバの3人閾値を待たずに「自分の報告は自分の端末で即効く」体験を実現する。
@MainActor
protocol SelfReportApplying {
    func apply(reportedURL: URL)
}

/// 本番実装: 報告URLを host-block ルール化 → App Group の自己報告ストアへ追記 →
/// 報告反映(popunder)の combined を再生成して報告反映 ContentBlocker(`.popunderblocker`)を reload。
/// 4→3 統合後、自己学習は「報告反映」拡張に統合された（旧 reportedblocker は廃止・名称整合のため popunder へ再配置）。
@MainActor
struct SelfReportApplier: SelfReportApplying {
    func apply(reportedURL: URL) {
        // Content Blocker(Safari) の自己ファストレーン。
        // `load-type: third-party` + document 除外なので、訪問中のサイト自体は壊さない。
        if let rule = ReportedRuleBuilder.blockRule(forURL: reportedURL.absoluteString),
           let store = SelfReportedRulesStore() {
            // 追記 + merged 再構築。失敗してもサーバ報告自体は成立しているので握り潰す。
            try? store.appendSelfRule(rule)
            // combined を再生成（off-main）して標準 ContentBlocker を reload。
            CombinedRuleListCoordinator.scheduleRegenerate()
        }
        // ★DNS 自己ファストレーンは v4.0.3 で廃止（DNSSelfReportApplier ごと削除）。
        // DNS には first-party / third-party の区別が無いため、「広告が消えなかったページ」を
        // 報告するとそのサイト自体が名前解決できなくなっていた（4.0.2 までの不具合）。
        // 残骸の削除は AdblockKeshiApp.migrateReportedRulesIfNeeded() が起動時に行う。
    }
}
