import Foundation

/// Pure URL validator for the report form.
/// spec rev4 §2 (A-88 で改訂): https-only, 送信形 (`URL.absoluteString`) で 2048 文字以内,
/// min host length 7。
///
/// A-88 送信エラー修正①: 以前は貼り付けた生文字列 (`raw.count`) を 200 文字で判定していたが、
/// 実際にサーバへ送るのは `components.url.absoluteString`（日本語等は %XX percent-encoding で
/// 展開される）。実測で生73字の日本語入り URL が送信形233字になり、サーバ側の旧上限(200)で
/// url_too_long として弾かれ、3回で自動停止（誤 ban）の原因になっていた。サーバ側の上限は
/// 別途 2048 に引き上げ、アプリ側もこれに合わせて「送信する文字列」の長さで判定する。
enum URLValidator {
    enum Result: Equatable {
        case valid(URL)
        case invalid(Reason)
    }

    enum Reason: Equatable {
        case empty
        case httpNotAllowed
        case tooLong
        case malformed
        case suspiciouslyShort

        var userMessage: String {
            switch self {
            case .empty: return "URL を入力してください"
            case .httpNotAllowed: return "https:// で始まる URL を入力してください"
            // 上限の数字はサーバ側の変更で動きうるため画面には出さない。
            case .tooLong: return "URL が長すぎます"
            case .malformed: return "URL の形式が正しくありません"
            case .suspiciouslyShort: return "ドメインが短すぎる可能性があります"
            }
        }
    }

    static let maxLength = 2048
    static let minDomainLength = 7

    static func validate(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(.empty) }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") { return .invalid(.httpNotAllowed) }
        guard lower.hasPrefix("https://") else { return .invalid(.malformed) }
        guard let components = URLComponents(string: trimmed),
              let host = components.host,
              !host.isEmpty else {
            return .invalid(.malformed)
        }
        guard host.count >= minDomainLength else {
            return .invalid(.suspiciouslyShort)
        }
        guard let url = components.url else {
            return .invalid(.malformed)
        }
        // 実際にサーバへ送る形（percent-encoding 後）の長さで判定する。
        guard url.absoluteString.count <= maxLength else { return .invalid(.tooLong) }
        return .valid(url)
    }
}

/// Pure memo validator. spec rev4: 200 char max, max 5 lines, no embedded URLs (server-side
/// still PII-redacts even if these pass).
enum MemoValidator {
    enum Result: Equatable {
        case valid
        case invalid(Reason)
    }

    enum Reason: Equatable {
        case tooLong
        case containsURL
        case tooManyLines

        var userMessage: String {
            switch self {
            case .tooLong: return "メモは 200 文字以内で入力してください"
            case .containsURL: return "メモに URL を入れないでください。URL は上の欄に入力してください"
            case .tooManyLines: return "メモは 5 行以内で入力してください"
            }
        }
    }

    static let maxLength = 200
    static let maxLines = 5

    private static let urlPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"https?://[^\s]+"#, options: [.caseInsensitive])
    }()

    static func validate(_ raw: String) -> Result {
        guard raw.count <= maxLength else { return .invalid(.tooLong) }
        let lineCount = raw.components(separatedBy: .newlines).count
        guard lineCount <= maxLines else { return .invalid(.tooManyLines) }
        let range = NSRange(raw.startIndex..., in: raw)
        if urlPattern.firstMatch(in: raw, options: [], range: range) != nil {
            return .invalid(.containsURL)
        }
        return .valid
    }
}
