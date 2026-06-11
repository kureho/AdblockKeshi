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
    let mode: ContentRuleListMode

    static func from(base: Bool, reported: Bool) -> ContentRuleListSnapshot {
        let mode: ContentRuleListMode
        switch (base, reported) {
        case (true, true): mode = .bothEnabled
        case (true, false): mode = .baseOnly
        case (false, true): mode = .reportedOnly
        case (false, false): mode = .bothDisabled
        }
        return ContentRuleListSnapshot(baseEnabled: base, reportedEnabled: reported, mode: mode)
    }
}

protocol ContentRuleListStateChecker: Sendable {
    func check() async -> ContentRuleListSnapshot
}

struct SFContentBlockerStateChecker: ContentRuleListStateChecker {
    static let baseID = "com.kureho.adblockkeshi.blocker"
    static let reportedID = "com.kureho.adblockkeshi.reportedblocker"

    func check() async -> ContentRuleListSnapshot {
        // iOS 26 simulator: 並列 XPC コール (`async let` で 2 本) が SFContentBlockerManager の
        // _contentBlockerLoaderConnection を _xpc_api_misuse で EXC_BREAKPOINT クラッシュさせる。
        // 実機でも同じ race condition リスクがあるため逐次化する (2 回の XPC は速いので体感差なし)。
        let b = await getEnabled(identifier: Self.baseID)
        let r = await getEnabled(identifier: Self.reportedID)
        return ContentRuleListSnapshot.from(base: b, reported: r)
    }

    private func getEnabled(identifier: String) async -> Bool {
        await withCheckedContinuation { cont in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, _ in
                cont.resume(returning: state?.isEnabled ?? false)
            }
        }
    }
}
