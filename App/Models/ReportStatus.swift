import SwiftUI

enum ReportStatus: String, Codable, CaseIterable, Equatable {
    case pending
    case validating
    case approved
    case rejectedNoAdDetected = "rejected_no_ad_detected"
    case rejectedSafetyGate = "rejected_safety_gate"

    /// 未知の値は `.pending` に寄せる（fail-safe）。
    ///
    /// D-lite で `applied_locally`（端末即反映）を廃止したが、既存端末の履歴には
    /// その値が保存されている。素直に throw すると `LocalReportHistoryStore` の
    /// fail-safe が働いて **履歴が丸ごと消える**ため、受付済として読み替える。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReportStatus(rawValue: raw) ?? .pending
    }

    var displayLabel: String {
        switch self {
        case .pending: return "受付済"
        case .validating: return "検証中"
        case .approved: return "反映済"
        case .rejectedNoAdDetected, .rejectedSafetyGate: return "対象外"
        }
    }

    var badgeRole: BadgeRole {
        switch self {
        case .pending: return .neutral
        case .validating: return .info
        case .approved: return .success
        case .rejectedNoAdDetected, .rejectedSafetyGate: return .warning
        }
    }

    var detailDescription: String {
        switch self {
        case .pending: return "報告を受け付けました。フィルタ改善の参考として確認します。"
        case .validating: return "内容を確認しています。"
        case .approved: return "広告ブロックリストへ反映済みです。"
        case .rejectedNoAdDetected: return "確認しましたが、広告を検出できませんでした。"
        case .rejectedSafetyGate: return "安全装置により、フィルタへの反映対象から除外されました (大手サイト等)。"
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
