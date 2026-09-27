import SwiftUI

enum ReportStatus: String, Codable, CaseIterable, Equatable {
    case pending
    case validating
    case approved
    case rejectedNoAdDetected = "rejected_no_ad_detected"
    case rejectedSafetyGate = "rejected_safety_gate"
    /// A-88 §3: `POST /v1/reports/status` の週次判定結果から来る状態。
    /// serverId を持つ行だけ `LocalReportHistoryStore.refreshStatuses` がこれらへ更新する。
    case checking
    case inAppAd = "in_app_ad"
    case siteOwnAd = "site_own_ad"
    case declined

    /// 未知の値は `.pending` に寄せる（fail-safe）。
    ///
    /// D-lite で `applied_locally`（端末即反映）を廃止したが、既存端末の履歴には
    /// その値が保存されている。素直に throw すると `LocalReportHistoryStore` の
    /// fail-safe が働いて **履歴が丸ごと消える**ため、受付済として読み替える。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReportStatus(rawValue: raw) ?? .pending
    }

    /// サーバーが返す丸め値（`checking/applied/in_app_ad/site_own_ad/declined`）を
    /// 履歴表示用の `ReportStatus` へ対応させる。設計 `tasks/a88-design-2026-09-27.md` §3。
    /// `applied` は「今の approved と同じ見た目でよい」ため既存 case を再利用する。
    /// 未知の値は nil（呼び出し側はその行の更新をスキップし、今の表示のまま保つ）。
    static func fromServerOutcome(_ raw: String) -> ReportStatus? {
        switch raw {
        case "checking": return .checking
        case "applied": return .approved
        case "in_app_ad": return .inAppAd
        case "site_own_ad": return .siteOwnAd
        case "declined": return .declined
        default: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .pending: return "受付済"
        case .validating: return "検証中"
        case .approved: return "反映済"
        case .rejectedNoAdDetected, .rejectedSafetyGate: return "対象外"
        case .checking: return "確認中"
        case .inAppAd: return "アプリ内広告"
        case .siteOwnAd: return "サイト自身の広告"
        case .declined: return "見送り"
        }
    }

    var badgeRole: BadgeRole {
        switch self {
        case .pending: return .neutral
        case .validating, .checking: return .info
        case .approved: return .success
        case .rejectedNoAdDetected, .rejectedSafetyGate, .inAppAd, .siteOwnAd, .declined: return .warning
        }
    }

    var detailDescription: String {
        switch self {
        case .pending: return "報告を受け付けました。フィルタ改善の参考として確認します。"
        case .validating: return "内容を確認しています。"
        case .approved: return "広告ブロックリストへ反映済みです。"
        case .rejectedNoAdDetected: return "確認しましたが、広告を検出できませんでした。"
        case .rejectedSafetyGate: return "安全装置により、フィルタへの反映対象から除外されました (大手サイト等)。"
        case .checking: return "内容を確認しています。結果が出るまで、もうしばらくお待ちください。"
        case .inAppAd: return "アプリの中に表示される広告のため、Safari のブロックでは消せません。「アプリ内広告ブロック」を使うと防げます。"
        case .siteOwnAd: return "サイト自身が出している広告です。止めるとページが壊れるおそれがあるため、対象外としています。"
        case .declined: return "確認しましたが、今回はブロックへの追加を見送りました。"
        }
    }
}

enum BadgeRole: Equatable {
    case neutral
    case info
    case success
    case warning

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        }
    }
}
