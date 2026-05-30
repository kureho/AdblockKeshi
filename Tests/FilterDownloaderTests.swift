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
