import Foundation

// MARK: - Request DTOs

struct TokenRequestDTO: Encodable {
    let turnstileResponse: String
    let scope: String
    let uuidHash: String

    enum CodingKeys: String, CodingKey {
        case turnstileResponse = "turnstile_response"
        case scope
        case uuidHash = "uuid_hash"
    }
}

/// Workers の `SubmitBody`（`workers/src/handlers/submit.ts`）と 1:1 対応。
/// Optional は synthesized encoder が `encodeIfPresent` するのでキーごと省略され、
/// サーバ側では未指定 = NULL として扱われる。
struct SubmitRequestDTO: Encodable {
    let token: String
    let uuidHash: String
    let url: String
    let memo: String?
    let adType: String?
    /// v4.2.0: 報告種別（ad_not_blocked / site_broken）。新クライアントは常に送る。
    /// 旧サーバは未知キーとして無視し、新サーバは未送信を ad_not_blocked として扱う。
    let reportKind: String
    /// D-lite: どこで見た広告か。**有無が新旧クライアントの境界**でもある。
    let seenIn: String?
    /// 以下は診断用の自動添付。取得できなくても報告を失敗させないため全て任意。
    let blockerEnabled: Bool?
    let dnsEnabled: Bool?
    let appVersion: String?
    let appBuild: String?
    let filterVersion: String?

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
        case url, memo
        case adType = "ad_type"
        case reportKind = "report_kind"
        case seenIn = "seen_in"
        case blockerEnabled = "blocker_enabled"
        case dnsEnabled = "dns_enabled"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case filterVersion = "filter_version"
    }
}

struct HistoryRequestDTO: Encodable {
    let token: String
    let uuidHash: String

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
    }
}

struct DeletionRequestDTO: Encodable {
    let token: String
    let uuidHash: String
    let urlPathHash: String?

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
        case urlPathHash = "url_path_hash"
    }
}

// MARK: - Response DTOs

struct TokenResponseDTO: Decodable {
    let token: String
    let expiresAt: Date
    let serverSalt: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case serverSalt = "server_salt"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.token = try c.decode(String.self, forKey: .token)
        let ts = try c.decode(Int64.self, forKey: .expiresAt)
        self.expiresAt = Date(timeIntervalSince1970: TimeInterval(ts))
        self.serverSalt = try c.decode(String.self, forKey: .serverSalt)
    }
}

struct SubmitResponseDTO: Decodable {
    let id: String
    let status: String
    let receivedAt: Date
    let memoRedacted: Bool

    enum CodingKeys: String, CodingKey {
        case id, status
        case receivedAt = "received_at"
        case memoRedacted = "memo_redacted"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.status = try c.decode(String.self, forKey: .status)
        let ts = try c.decode(Int64.self, forKey: .receivedAt)
        self.receivedAt = Date(timeIntervalSince1970: TimeInterval(ts))
        self.memoRedacted = try c.decode(Bool.self, forKey: .memoRedacted)
    }
}

struct APIErrorResponseDTO: Decodable {
    let error: String
    let message: String?
    let retryAfter: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case error, message
        case retryAfter = "retry_after"
    }
}
