import XCTest
@testable import AdblockKeshi

/// 報告が成功したら、自己報告ファストレーン(applier)が報告URLで呼ばれることを固定する。
/// これが切れると「報告しても自分の端末に反映されない」という当初の不満に戻る。
@MainActor
final class SelfReportFastLaneWiringTests: XCTestCase {

    private final class StubClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?) async throws {}
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    private final class SpyApplier: SelfReportApplying {
        var applied: [URL] = []
        func apply(reportedURL: URL) { applied.append(reportedURL) }
    }

    func test_applies_self_report_on_successful_submit() async {
        let spy = SpyApplier()
        let vm = ReportFormViewModel(
            apiClient: StubClient(),
            selfReportApplier: spy,
            onSuccess: {}
        )
        vm.urlInput = "https://ads.example.com/banner"
        vm.selectedAdType = .popup
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertEqual(spy.applied.map { $0.absoluteString }, ["https://ads.example.com/banner"])
    }

    private final class FailingClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?) async throws {
            throw APIError.decodingFailed
        }
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }

    func test_does_not_apply_when_submit_fails() async {
        let spy = SpyApplier()
        let vm = ReportFormViewModel(
            apiClient: FailingClient(),
            selfReportApplier: spy,
            onSuccess: {}
        )
        vm.urlInput = "https://ads.example.com/banner"
        vm.selectedAdType = .popup
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertTrue(spy.applied.isEmpty, "送信失敗時は端末にも反映しない")
    }
}
