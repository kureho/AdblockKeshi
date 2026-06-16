import XCTest
@testable import AdblockKeshi

/// 報告が自端末で即反映されたら履歴に「この端末で反映済」を表示する。
/// 元の不満「報告したものがどう活かされてるか分からない」への直接の答え。
@MainActor
final class SelfReportStatusFeedbackTests: XCTestCase {

    private final class OKClient: ReportAPIClientProtocol, @unchecked Sendable {
        func submitReport(url: URL, memo: String?, adType: AdType?) async throws {}
        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {}
    }
    private final class NoopApplier: SelfReportApplying {
        func apply(reportedURL: URL) {}
    }

    func test_appliedLocally_label_and_badge() {
        XCTAssertEqual(ReportStatus.appliedLocally.displayLabel, "この端末で反映済")
        XCTAssertEqual(ReportStatus.appliedLocally.badgeRole, .success)
    }

    private func makeVM(_ history: LocalReportHistoryStore) -> ReportFormViewModel {
        ReportFormViewModel(
            apiClient: OKClient(),
            historyStore: history,
            selfReportApplier: NoopApplier(),
            onSuccess: {}
        )
    }

    func test_history_marked_appliedLocally_for_normal_ad_url() async {
        let history = LocalReportHistoryStore(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!)
        let vm = makeVM(history)
        vm.urlInput = "https://ads.example.com/banner"
        vm.selectedAdType = .popup
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt")
        XCTAssertEqual(history.items.first?.status, .appliedLocally)
    }

    func test_history_pending_for_critical_domain() async {
        let history = LocalReportHistoryStore(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!)
        let vm = makeVM(history)
        vm.urlInput = "https://pay.stripe.com/checkout"
        vm.selectedAdType = .popup
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt")
        // 重要ドメインはローカル適用されない → 通常の受付済(pending)
        XCTAssertEqual(history.items.first?.status, .pending)
    }
}
