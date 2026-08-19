import Foundation

/// DNS 保護の時限一時停止（App Group・`dns-pause.json`）。
///
/// v4.2.0: 「誤ブロックで困った → 全 OFF → 戻し忘れ → 効かない★1」を断つため、
/// 15分/1時間の**自動再開つき**一時停止を提供する。トンネルは止めず、
/// PacketTunnelProvider が本ストアを読んで素通しエンジンに切り替える
/// （stopTunnel 方式だとアプリ suspend 中に再開経路が消えるため）。
///
/// fail-safe: 未存在 / 不正 JSON / 期限切れはすべて「停止していない」= 保護が生きる方向。
struct DNSPauseStore {
    static let filename = "dns-pause.json"

    /// 選べる停止時間（UI とプロバイダで共有する唯一の定義）。
    enum Duration: TimeInterval, CaseIterable {
        case fifteenMinutes = 900
        case oneHour = 3600
    }

    private struct Payload: Codable {
        let pausedUntil: Date
    }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// App Group container の dns-pause.json を指す convenience initializer。
    static func sharedAppGroup(
        identifier: String = "group.com.kureho.adblockkeshi.shared"
    ) -> DNSPauseStore? {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return DNSPauseStore(fileURL: container.appendingPathComponent(filename))
    }

    /// 選べる最長の停止時間 + 時計誤差マージン。これより遠い未来の期限は異常として捨てる。
    /// 端末時計を巻き戻すと保存済みの絶対日時が「遠い未来」に化け、停止が解けないまま
    /// 保護が戻らなくなるため（v4.2.0 の反証レビューで判明）。Duration から導出して二重管理を避ける。
    private static var maxPauseWindow: TimeInterval {
        (Duration.allCases.map(\.rawValue).max() ?? 3_600) + 60
    }

    /// 有効な停止期限。期限切れ（now 以前）・未存在・不正 JSON・上限超過は nil（= 停止していない）。
    /// 期限切れファイルの削除は行わない（読み手は extension のこともあるため書き込まない。
    /// 掃除は clear() / 次の pause() が担う）。
    func readPausedUntil(now: Date = Date()) -> Date? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return nil }
        guard payload.pausedUntil > now else { return nil }
        guard payload.pausedUntil <= now.addingTimeInterval(Self.maxPauseWindow) else { return nil }
        return payload.pausedUntil
    }

    /// 停止期限を保存する（既存の期限は上書き・atomic）。
    func pause(until: Date) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Payload(pausedUntil: until))
        try data.write(to: fileURL, options: [.atomic])
    }

    /// 停止を解除する（ファイル削除・冪等）。
    func clear() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
