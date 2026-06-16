import Foundation
import SafariServices

enum ContentRuleListMode: Equatable {
    case bothEnabled
    case baseOnly
    case reportedOnly
    case bothDisabled

    var isFullyOperational: Bool { self == .bothEnabled }

    var statusLabel: String {
        switch self {
        case .bothEnabled: return "広告ブロック中"
        case .baseOnly: return "広告ブロック中 (学習機能 OFF)"
        case .reportedOnly: return "⚠️ 本体ブロッカーが OFF です"
        case .bothDisabled: return "準備未完了"
        }
    }

    var bannerType: BannerType? {
        switch self {
        case .bothEnabled: return nil
        case .baseOnly: return .yellow("「自己学習フィルタ」を ON にすると、報告で広告ブロックが進化します")
        case .reportedOnly: return .red("「標準フィルタ」を ON にしてください。学習機能だけでは大部分の広告が通り抜けます")
        case .bothDisabled: return nil
        }
    }
}

enum BannerType: Equatable {
    case yellow(String)
    case red(String)
}

struct ContentRuleListSnapshot: Equatable {
    let baseEnabled: Bool
    let reportedEnabled: Bool
    /// 「ポップアップ広告対策」拡張（任意の追加保護）の ON/OFF。core(標準+学習)の判定には影響しない。
    let popunderEnabled: Bool
    let mode: ContentRuleListMode

    static func from(base: Bool, reported: Bool, popunder: Bool = false) -> ContentRuleListSnapshot {
        let mode: ContentRuleListMode
        switch (base, reported) {
        case (true, true): mode = .bothEnabled
        case (true, false): mode = .baseOnly
        case (false, true): mode = .reportedOnly
        case (false, false): mode = .bothDisabled
        }
        return ContentRuleListSnapshot(
            baseEnabled: base, reportedEnabled: reported, popunderEnabled: popunder, mode: mode
        )
    }

    /// core(標準+学習)が ON のとき、追加保護の「ポップアップ広告対策」も勧める任意ヒント。
    /// core が未完了のときは出さない（まずそちらの設定に集中させる）。
    var popunderSuggestion: BannerType? {
        guard mode == .bothEnabled, !popunderEnabled else { return nil }
        return .yellow("「ポップアップ広告対策」も ON にすると、タップ時に広告サイトへ飛ばされる誘導をブロックします")
    }
}

protocol ContentRuleListStateChecker: Sendable {
    func check() async -> ContentRuleListSnapshot
}

struct SFContentBlockerStateChecker: ContentRuleListStateChecker {
    static let baseID = "com.kureho.adblockkeshi.blocker"
    static let reportedID = "com.kureho.adblockkeshi.reportedblocker"
    static let popunderID = "com.kureho.adblockkeshi.popunderblocker"

    func check() async -> ContentRuleListSnapshot {
        // iOS 26 simulator: 並列 XPC コール (`async let`) が SFContentBlockerManager の
        // _contentBlockerLoaderConnection を _xpc_api_misuse で EXC_BREAKPOINT クラッシュさせる。
        // 実機でも同じ race condition リスクがあるため逐次化する (XPC は速いので体感差なし)。
        let b = await getEnabled(identifier: Self.baseID)
        let r = await getEnabled(identifier: Self.reportedID)
        let p = await getEnabled(identifier: Self.popunderID)
        return ContentRuleListSnapshot.from(base: b, reported: r, popunder: p)
    }

    private func getEnabled(identifier: String) async -> Bool {
        await withCheckedContinuation { cont in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, _ in
                cont.resume(returning: state?.isEnabled ?? false)
            }
        }
    }
}
