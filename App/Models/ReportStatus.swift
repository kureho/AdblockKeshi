import SwiftUI

enum ReportStatus: String, Codable, CaseIterable, Equatable {
    case pending
    case validating
    case approved
    /// この端末で即ブロック反映済み（自己報告ファストレーン）。全体反映は別途サーバ検証を待つ。
    case appliedLocally = "applied_locally"
    case rejectedNoAdDetected = "rejected_no_ad_detected"
    case rejectedSafetyGate = "rejected_safety_gate"

    var displayLabel: String {
        switch self {
        case .pending: return "受付済"
        case .validating: return "検証中"
        case .approved: return "反映済"
        case .appliedLocally: return "この端末で反映済"
        case .rejectedNoAdDetected, .rejectedSafetyGate: return "対象外"
        }
    }

    var badgeRole: BadgeRole {
        switch self {
        case .pending: return .neutral
        case .validating: return .info
        case .approved, .appliedLocally: return .success
        case .rejectedNoAdDetected, .rejectedSafetyGate: return .warning
        }
    }

    var detailDescription: String {
        switch self {
        case .pending: return "報告を受け付けました。検証開始まで最大 1 時間。"
        case .validating: return "自動検証中です。最大 7 日間で結果が出ます。"
        case .approved: return "広告ブロックリストへ反映済みです。"
        case .appliedLocally: return "この端末ではすぐにブロックへ反映しました。全体への反映は検証後（最大 7 日）です。"
        case .rejectedNoAdDetected: return "自動検証で広告を検出できませんでした。"
        case .rejectedSafetyGate: return "安全装置で除外されました (大手サイト等)。"
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
