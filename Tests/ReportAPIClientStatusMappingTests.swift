import XCTest
@testable import AdblockKeshi

/// `ReportAPIClient` の HTTP ステータス → `APIError` マッピング契約。
///
/// 点検記録 `tasks/report-pipeline-audit-2026-09-27.md` ③: サーバは送信停止中（自動 ban）を
/// **403** で返す（`workers/src/handlers/submit.ts:123` `jsonError(403, 'banned', ...)`。
/// ワークスペース内で 403 が返る箇所はここ 1 つだけ＝grep 確認済）。
/// 修正前は `ReportAPIClient.swift` が 401/403 を一律 `.unauthorized`
/// （「認証エラーです。アプリを再起動してください」＝再起動しても直らない）にマップしていた。
final class ReportAPIClientStatusMappingTests: XCTestCase {

    /// 固定のステータス・ボディを返すだけの URLProtocol スタブ。
    private final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var statusCode = 200
        nonisolated(unsafe) static var body: Data = Data()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.statusCode,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var keychainService = ""

    override func setUp() {
        super.setUp()
        keychainService = "test.report-api-client-status-mapping.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? KeychainHelper(service: keychainService, accessGroup: nil).delete(account: DeviceUUIDStore.account)
        super.tearDown()
    }

    private func makeClient() -> ReportAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let uuidStore = DeviceUUIDStore(
            keychain: KeychainHelper(service: keychainService, accessGroup: nil),
            serverSalt: "test-salt"
        )
        return ReportAPIClient(baseURL: URL(string: "https://stub.invalid")!, session: session, uuidStore: uuidStore)
    }

    func test_403Banned_mapsToBanned_notUnauthorized() async throws {
        StubURLProtocol.statusCode = 403
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: [
            "error": "banned", "message": "temporarily banned",
        ])
        let client = makeClient()

        do {
            try await client.requestToken(turnstileResponse: "tt", scope: .submit)
            XCTFail("403 は例外を投げるはず")
        } catch let err as APIError {
            guard case .banned = err else {
                return XCTFail("403 banned は unauthorized ではなく banned にマップすること: \(err)")
            }
        }
    }

    /// 401（トークン不正・期限切れ等）は従来どおり unauthorized のまま
    /// （403 だけを区別する。401 の意味は変えない）。
    func test_401_stillMapsToUnauthorized() async throws {
        StubURLProtocol.statusCode = 401
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: [
            "error": "unauthorized", "message": "invalid or expired token",
        ])
        let client = makeClient()

        do {
            try await client.requestToken(turnstileResponse: "tt", scope: .submit)
            XCTFail("401 は例外を投げるはず")
        } catch let err as APIError {
            XCTAssertEqual(err, .unauthorized, "401 は従来どおり unauthorized のまま")
        }
    }
}
