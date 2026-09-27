import XCTest
@testable import AdblockKeshi

/// A-88 §3・進め方4: 履歴を開いたときに serverId のある行だけ結果を取りに行き、
/// 状態を更新して保存する。連打・頻繁な再取得を避ける／通信失敗は黙って今の表示を保つ。
@MainActor
final class LocalReportHistoryStoreStatusRefreshTests: XCTestCase {

    /// 呼ばれた ids のバッチを記録し、注入した結果 or エラーを返すだけのスタブ。
    private final class StubOutcomeClient: ReportAPIClientProtocol, @unchecked Sendable {
        private(set) var calledBatches: [[String]] = []
        var outcomesByServerId: [String: String] = [:]
        var errorToThrow: Error?

        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws -> String {
            UUID().uuidString
        }
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}

        func fetchReportOutcomes(ids: [String]) async throws -> [ReportOutcomeResult] {
            calledBatches.append(ids)
            if let errorToThrow { throw errorToThrow }
            return ids.compactMap { id in
                outcomesByServerId[id].map { ReportOutcomeResult(id: id, outcome: $0) }
            }
        }
    }

    private func makeStore(suiteName: String = UUID().uuidString) -> (LocalReportHistoryStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (LocalReportHistoryStore(defaults: defaults), defaults)
    }

    func test_refresh_updatesOnlyItemsWithServerId() async {
        let (store, _) = makeStore()
        store.append(url: URL(string: "https://a.example.com")!, memo: nil, serverId: "s1")
        store.append(url: URL(string: "https://b.example.com")!, memo: nil, serverId: nil)

        let client = StubOutcomeClient()
        client.outcomesByServerId = ["s1": "applied"]

        await store.refreshStatuses(apiClient: client)

        let a = store.items.first { $0.url == "https://a.example.com" }
        let b = store.items.first { $0.url == "https://b.example.com" }
        XCTAssertEqual(a?.status, .approved, "applied は approved（反映済）に丸める")
        XCTAssertEqual(b?.status, .pending, "serverId の無い行は問い合わせず受付済のまま")
        XCTAssertEqual(client.calledBatches, [["s1"]], "serverId のある行だけを問い合わせる")
    }

    func test_refresh_persistsUpdatedStatus_acrossInstances() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LocalReportHistoryStore(defaults: defaults)
        store.append(url: URL(string: "https://persist.example.com")!, memo: nil, serverId: "s9")

        let client = StubOutcomeClient()
        client.outcomesByServerId = ["s9": "declined"]
        await store.refreshStatuses(apiClient: client)

        let reloaded = LocalReportHistoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.items.first?.status, .declined)
    }

    func test_refresh_batchesInChunksOf20() async {
        let (store, _) = makeStore()
        for i in 0..<45 {
            store.append(url: URL(string: "https://example.com/\(i)")!, memo: nil, serverId: "s\(i)")
        }
        let client = StubOutcomeClient()

        await store.refreshStatuses(apiClient: client)

        XCTAssertEqual(client.calledBatches.count, 3, "45 件は 20/20/5 の 3 バッチに分ける")
        XCTAssertTrue(client.calledBatches.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(client.calledBatches.map(\.count).reduce(0, +), 45)
    }

    func test_refresh_withinMinInterval_doesNotCallClientAgain() async {
        let (store, _) = makeStore()
        store.append(url: URL(string: "https://a.example.com")!, memo: nil, serverId: "s1")
        let client = StubOutcomeClient()
        client.outcomesByServerId = ["s1": "checking"]

        let now = Date()
        await store.refreshStatuses(apiClient: client, now: now, minInterval: 600)
        XCTAssertEqual(client.calledBatches.count, 1)

        // 5 分後の再取得（連打・タブ往復）は問い合わせない。
        await store.refreshStatuses(apiClient: client, now: now.addingTimeInterval(300), minInterval: 600)
        XCTAssertEqual(client.calledBatches.count, 1, "前回取得から min interval 以内は問い合わせない")

        // min interval を過ぎたら再度問い合わせる。
        await store.refreshStatuses(apiClient: client, now: now.addingTimeInterval(601), minInterval: 600)
        XCTAssertEqual(client.calledBatches.count, 2)
    }

    func test_refresh_onNetworkFailure_keepsCurrentDisplay_silently() async {
        let (store, _) = makeStore()
        store.append(url: URL(string: "https://a.example.com")!, memo: nil, serverId: "s1")
        let client = StubOutcomeClient()
        client.errorToThrow = APIError.networkUnavailable

        await store.refreshStatuses(apiClient: client)

        XCTAssertEqual(store.items.first?.status, .pending, "通信失敗時は今の表示のまま変えない")
    }
}
