import Foundation

/// Pure URL validator for the report form.
/// spec rev4 §2: https-only, 200 char max, min host length 7.
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
            case .tooLong: return "URL が長すぎます (200 文字以内)"
            case .malformed: return "URL の形式が正しくありません"
            case .suspiciouslyShort: return "ドメインが短すぎる可能性があります"
            }
        }
    }

    static let maxLength = 200
    static let minDomainLength = 7

    static func validate(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(.empty) }
        guard trimmed.count <= maxLength else { return .invalid(.tooLong) }
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
