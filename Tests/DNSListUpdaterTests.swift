import XCTest
@testable import AdblockKeshi

/// DNSListUpdater（CDN self-fetch: manifest 比較 → sha 検証 → App Group 書込）のテスト。
/// ネットワークは fetch closure 注入でモック。
final class DNSListUpdaterTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dnsupd-\(UUID().uuidString).json")
    }

    private func manifestData(sha: String, bytes: Int) -> Data {
        Data("{\"dns-rules_sha256\":\"\(sha)\",\"dns-rules_bytes\":\(bytes)}".utf8)
    }

    private func makeUpdater(manifest: Data, rules: Data, rulesURL: URL, appliedURL: URL) -> DNSListUpdater {
        DNSListUpdater(
            manifestURL: URL(string: "https://cdn.example/version-dns.json")!,
            rulesURL: URL(string: "https://cdn.example/dns-rules.json")!,
            appGroupRulesURL: rulesURL,
            appliedRecordURL: appliedURL,
            fetch: { url in
                url.absoluteString.hasSuffix("version-dns.json") ? manifest : rules
            })
    }

    func test_applies_whenShaDiffers_thenSkipsWhenMatches() async throws {
        let rules = try JSONEncoder().encode(["doubleclick.net", "ads.example.com"])
        let manifest = manifestData(sha: DNSListUpdater.sha256Hex(rules), bytes: rules.count)
        let rulesURL = tempURL(); let appliedURL = tempURL()
        defer { try? FileManager.default.removeItem(at: rulesURL); try? FileManager.default.removeItem(at: appliedURL) }
        let updater = makeUpdater(manifest: manifest, rules: rules, rulesURL: rulesURL, appliedURL: appliedURL)

        let did = await updater.updateIfNeeded()
        XCTAssertTrue(did, "初回は sha 差分で適用")
        XCTAssertEqual(try? Data(contentsOf: rulesURL), rules, "App Group に書かれる")

        let did2 = await updater.updateIfNeeded()
        XCTAssertFalse(did2, "2回目は sha 一致で skip（二重 DL 回避）")
    }

    func test_rejects_whenShaMismatch() async throws {
        let rules = try JSONEncoder().encode(["ads.example.com"])
        let manifest = manifestData(sha: "deadbeefdeadbeef", bytes: rules.count)   // 宣言 sha が実体と不一致
        let rulesURL = tempURL(); let appliedURL = tempURL()
        defer { try? FileManager.default.removeItem(at: rulesURL); try? FileManager.default.removeItem(at: appliedURL) }
        let updater = makeUpdater(manifest: manifest, rules: rules, rulesURL: rulesURL, appliedURL: appliedURL)

        let did = await updater.updateIfNeeded()
        XCTAssertFalse(did, "sha 不一致は破棄")
        XCTAssertNil(try? Data(contentsOf: rulesURL), "改竄/破損は書き込まない")
    }

    func test_rejects_whenRulesNotJSONArray() async throws {
        let rules = Data("{\"not\":\"an array\"}".utf8)
        let manifest = manifestData(sha: DNSListUpdater.sha256Hex(rules), bytes: rules.count)
        let rulesURL = tempURL(); let appliedURL = tempURL()
        defer { try? FileManager.default.removeItem(at: rulesURL); try? FileManager.default.removeItem(at: appliedURL) }
        let updater = makeUpdater(manifest: manifest, rules: rules, rulesURL: rulesURL, appliedURL: appliedURL)

        let did = await updater.updateIfNeeded()
        XCTAssertFalse(did, "ドメイン配列でない payload は破棄")
        XCTAssertNil(try? Data(contentsOf: rulesURL))
    }
}
