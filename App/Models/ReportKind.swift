import Foundation

/// 報告フォームの「なにを報告しますか？」（v4.2.0）。
///
/// サーバ (`workers/src/lib/report-kind.ts` の `REPORT_KINDS`) と **完全同期**させる。
/// rawValue がずれるとサーバが値を認識できず既定の広告報告として扱われ、
/// 壊れ報告が広告集約の母集団（= ブロックを強める方向）を汚染する。
///
/// v4.2.0 の中核: 「広告が消えない」（ブロックを強めたい）と「サイトが壊れた」
/// （ブロックが強すぎた）は改善の方向が真逆なので、入口で分ける。
enum ReportKind: String, CaseIterable, Identifiable, Sendable {
    case adNotBlocked = "ad_not_blocked"
    case siteBroken = "site_broken"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adNotBlocked: return "広告が消えない"
        case .siteBroken:   return "サイトが壊れた"
        }
    }

    var detail: String {
        switch self {
        case .adNotBlocked: return "ブロックしているのに広告が表示される"
        case .siteBroken:   return "ページが表示されない・レイアウトが崩れる・ボタンが効かない"
        }
    }

    var iconSystemName: String {
        switch self {
        case .adNotBlocked: return "rectangle.badge.xmark"
        case .siteBroken:   return "exclamationmark.triangle"
        }
    }

    /// 広告の種類（ad_type）の選択を要求するか。壊れ報告は広告タイプでは表せない。
    var requiresAdType: Bool {
        switch self {
        case .adNotBlocked: return true
        case .siteBroken:   return false
        }
    }
}
