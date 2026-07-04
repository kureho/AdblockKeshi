import XCTest
@testable import AdblockKeshi

/// RuleUpdater の統合テスト（ネットワークは fetch closure 注入でスタブ・実 CDN には出ない）。
/// 検証: 差分 variant のみ DL / sha256 検証 / ルール数ガード / atomic write / 適用記録 /
/// 失敗時に既存ルール維持 / 旧 22MB blockerList.json の掃除 / reload 発火。
final class RuleUpdaterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rule-updater-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - fixture helpers

    private static let cdn = "https://kureho.github.io/AdblockKeshi/cdn"

    /// ルール n 件の Content Blocker JSON payload を作る。
    private func rulesPayload(count: Int, marker: String = "example.com") -> Data {
        let rule = #"{"trigger":{"url-filter":"\#(marker)"},"action":{"type":"block"}}"#
        let body = Array(repeating: rule, count: count).joined(separator: ",")
        return Data("[\(body)]".utf8)
    }

    /// payload 群から CDN manifest（version.json / version-security.json）を組み立てる。
    private func manifests(
        ad: Data, merged: Data, security: Data, empty: Data = Data("[]".utf8)
    ) -> (version: Data, versionSecurity: Data) {
        let version = Data("""
        {
          "generated_at": "2026-07-01T07:06:49Z",
          "rule_count": 150000,
          "blocker_list_sha256": "\(RuleUpdatePlanner.sha256Hex(ad))",
          "reported": {"rule_count": 3, "added_last_month": 1}
        }
        """.utf8)
        let versionSecurity = Data("""
        {
          "security-rules_sha256": "\(RuleUpdatePlanner.sha256Hex(security))",
          "merged-rules_sha256": "\(RuleUpdatePlanner.sha256Hex(merged))",
          "empty-rules_sha256": "\(RuleUpdatePlanner.sha256Hex(empty))",
          "generated_at": "2026-06-28T02:05:04.311961Z"
        }
        """.utf8)
        return (version, versionSecurity)
    }

    /// URL → response data のスタブ fetch。呼ばれた URL を記録する。
    private final class FetchStub: @unchecked Sendable {
        var responses: [String: Data]
        private(set) var requested: [String] = []
        private let lock = NSLock()

        init(_ responses: [String: Data]) { self.responses = responses }

        func fetch(_ url: URL) async throws -> Data {
            lock.lock()
            requested.append(url.absoluteString)
            lock.unlock()
            guard let data = responses[url.absoluteString] else {
                throw NSError(domain: "FetchStub", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "no stub for \(url)"])
            }
            return data
        }
    }

    private final class ReloadSpy: @unchecked Sendable {
        private(set) var count = 0
        private let lock = NSLock()
        func reload() { lock.lock(); count += 1; lock.unlock() }
    }

    private func makeUpdater(
        stub: FetchStub,
        reloadSpy: ReloadSpy? = nil,
        bundledFileURL: @escaping @Sendable (String) -> URL? = { _ in nil }
    ) -> RuleUpdater {
        RuleUpdater(
            directory: tempDir,
            fetch: { url in try await stub.fetch(url) },
            bundledFileURL: bundledFileURL,
            reload: reloadSpy.map { spy in { spy.reload() } }
        )
    }

    private func stubAllEndpoints(
        ad: Data, merged: Data, security: Data, empty: Data = Data("[]".utf8)
    ) -> FetchStub {
        let m = manifests(ad: ad, merged: merged, security: security, empty: empty)
        return FetchStub([
            "\(Self.cdn)/version.json": m.version,
            "\(Self.cdn)/version-security.json": m.versionSecurity,
            "\(Self.cdn)/blockerList.json": ad,
            "\(Self.cdn)/merged-rules.json": merged,
            "\(Self.cdn)/security-rules.json": security,
            "\(Self.cdn)/empty-rules.json": empty,
        ])
    }

    // MARK: - 適用（DL → 検証 → atomic write → 記録 → reload）

    func test_applies_all_variants_on_first_run_and_reloads() async throws {
        let ad = rulesPayload(count: 150_000, marker: "ad.example")
        let merged = rulesPayload(count: 130_000, marker: "merged.example")
        let security = rulesPayload(count: 30_000, marker: "sec.example")
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        let spy = ReloadSpy()
        let updater = makeUpdater(stub: stub, reloadSpy: spy)

        let outcome = try await updater.updateIfNeeded()

        XCTAssertEqual(Set(outcome.applied),
                       ["ad-rules.json", "merged-rules.json", "security-rules.json", "empty-rules.json"])
        XCTAssertTrue(outcome.failed.isEmpty)
        // App Group（temp dir）に variant ファイルが書かれ、内容が CDN payload と一致
        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("ad-rules.json")), ad)
        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("merged-rules.json")), merged)
        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("security-rules.json")), security)
        // 適用記録（sha / ルール数 / generated_at）が残る
        let records = AppliedRulesStore(directory: tempDir).read()
        XCTAssertEqual(records["merged-rules.json"]?.sha256, RuleUpdatePlanner.sha256Hex(merged))
        XCTAssertEqual(records["merged-rules.json"]?.ruleCount, 130_000)
        XCTAssertEqual(records["ad-rules.json"]?.ruleCount, 150_000)
        // 変化があったので reload は 1 回だけ
        XCTAssertEqual(spy.count, 1)
        XCTAssertTrue(outcome.reloaded)
    }

    func test_skips_variants_when_sha_matches_record_and_downloads_nothing() async throws {
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        let spy = ReloadSpy()
        // 1 回目で適用
        _ = try await makeUpdater(stub: stub).updateIfNeeded()
        // 2 回目: sha 一致 → variant DL ゼロ・reload なし
        let secondStub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        let outcome = try await makeUpdater(stub: secondStub, reloadSpy: spy).updateIfNeeded()

        XCTAssertEqual(Set(outcome.skipped),
                       ["ad-rules.json", "merged-rules.json", "security-rules.json", "empty-rules.json"])
        XCTAssertTrue(outcome.applied.isEmpty)
        XCTAssertEqual(spy.count, 0)
        XCTAssertFalse(outcome.reloaded)
        // manifest 2 本以外に何も取得していない（22MB 常時 DL の廃止を担保）
        XCTAssertEqual(
            Set(secondStub.requested),
            ["\(Self.cdn)/version.json", "\(Self.cdn)/version-security.json"]
        )
    }

    func test_updates_only_changed_variant() async throws {
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        _ = try await makeUpdater(stub: stubAllEndpoints(ad: ad, merged: merged, security: security))
            .updateIfNeeded()

        // security だけ更新された CDN 状態
        let newSecurity = rulesPayload(count: 29_000, marker: "sec2.example")
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: newSecurity)
        let outcome = try await makeUpdater(stub: stub).updateIfNeeded()

        XCTAssertEqual(outcome.applied, ["security-rules.json"])
        XCTAssertTrue(stub.requested.contains("\(Self.cdn)/security-rules.json"))
        XCTAssertFalse(stub.requested.contains("\(Self.cdn)/blockerList.json"))
        XCTAssertFalse(stub.requested.contains("\(Self.cdn)/merged-rules.json"))
    }

    // MARK: - 検証失敗時は既存ルールを維持

    func test_sha_mismatch_rejects_payload_and_keeps_existing_file() async throws {
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        _ = try await makeUpdater(stub: stubAllEndpoints(ad: ad, merged: merged, security: security))
            .updateIfNeeded()

        // manifest は新 sha を宣言するが、配信 payload が改ざんされている（sha 不一致）
        let genuine = rulesPayload(count: 30_000, marker: "sec-new.example")
        let tampered = rulesPayload(count: 30_000, marker: "evil.example")
        let m = manifests(ad: ad, merged: merged, security: genuine)
        let stub = FetchStub([
            "\(Self.cdn)/version.json": m.version,
            "\(Self.cdn)/version-security.json": m.versionSecurity,
            "\(Self.cdn)/security-rules.json": tampered,
        ])
        let spy = ReloadSpy()
        let outcome = try await makeUpdater(stub: stub, reloadSpy: spy).updateIfNeeded()

        XCTAssertEqual(outcome.failed, ["security-rules.json"])
        // 既存ファイル・記録は旧内容のまま（App Group を壊さない）
        XCTAssertEqual(
            try Data(contentsOf: tempDir.appendingPathComponent("security-rules.json")), security)
        XCTAssertEqual(
            AppliedRulesStore(directory: tempDir).read()["security-rules.json"]?.sha256,
            RuleUpdatePlanner.sha256Hex(security))
        XCTAssertEqual(spy.count, 0)
    }

    func test_rule_count_below_half_of_past_actual_is_rejected() async throws {
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        _ = try await makeUpdater(stub: stubAllEndpoints(ad: ad, merged: merged, security: security))
            .updateIfNeeded()

        // 過去実績 30,000 の 50% 未満（14,999 件）→ 拒否して既存維持
        let shrunk = rulesPayload(count: 14_999, marker: "sec-shrunk.example")
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: shrunk)
        let outcome = try await makeUpdater(stub: stub).updateIfNeeded()

        XCTAssertEqual(outcome.failed, ["security-rules.json"])
        XCTAssertEqual(
            try Data(contentsOf: tempDir.appendingPathComponent("security-rules.json")), security)
    }

    func test_rule_count_above_webkit_limit_is_rejected() async throws {
        let ad = rulesPayload(count: 150_001)  // WebKit 上限 150,000 超
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        let outcome = try await makeUpdater(stub: stub).updateIfNeeded()

        XCTAssertTrue(outcome.failed.contains("ad-rules.json"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("ad-rules.json").path))
    }

    func test_non_array_json_payload_is_rejected() async throws {
        let ad = Data(#"{"not": "an array"}"#.utf8)  // sha は一致させる（manifest から計算）
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        let outcome = try await makeUpdater(stub: stub).updateIfNeeded()

        XCTAssertTrue(outcome.failed.contains("ad-rules.json"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("ad-rules.json").path))
    }

    func test_manifest_fetch_failure_throws_and_keeps_everything() async throws {
        let stub = FetchStub([:])  // version.json すら取れない（オフライン相当）
        let updater = makeUpdater(stub: stub)
        do {
            _ = try await updater.updateIfNeeded()
            XCTFail("should throw")
        } catch {
            // 既存ファイルには触っていない（bundle fallback チェーンが生きる）
            XCTAssertEqual(AppliedRulesStore(directory: tempDir).read(), [:])
        }
    }

    // MARK: - bundle 一致なら DL せず記録のみ（新規インストール直後の無駄 DL 回避）

    func test_records_without_download_when_bundled_content_matches_cdn() async throws {
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        let empty = Data("[]".utf8)
        // 「bundle 同梱ファイル」を temp に用意して bundledFileURL で注入
        let bundleDir = tempDir.appendingPathComponent("fake-bundle")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        for (name, data) in ["ad-rules.json": ad, "merged-rules.json": merged,
                             "security-rules.json": security, "empty-rules.json": empty] {
            try data.write(to: bundleDir.appendingPathComponent(name))
        }
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        let spy = ReloadSpy()
        let updater = makeUpdater(stub: stub, reloadSpy: spy) { name in
            bundleDir.appendingPathComponent(name)
        }

        let outcome = try await updater.updateIfNeeded()

        XCTAssertEqual(Set(outcome.recordedWithoutDownload),
                       ["ad-rules.json", "merged-rules.json", "security-rules.json", "empty-rules.json"])
        XCTAssertTrue(outcome.applied.isEmpty)
        // variant の DL は発生しない（manifest 2 本のみ）
        XCTAssertEqual(
            Set(stub.requested),
            ["\(Self.cdn)/version.json", "\(Self.cdn)/version-security.json"])
        // 内容不変なので reload も不要
        XCTAssertEqual(spy.count, 0)
        // 記録は残る（次回以降は sha 比較のみで済む）
        XCTAssertEqual(
            AppliedRulesStore(directory: tempDir).read()["merged-rules.json"]?.sha256,
            RuleUpdatePlanner.sha256Hex(merged))
    }

    // MARK: - 旧 22MB blockerList.json の掃除

    func test_removes_legacy_blockerList_from_app_group() async throws {
        // 旧実装が App Group に残した 22MB 相当のファイル（読む者がいない）
        try Data("legacy".utf8).write(to: tempDir.appendingPathComponent("blockerList.json"))
        try Data("legacy-combined".utf8).write(
            to: tempDir.appendingPathComponent("combined-blockerList.json"))
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        _ = try await makeUpdater(stub: stubAllEndpoints(ad: ad, merged: merged, security: security))
            .updateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("blockerList.json").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("combined-blockerList.json").path))
    }

    // MARK: - version.json の App Group 同期（moat 表示用・表示日付には使わない）

    func test_writes_cdn_version_json_to_app_group() async throws {
        let ad = rulesPayload(count: 150_000)
        let merged = rulesPayload(count: 130_000)
        let security = rulesPayload(count: 30_000)
        let stub = stubAllEndpoints(ad: ad, merged: merged, security: security)
        _ = try await makeUpdater(stub: stub).updateIfNeeded()

        let written = try Data(contentsOf: tempDir.appendingPathComponent("version.json"))
        XCTAssertEqual(written, stub.responses["\(Self.cdn)/version.json"])
    }

    // MARK: - 既定エンドポイント

    func test_default_endpoints_are_github_pages_manifests() {
        XCTAssertEqual(
            RuleUpdater.defaultVersionURL.absoluteString,
            "https://kureho.github.io/AdblockKeshi/cdn/version.json")
        XCTAssertEqual(
            RuleUpdater.defaultVersionSecurityURL.absoluteString,
            "https://kureho.github.io/AdblockKeshi/cdn/version-security.json")
    }
}
