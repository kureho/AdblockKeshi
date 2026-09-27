import Foundation
import SwiftUI

/// 端末ローカルで報告履歴を保持する store。
///
/// 「URL のみ送信・完全匿名」の運用方針上、サーバー側に UUID 紐付きの履歴を
/// 保持できないため、送信成功時に端末側へ append する。`ReportHistoryItem` 単位で
/// id（UUID 文字列）を付け、swipe 削除はその id で remove する。
@MainActor
final class LocalReportHistoryStore: ObservableObject {
    static let storageKey = "v3.report.history.local.v1"
    /// A-88 §3: 前回「結果を取りに行った」時刻。連打・頻繁な再取得を避けるための throttle に使う。
    private static let lastStatusRefreshKey = "v3.report.history.statusRefresh.v1"
    /// 1 回のリクエストで問い合わせる ID 数（サーバー側 `POST /v1/reports/status` の上限＝設計 §3）。
    private static let statusFetchBatchSize = 20

    @Published private(set) var items: [ReportHistoryItem] = []

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 満足度カードの実績表示用: 永続化済みの報告履歴件数を副作用なしで読む。
    /// store を生成せず UserDefaults を直接 decode する（read-only）。
    static func persistedCount(defaults: UserDefaults = .standard) -> Int {
        guard let data = defaults.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([ReportHistoryItem].self, from: data)
        else { return 0 }
        return items.count
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.items = loadFromDisk()
    }

    /// 報告送信成功時に呼ぶ。新しい行は先頭へ。
    /// - Parameter serverId: サーバーが返した報告 ID。週次判定結果の問い合わせに使う
    ///   （A-88 §1・§3）。4.3 以前と同じ経路のテスト・呼び出しを壊さないよう既定は nil。
    func append(url: URL, memo: String?, status: ReportStatus = .pending, serverId: String? = nil) {
        let item = ReportHistoryItem(
            id: UUID().uuidString,
            url: url.absoluteString,
            memo: memo,
            memoRedacted: false,
            status: status,
            createdAt: Date(),
            validatedAt: nil,
            // D-lite: 送信直後に端末へ反映されることはないので、appliedAt は常に nil で始まる。
            appliedAt: nil,
            serverId: serverId
        )
        items.insert(item, at: 0)
        persist()
    }

    /// A-88 §3・進め方4: 履歴を開いたときに呼ぶ。serverId のある行だけ結果を取りに行き、
    /// 状態を更新して保存する。
    /// - 連打・頻繁な再取得を避けるため、前回取得から `minInterval` 以内は何もしない
    ///   （既定 10 分。値は目安として妥当な範囲であればよい、という設計上の余地に対する判断）。
    /// - 通信失敗は例外を投げずに「今の表示のまま」にする（`fetchReportOutcomes` が投げた
    ///   場合もここで catch し、他の行の更新やエラー伝播をしない＝1 バッチの失敗が全体を壊さない）。
    /// - 1 回 20 件までのサーバー制約に合わせ、対象を chunk して複数回に分けて呼ぶ。
    func refreshStatuses(apiClient: ReportAPIClientProtocol, now: Date = Date(),
                         minInterval: TimeInterval = 600) async {
        if let last = lastStatusRefreshAt, now.timeIntervalSince(last) < minInterval { return }
        lastStatusRefreshAt = now

        let targets = items.filter { $0.serverId != nil }
        guard !targets.isEmpty else { return }
        let serverIds = targets.compactMap(\.serverId)

        var outcomeByServerId: [String: String] = [:]
        for batch in serverIds.chunked(into: Self.statusFetchBatchSize) {
            do {
                let results = try await apiClient.fetchReportOutcomes(ids: batch)
                for result in results { outcomeByServerId[result.id] = result.outcome }
            } catch {
                // 通信失敗は黙って今の表示のまま。他バッチの取得は続ける。
                continue
            }
        }
        guard !outcomeByServerId.isEmpty else { return }

        items = items.map { item in
            guard let serverId = item.serverId,
                  let outcome = outcomeByServerId[serverId],
                  let newStatus = ReportStatus.fromServerOutcome(outcome)
            else { return item }
            return item.withStatus(newStatus)
        }
        persist()
    }

    /// swipe 削除のための index 削除。
    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    /// id 指定削除（将来のため。テスト等で利用）。
    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    // MARK: - private

    /// UserDefaults 直読み書き（Date は plist 互換で素直に扱える）。
    private var lastStatusRefreshAt: Date? {
        get { defaults.object(forKey: Self.lastStatusRefreshKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastStatusRefreshKey) }
    }

    private func persist() {
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func loadFromDisk() -> [ReportHistoryItem] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([ReportHistoryItem].self, from: data)
        else { return [] }
        return decoded
    }
}

private extension Array {
    /// A-88 §3: サーバーの 1 回 20 件までの制約に合わせて分割する。
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#if DEBUG
extension LocalReportHistoryStore {
    /// A-88 検証用: 起動引数 `--seed-report-history-fixtures` から呼ぶ固定データ投入。
    /// 本番ビルドには含まれない（#if DEBUG）。全状態のスクリーンショットを撮るためのもの。
    /// `refreshStatuses` の throttle も「たった今取得済み」にしておき、実ネットワークへ
    /// 問い合わせて表示が変わらないようにする（撮影の再現性のため）。
    static func seedFixturesForUITesting(defaults: UserDefaults = .standard) {
        let now = Date()
        let items: [ReportHistoryItem] = [
            ReportHistoryItem(id: "fixture-checking", url: "https://checking.example.com/news/page1",
                              memo: nil, memoRedacted: false, status: .checking,
                              createdAt: now, validatedAt: nil, appliedAt: nil, serverId: "s-checking"),
            ReportHistoryItem(id: "fixture-applied", url: "https://applied.example.com/article",
                              memo: "記事下の広告が消えませんでした", memoRedacted: false, status: .approved,
                              createdAt: now, validatedAt: nil, appliedAt: now, serverId: "s-applied"),
            ReportHistoryItem(id: "fixture-inappad", url: "https://inappad.example.com/video",
                              memo: nil, memoRedacted: false, status: .inAppAd,
                              createdAt: now, validatedAt: nil, appliedAt: nil, serverId: "s-inappad"),
            ReportHistoryItem(id: "fixture-siteownad", url: "https://siteownad.example.com/matome",
                              memo: nil, memoRedacted: false, status: .siteOwnAd,
                              createdAt: now, validatedAt: nil, appliedAt: nil, serverId: "s-siteownad"),
            ReportHistoryItem(id: "fixture-declined", url: "https://declined.example.com/page2",
                              memo: nil, memoRedacted: false, status: .declined,
                              createdAt: now, validatedAt: nil, appliedAt: nil, serverId: "s-declined"),
            // 4.3 以前に送った報告＝ server_id が無く、結果を問い合わせられないので「受付済」のまま。
            ReportHistoryItem(id: "fixture-legacy", url: "https://legacy.example.com/old-report",
                              memo: nil, memoRedacted: false, status: .pending,
                              createdAt: now, validatedAt: nil, appliedAt: nil, serverId: nil),
        ]
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
        defaults.set(now, forKey: lastStatusRefreshKey)
    }
}
#endif
