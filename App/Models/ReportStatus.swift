import SwiftUI

enum ReportStatus: String, Codable, CaseIterable, Equatable {
    case pending
    case validating
    case approved
    case rejectedNoAdDetected = "rejected_no_ad_detected"
    case rejectedSafetyGate = "rejected_safety_gate"

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
        case .pending: return "報告を受け付けました。検証開始まで最大 1 時間。"
        case .validating: return "自動検証中です。最大 7 日間で結果が出ます。"
        case .approved: return "広告ブロックリストへ反映済みです。"
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
