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

struct SubmitRequestDTO: Encodable {
    let token: String
    let uuidHash: String
    let url: String
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
        case url, memo
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
