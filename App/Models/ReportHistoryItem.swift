import Foundation

struct ReportHistoryItem: Codable, Equatable, Identifiable {
    let id: String
    let url: String
    let memo: String?
    let memoRedacted: Bool
    let status: ReportStatus
    let createdAt: Date
    let validatedAt: Date?
    let appliedAt: Date?
    /// A-88 §1: 送信成功時にサーバーが返す報告 ID（UUID）。週次判定結果の問い合わせに使う。
    /// 4.3 以前に送った報告には無い（nil）＝「受付済」のまま表示する（進め方4の対応表どおり）。
    let serverId: String?

    enum CodingKeys: String, CodingKey {
        case id, url, memo, status
        case memoRedacted = "memo_redacted"
        case createdAt = "created_at"
        case validatedAt = "validated_at"
        case appliedAt = "applied_at"
        case serverId = "server_id"
    }

    init(id: String, url: String, memo: String?, memoRedacted: Bool, status: ReportStatus,
         createdAt: Date, validatedAt: Date?, appliedAt: Date?, serverId: String? = nil) {
        self.id = id; self.url = url; self.memo = memo; self.memoRedacted = memoRedacted
        self.status = status; self.createdAt = createdAt
        self.validatedAt = validatedAt; self.appliedAt = appliedAt; self.serverId = serverId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.url = try c.decode(String.self, forKey: .url)
        self.memo = try c.decodeIfPresent(String.self, forKey: .memo)
        self.memoRedacted = try c.decode(Bool.self, forKey: .memoRedacted)
        self.status = try c.decode(ReportStatus.self, forKey: .status)
        let createdTs = try c.decode(Int64.self, forKey: .createdAt)
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(createdTs))
        if let validatedTs = try c.decodeIfPresent(Int64.self, forKey: .validatedAt) {
            self.validatedAt = Date(timeIntervalSince1970: TimeInterval(validatedTs))
        } else { self.validatedAt = nil }
        if let appliedTs = try c.decodeIfPresent(Int64.self, forKey: .appliedAt) {
            self.appliedAt = Date(timeIntervalSince1970: TimeInterval(appliedTs))
        } else { self.appliedAt = nil }
        // 4.3 以前の履歴には `server_id` キー自体が存在しない。無ければ nil（fail-safe）。
        self.serverId = try c.decodeIfPresent(String.self, forKey: .serverId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(memo, forKey: .memo)
        try c.encode(memoRedacted, forKey: .memoRedacted)
        try c.encode(status, forKey: .status)
        try c.encode(Int64(createdAt.timeIntervalSince1970), forKey: .createdAt)
        try c.encodeIfPresent(validatedAt.map { Int64($0.timeIntervalSince1970) }, forKey: .validatedAt)
        try c.encodeIfPresent(appliedAt.map { Int64($0.timeIntervalSince1970) }, forKey: .appliedAt)
        try c.encodeIfPresent(serverId, forKey: .serverId)
    }

    /// 週次判定結果の反映用: id/url 等はそのままに status だけ差し替えたコピーを作る。
    func withStatus(_ newStatus: ReportStatus) -> ReportHistoryItem {
        ReportHistoryItem(id: id, url: url, memo: memo, memoRedacted: memoRedacted, status: newStatus,
                          createdAt: createdAt, validatedAt: validatedAt, appliedAt: appliedAt, serverId: serverId)
    }
}
