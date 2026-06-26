import Foundation
import SafariServices

/// 4→3 統合後、自己学習は標準 ContentBlocker に内包されたため、状態は
/// 「標準(自己学習込み) ON」/「OFF」の 2 値のみ（旧 baseOnly/reportedOnly は到達不能なので削除）。
enum ContentRuleListMode: Equatable {
    case bothEnabled
    case bothDisabled

    var isFullyOperational: Bool { self == .bothEnabled }

    var statusLabel: String {
        switch self {
        case .bothEnabled: return "広告ブロック中"
        case .bothDisabled: return "準備未完了"
        }
    }
}

enum BannerType: Equatable {
    case yellow(String)
    case red(String)
}

struct ContentRuleListSnapshot: Equatable {
    let baseEnabled: Bool
    /// 「報告反映」拡張（任意の追加保護）の ON/OFF。core(基本+学習)の判定には影響しない。
    let popunderEnabled: Bool
    let mode: ContentRuleListMode

    static func from(base: Bool, popunder: Bool = false) -> ContentRuleListSnapshot {
        ContentRuleListSnapshot(
            baseEnabled: base, popunderEnabled: popunder,
            mode: base ? .bothEnabled : .bothDisabled
        )
    }

    /// core(基本保護) が ON のとき、追加保護の「報告反映」も勧める任意ヒント。
    /// core が未完了のときは出さない（まずそちらの設定に集中させる）。
    var popunderSuggestion: BannerType? {
        guard mode == .bothEnabled, !popunderEnabled else { return nil }
        return .yellow("「報告反映」も ON にすると、タップ時に広告サイトへ飛ばされる誘導をブロックします")
    }
}

protocol ContentRuleListStateChecker: Sendable {
    func check() async -> ContentRuleListSnapshot
}

struct SFContentBlockerStateChecker: ContentRuleListStateChecker {
    static let baseID = "com.kureho.adblockkeshi.blocker"
    static let popunderID = "com.kureho.adblockkeshi.popunderblocker"

    func check() async -> ContentRuleListSnapshot {
        // iOS 26 simulator: 並列 XPC コール (`async let`) が SFContentBlockerManager の
        // _contentBlockerLoaderConnection を _xpc_api_misuse で EXC_BREAKPOINT クラッシュさせる。
        // 実機でも同じ race condition リスクがあるため逐次化する (XPC は速いので体感差なし)。
        let b = await getEnabled(identifier: Self.baseID)
        let p = await getEnabled(identifier: Self.popunderID)
        // 4→3 統合: 自己学習は標準 ContentBlocker に統合済み（独立 reportedblocker 拡張は廃止）。
        return ContentRuleListSnapshot.from(base: b, popunder: p)
    }

    private func getEnabled(identifier: String) async -> Bool {
        await withCheckedContinuation { cont in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, _ in
                cont.resume(returning: state?.isEnabled ?? false)
            }
        }
    }
}
