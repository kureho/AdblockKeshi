import XCTest
@testable import AdblockKeshi

/// A-88 §1・§3: `submitReport` がサーバーの報告 ID を返すこと（履歴への保存に使う）と、
/// `POST /v1/reports/status` の結果取得を新しく実装する契約を固定する。
final class ReportAPIClientReportStatusTests: XCTestCase {

    private final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var statusCode = 200
        nonisolated(unsafe) static var body: Data = Data()
        nonisolated(unsafe) static var lastRequestBody: Data?
        nonisolated(unsafe) static var lastRequestPath: String?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequestBody = request.httpBodyStream.map { stream -> Data in
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 4096
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: bufferSize)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                return data
            } ?? request.httpBody
            Self.lastRequestPath = request.url?.path
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
        keychainService = "test.report-api-client-status.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? KeychainHelper(service: keychainService, accessGroup: nil).delete(account: DeviceUUIDStore.account)
        super.tearDown()
    }

    private func makeClient(tokenStore: HMACTokenStore = HMACTokenStore()) -> ReportAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let uuidStore = DeviceUUIDStore(
            keychain: KeychainHelper(service: keychainService, accessGroup: nil),
            serverSalt: "test-salt"
        )
        return ReportAPIClient(
            baseURL: URL(string: "https://stub.invalid")!,
            session: session,
            uuidStore: uuidStore,
            tokenStore: tokenStore
        )
    }

    func test_submitReport_returnsServerIdFromResponse() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: [
            "id": "5b1e6f2a-1234-4a11-9c22-0000000000aa",
            "status": "pending",
            "received_at": 1_700_000_000,
            "memo_redacted": false,
        ])
        let tokenStore = HMACTokenStore()
        await tokenStore.set(HMACToken(value: "cached", scope: .submit,
                                       expiresAt: Date(timeIntervalSinceNow: 300)))
        let client = makeClient(tokenStore: tokenStore)

        let serverId = try await client.submitReport(
            url: URL(string: "https://example.com/article")!, memo: nil, adType: nil,
            reportKind: .adNotBlocked, seenIn: .safari, diagnostics: .unavailable
        )

        XCTAssertEqual(serverId, "5b1e6f2a-1234-4a11-9c22-0000000000aa")
    }

    func test_fetchReportOutcomes_decodesItems() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: [
            "items": [
                ["id": "s1", "outcome": "applied"],
                ["id": "s2", "outcome": "checking"],
            ],
            "fetched_at": 1_700_000_000,
        ])
        let client = makeClient()

        let results = try await client.fetchReportOutcomes(ids: ["s1", "s2"])

        XCTAssertEqual(results, [
            ReportOutcomeResult(id: "s1", outcome: "applied"),
            ReportOutcomeResult(id: "s2", outcome: "checking"),
        ])
    }

    func test_fetchReportOutcomes_sendsIdsInRequestBody() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: ["items": [], "fetched_at": 1_700_000_000])
        let client = makeClient()

        _ = try await client.fetchReportOutcomes(ids: ["s1", "s2"])

        XCTAssertEqual(StubURLProtocol.lastRequestPath, "/v1/reports/status")
        let sentBody = try XCTUnwrap(StubURLProtocol.lastRequestBody)
        let json = try JSONSerialization.jsonObject(with: sentBody) as? [String: Any]
        XCTAssertEqual(json?["ids"] as? [String], ["s1", "s2"])
    }

    /// 失敗は例外を投げる（呼び出し側の `LocalReportHistoryStore.refreshStatuses` が
    /// catch して今の表示のまま保つ設計。ここでは投げること自体を固定する）。
    func test_fetchReportOutcomes_onServerError_throws() async throws {
        StubURLProtocol.statusCode = 500
        StubURLProtocol.body = Data()
        let client = makeClient()

        do {
            _ = try await client.fetchReportOutcomes(ids: ["s1"])
            XCTFail("500 は例外を投げるはず")
        } catch let err as APIError {
            XCTAssertEqual(err, .serverError(statusCode: 500))
        }
    }
}
