import Foundation

enum APIError: LocalizedError, Equatable {
    case networkUnavailable
    case rateLimitExceeded(retryAfter: TimeInterval)
    case validationFailed(field: String, reason: String)
    case criticalDomainProtected
    case turnstileVerificationFailed
    case unauthorized
    case banned(level: Int, expiresAt: Date)
    case serverError(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "インターネット接続を確認してください"
        case .rateLimitExceeded(let after):
            let hours = Int(after / 3600)
            if hours >= 24 {
                return "1 日の上限に達しました。明日また送信できます"
            } else if hours >= 1 {
                return "送信間隔の上限に達しました。\(hours) 時間後にお試しください"
            } else {
                return "送信間隔が短すぎます。少し時間を空けてください"
            }
        case .validationFailed(let field, let reason):
            return "入力エラー (\(field)): \(reason)"
        case .criticalDomainProtected:
            return "この URL は主要サービス保護のため報告の対象外です（誤ブロック防止）。時間を置いても送信できません"
        case .turnstileVerificationFailed:
            return "確認に失敗しました。もう一度お試しください"
        case .unauthorized:
            return "認証エラーです。アプリを再起動してください"
        case .banned(let level, _):
            return "報告機能が一時的に制限されています (level \(level))"
        case .serverError(let code):
            return "サーバエラー (HTTP \(code))。少し時間を空けて再試行してください"
        case .decodingFailed:
            return "サーバの応答を解釈できませんでした"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable: return true
        case .serverError(let code) where (500...599).contains(code): return true
        default: return false
        }
    }
}
