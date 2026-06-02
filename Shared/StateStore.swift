import Foundation

/// v2.0 で導入。広告ブロック / セキュリティブロック 2 トグルの状態を表す。
/// Main App と Content Blocker Extension の両方から App Group 経由で読まれる。
struct BlockerTogglesState: Equatable, Codable {
    let adEnabled: Bool
    let securityEnabled: Bool
    let updatedAt: Date

    init(adEnabled: Bool = true, securityEnabled: Bool = true, updatedAt: Date = Date()) {
        self.adEnabled = adEnabled
        self.securityEnabled = securityEnabled
        self.updatedAt = updatedAt
    }

    /// 不正 JSON / 未存在時の fail-safe デフォルト = 両方 ON。
    /// ユーザー体験を壊さないためにブロック側に倒す。
    static let `default` = BlockerTogglesState()
}

/// App Group container 上の state.json を atomic に読み書きする store。
/// Main App とコンテンツブロッカー Extension の両方から使う。
struct StateStore {
    let stateFileURL: URL

    init(stateFileURL: URL) {
        self.stateFileURL = stateFileURL
    }

    /// App Group container の state.json を指す convenience initializer。
    /// container が取れない（entitlement 不備等）なら nil。
    static func sharedAppGroup(
        identifier: String = "group.com.kureho.adblockkeshi.shared"
    ) -> StateStore? {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return StateStore(stateFileURL: container.appendingPathComponent("state.json"))
    }

    /// 不正 JSON / 未存在ならデフォルト（両方 ON）を返す（fail-safe）。
    /// Extension 側でこのメソッドが失敗してもブロック動作は継続する。
    func read() -> BlockerTogglesState {
        guard let data = try? Data(contentsOf: stateFileURL) else { return .default }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(BlockerTogglesState.self, from: data) else {
            return .default
        }
        return state
    }

    /// atomic write。Extension が中途半端な JSON を読まないように `.atomic` 必須。
    func write(_ state: BlockerTogglesState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
    }
}
