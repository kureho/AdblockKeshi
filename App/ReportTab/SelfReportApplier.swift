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
        // ① Content Blocker(Safari) の自己ファストレーン
        if let rule = ReportedRuleBuilder.blockRule(forURL: reportedURL.absoluteString),
           let store = SelfReportedRulesStore() {
            // 追記 + merged 再構築。失敗してもサーバ報告自体は成立しているので握り潰す。
            try? store.appendSelfRule(rule)
            // combined を再生成（off-main）して標準 ContentBlocker を reload。
            CombinedRuleListCoordinator.scheduleRegenerate()
        }
        // ② DNS ブロックの自己ファストレーン（あなたの報告で他アプリの広告ブロックも即増える）
        //    tunnel が dns-rules(curated/CDN) ∪ dns-self を読む（DNSBlocklistLoader）。
        if let dnsStore = DNSSelfReportStore.sharedAppGroup() {
            DNSSelfReportApplier(store: dnsStore).apply(reportedURL: reportedURL)
        }
    }
}
