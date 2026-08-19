import XCTest
@testable import AdblockKeshi

/// ★D-lite の中核の回帰ガード。
///
/// 報告しても、その端末の自己ブロックリストへは**何も書かれない**。
/// 4.0.2 までは報告した host が DNS 自己リストへ入り、報告先サイトが名前解決不能になっていた
/// （v4.0.3 hotfix の原因）。Content Blocker 側も同様に自己リストへ追記していた。
/// ここでは実 App Group コンテナのファイルを送信前後で比較して、増えていないことを確かめる。
@MainActor
final class SubmitDoesNotWriteSelfListsTests: XCTestCase {

    private let appGroup = "group.com.kureho.adblockkeshi.shared"

    private final class StubClient: ReportAPIClientProtocol, @unchecked Sendable {
        private(set) var submitted = 0
        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {
            submitted += 1
        }
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    private func snapshot(_ container: URL, _ filename: String) -> Data? {
        try? Data(contentsOf: container.appendingPathComponent(filename))
    }

    func test_successfulSubmit_doesNotTouchSelfBlockLists() async throws {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else {
            throw XCTSkip("App Group コンテナがこのテストホストで利用不可")
        }

        let watched = [
            SelfReportedRulesStore.selfFilename,   // rules-self.json
            SelfReportedRulesStore.mergedFilename, // rules-reported.json
            DNSSelfReportStore.filename,           // dns-self.json
        ]
        let before = watched.map { snapshot(container, $0) }

        let client = StubClient()
        let vm = ReportFormViewModel(apiClient: client, onSuccess: { _ in })
        // 報告先が「広告配信元」ではなく「閲覧していたページ」でも同じ。
        vm.urlInput = "https://ads.example.com/banner"
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(client.submitted, 1, "前提: 送信自体は成功している")

        let after = watched.map { snapshot(container, $0) }
        for (index, filename) in watched.enumerated() {
            XCTAssertEqual(before[index], after[index],
                           "\(filename) が報告によって書き換わっている（自己ブロックが復活している）")
        }
    }

    /// DNS 自己リストの供給経路が存在しないこと（tunnel は curated のみを読む）。
    func test_dnsSelfReportStore_hasNoWriteAPI_onlyPurge() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try Data("[\"ads.example.com\"]".utf8).write(to: url)
        let store = DNSSelfReportStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(store.readDomains(), ["ads.example.com"], "前提: 旧端末の残骸を読める")
        XCTAssertTrue(try store.purge(), "残骸は purge で消える")
        XCTAssertTrue(store.readDomains().isEmpty)
    }
}
