import XCTest
@testable import AdblockKeshi

final class FilterDownloaderTests: XCTestCase {

    func test_default_endpoints_are_github_pages() async {
        let downloader = FilterDownloader()
        let url = await downloader.blockerListURL.absoluteString
        let versionUrl = await downloader.versionURL.absoluteString
        XCTAssertTrue(url.hasPrefix("https://kureho.github.io/AdblockKeshi/cdn/"))
        XCTAssertTrue(versionUrl.hasPrefix("https://kureho.github.io/AdblockKeshi/cdn/"))
        XCTAssertTrue(url.hasSuffix("blockerList.json"))
        XCTAssertTrue(versionUrl.hasSuffix("version.json"))
    }

    func test_default_app_group_matches_extension() async {
        let downloader = FilterDownloader()
        let id = await downloader.appGroupIdentifier
        XCTAssertEqual(id, "group.com.kureho.adblockkeshi.shared")
    }

    func test_syncsVersion_defaults_true_and_can_opt_out() async {
        // 既定は version 同期 ON（本体フィルタの後方互換）。
        let dflt = FilterDownloader()
        let on = await dflt.syncsVersion
        XCTAssertTrue(on)
        // popunder 等の2つ目インスタンスは version 同期 OFF にして
        // 共有 App Group の version.json（本体「最終更新日」UI）の上書きを避ける。
        let off = FilterDownloader(syncsVersion: false)
        let isOff = await off.syncsVersion
        XCTAssertFalse(isOff)
    }

    /// 前面復帰のたびに取得する。中身が変わるときだけ、書き込みの前に知らせる
    /// （呼び出し側が「読み込みが要る」印を付ける。同じ中身なら Safari に読み込み直させない）。
    func test_中身が変わるときだけ_書き込みの前に知らせる() async throws {
        let filename = "filter-downloader-test-\(UUID().uuidString).json"
        let container = try XCTUnwrap(FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.kureho.adblockkeshi.shared"))
        let file = container.appendingPathComponent(filename)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let downloader = FilterDownloader(
            blockerListURL: URL(string: "https://stub.example/rules.json")!,
            filename: filename, session: URLSession(configuration: config), syncsVersion: false)
        var seen: [String?] = []
        let currentContent = { (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) } }

        StubURLProtocol.body = Data("[1]".utf8)
        try await downloader.downloadAndStore(willReplace: { seen.append(currentContent()) })
        StubURLProtocol.body = Data("[1]".utf8)
        try await downloader.downloadAndStore(willReplace: { seen.append(currentContent()) })
        StubURLProtocol.body = Data("[2]".utf8)
        try await downloader.downloadAndStore(willReplace: { seen.append(currentContent()) })

        XCTAssertEqual(seen, [nil, "[1]"], "初回と中身が変わったときだけ・書き込みの前に")
        XCTAssertEqual(currentContent(), "[2]")
    }

    /// 同じ中身なら書き込まない。書くと、別の同期と重なったときに「同じ」と判断した後で古い中身を印なしで
    /// 書き戻しうる（同じ中身を書くだけの書き込みに印は付かない）。
    func test_中身が同じなら_ファイルを書き換えない() async throws {
        let filename = "filter-downloader-test-\(UUID().uuidString).json"
        let container = try XCTUnwrap(FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.kureho.adblockkeshi.shared"))
        let file = container.appendingPathComponent(filename)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let downloader = FilterDownloader(
            blockerListURL: URL(string: "https://stub.example/rules.json")!,
            filename: filename, session: URLSession(configuration: config), syncsVersion: false)
        let fileNumber = { try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int }

        StubURLProtocol.body = Data("[1]".utf8)
        try await downloader.downloadAndStore()
        let before = try fileNumber()
        StubURLProtocol.body = Data("[1]".utf8)
        let bytes = try await downloader.downloadAndStore()

        XCTAssertEqual(try fileNumber(), before, "atomic write は別のファイルに置き換わる＝番号が変わる")
        XCTAssertEqual(bytes, 3)
    }

    func test_invalid_url_throws() async {
        let downloader = FilterDownloader(
            blockerListURL: URL(string: "https://nonexistent.invalid.example/x.json")!,
            appGroupIdentifier: "group.nonexistent.test"
        )
        do {
            _ = try await downloader.downloadAndStore()
            XCTFail("should throw")
        } catch {
            // OK: ネットワークエラー or App Group エラー
            XCTAssertNotNil(error)
        }
    }
}

/// 決まった中身を 200 で返す偽の通信。
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
