import Foundation

/// 2 本目のブロッカー（報告反映）の土台 = 広告の残り（トグル別）→ ポップアップ対策（A-88 ①）。
///
/// 基本保護は 15 万件の上限で広告ルールの一部しか持てない。入り切らない残りを 2 本目に載せる。
/// 残りは基本保護の variant と対で作られている（scripts/build_split_rules.py）:
/// merged-rules.json ↔ second-ads-sec.json / ad-rules.json ↔ second-ads.json。
/// 並びは「残り → ポップアップ対策 → 報告 → 一時オフ」。ポップアップ対策の例外（L2）が後ろにあっても
/// 残りの広告ルールを打ち消さないよう、許可ドメイン宛ての広告ルールは基本保護側に寄せてある。
enum SecondBlockerBase {
    static let adsAndSecurityRemainder = "second-ads-sec.json"
    static let adsOnlyRemainder = "second-ads.json"
    static let remainderFilenames: Set<String> = [adsAndSecurityRemainder, adsOnlyRemainder]

    /// 基本保護の variant と対になる残りのファイル名。広告オフなら残りは無い（ポップアップ対策だけ）。
    static func adsRemainderFilename(for state: BlockerTogglesState) -> String? {
        guard state.adEnabled else { return nil }
        return state.securityEnabled ? adsAndSecurityRemainder : adsOnlyRemainder
    }

    /// 残りの後ろにポップアップ対策を繋ぐ。どちらもデコードせずバイト列のまま繋ぐ
    /// （残りは 1,000 万バイト級・ポップアップ対策は CDN の生 JSON で型に無いキーを落とさないため）。
    static func compose(adsRemainder: Data?, popunder: Data) throws -> Data {
        guard let adsRemainder else { return popunder }
        return try CombinedRuleListMerge.concatenate(adsRemainder, popunder)
    }

    /// 2 本目を作る。残りを載せた版が作れなければ（コンパイル失敗など）、ポップアップ対策だけで作り直す。
    /// 残りは CDN から毎月入れ替わる新しい失敗源。失敗したまま古い 2 本目を残すと、新しい報告も
    /// 「このサイトで一時オフ」も 2 本目に届かない（開けないサイトを開けなくなる）ので、残りを諦めて一時オフを通す。
    /// `rebuild(base, keepWhenNoReported)` は CombinedRuleListBuilder.rebuildIfNeeded を呼ぶ口。
    static func rebuild<Outcome>(composed: Data?, popunder: Data,
                                 using rebuild: (_ base: Data, _ keepWhenNoReported: Bool) throws -> Outcome) -> Outcome? {
        if let composed, let outcome = try? rebuild(composed, true) { return outcome }
        return try? rebuild(popunder, false)
    }

    /// ルール更新で残りのファイルが差し替わったら、2 本目を作り直す必要がある。
    static func needsRegenerate(afterApplying applied: [String]) -> Bool {
        applied.contains(where: remainderFilenames.contains)
    }
}
