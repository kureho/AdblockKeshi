import Foundation

enum APIError: LocalizedError, Equatable {
    case networkUnavailable
    case rateLimitExceeded(retryAfter: TimeInterval)
    case validationFailed(field: String, reason: String)
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
            // サーバの実際の単位は日次 86400 秒 / 月次 2,592,000 秒の 2 通りだけ
            // (`workers/src/lib/rate-limit.ts` UUID_DAILY_LIMIT / UUID_MONTHLY_LIMIT)。
            // 月次を「明日また送れます」と言うと嘘になるため、まず月次を判定する。
            let hours = Int(after / 3600)
            if hours >= 24 * 7 {
                return "月の送信上限に達しました。しばらく経ってから送信できます"
            } else if hours >= 24 {
                return "1 日の上限に達しました。明日また送信できます"
            } else if hours >= 1 {
                return "送信間隔の上限に達しました。\(hours) 時間後にお試しください"
            } else {
                return "送信間隔が短すぎます。少し時間を空けてください"
            }
        case .validationFailed:
            // サーバの生文言（英語混じり・技術用語）はそのまま出さない。
            // field は現状サーバ応答から正しく判別できない（常に "url" 固定で来る）ため、
            // URL・メモの両方に触れる汎用文言にする。
            return "入力内容をご確認ください（URL の形式やメモの長さなど）"
        case .turnstileVerificationFailed:
            return "確認に失敗しました。もう一度お試しください"
        case .unauthorized:
            return "認証エラーです。アプリを再起動してください"
        case .banned:
            // サーバは実際の停止期間（24h/7d/30d/permanent）を返さないため期限は断定しない。
            // 「アプリを再起動してください」は誤り（再起動しても直らない）なので unauthorized とは分ける。
            return "現在この報告機能を一時的に停止しています。しばらく経ってからもう一度お試しください"
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
