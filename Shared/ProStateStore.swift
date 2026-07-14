import Foundation

/// Pro 状態（買い切り or grandfather の結果）を表す。
/// Main App が書き、tunnel(PacketTunnelProvider) が起動時に読む（App Group 共有）。
struct ProState: Equatable, Codable {
    let isPro: Bool
    let updatedAt: Date

    init(isPro: Bool = false, updatedAt: Date = Date()) {
        self.isPro = isPro
        self.updatedAt = updatedAt
    }

    /// 不正 JSON / 未存在時の fail-safe = **非 Pro**（StateStore と逆向き）。
    /// Pro 機能は過少付与に倒す（無権利ユーザーに tunnel を渡さない）。
    static let `default` = ProState(isPro: false)
}

/// App Group container 上の pro-state.json を atomic に読み書きする store。
/// StateStore と同型（Shared/ に置くのは tunnel extension からも読むため）。
struct ProStateStore {
    let stateFileURL: URL

    init(stateFileURL: URL) {
        self.stateFileURL = stateFileURL
    }

    /// App Group container の pro-state.json を指す convenience initializer。
    static func sharedAppGroup(
        identifier: String = "group.com.kureho.adblockkeshi.shared"
    ) -> ProStateStore? {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return ProStateStore(stateFileURL: container.appendingPathComponent("pro-state.json"))
    }

    /// 不正 JSON / 未存在なら非 Pro を返す（fail-safe）。
    func read() -> ProState {
        guard let data = try? Data(contentsOf: stateFileURL) else { return .default }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(ProState.self, from: data) else { return .default }
        return state
    }

    /// atomic write（tunnel が中途半端な JSON を読まないよう `.atomic` 必須）。
    func write(_ state: ProState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
    }
}
