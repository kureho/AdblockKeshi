import Foundation

/// 「フィルタ最終更新」表示の実態化（虚偽表示の解消・2026-07-04 監査 P1）。
/// 表示日付 = **実際に端末へ適用された** variant の generated_at（AppliedRulesStore の記録）。
/// 適用記録が無い端末（CDN 未取得）は bundle 同梱ルールの生成日にフォールバックする。
/// 旧実装は CDN の version.json をそのまま表示していたため、拡張が読む variant が
/// bundle 凍結のままでも「最新」を騙る虚偽表示になっていた。
enum FilterUpdateDisplay {
    static func displayDate(
        state: BlockerTogglesState,
        applied: [String: AppliedRulesRecord],
        bundledGeneratedAt: Date?
    ) -> Date? {
        let variant = BlockerListResolver().filename(for: state)
        if let record = applied[variant] {
            return record.generatedAt
        }
        return bundledGeneratedAt
    }
}

/// bundle 同梱ルール（Extension/Resources の variant 群）の生成日メタデータ。
/// App/Resources/bundled-rules-info.json を読む。**同梱ルールを差し替えたら必ずこのファイルも更新する**。
enum BundledRulesInfo {
    static let filename = "bundled-rules-info.json"

    static func generatedAt(bundle: Bundle = .main) -> Date? {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> Date? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any],
              let raw = dict["generated_at"] as? String
        else { return nil }
        return RuleUpdatePlanner.parseISO8601(raw)
    }
}
