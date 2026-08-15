import XCTest
@testable import AdblockKeshi

@MainActor
final class ReportFormViewModelAdTypeTests: XCTestCase {

    private final class CaptureClient: ReportAPIClientProtocol, @unchecked Sendable {
        var lastSubmittedAdType: AdType?
        var lastSubmittedURL: URL?
        var didCallRequestToken = false

        func submitReport(url: URL, memo: String?, adType: AdType?, reportKind: ReportKind,
                          seenIn: SeenIn, diagnostics: ReportDiagnostics) async throws {
            lastSubmittedURL = url
            lastSubmittedAdType = adType
        }

        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {
            didCallRequestToken = true
        }
    }

    private func makeViewModel(_ client: ReportAPIClientProtocol,
                               onSuccess: @escaping (ReportSuccess) -> Void = { _ in }) -> ReportFormViewModel {
        ReportFormViewModel(apiClient: client, onSuccess: onSuccess)
    }

    func test_canSubmit_isFalse_whenAdTypeNotSelected() {
        let vm = makeViewModel(CaptureClient())
        vm.urlInput = "https://example.com/article"
        vm.selectedSeenIn = .safari
        XCTAssertNil(vm.selectedAdType)
        XCTAssertFalse(vm.canSubmit, "ad type を選んでいないときは送信不可")
    }

    func test_canSubmit_isTrue_whenAdTypeSelectedWithValidURL() {
        let vm = makeViewModel(CaptureClient())
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        vm.selectedSeenIn = .safari
        XCTAssertTrue(vm.canSubmit)
    }

    func test_canSubmit_isFalse_evenWithAdType_whenURLInvalid() {
        let vm = makeViewModel(CaptureClient())
        vm.urlInput = ""
        vm.selectedAdType = .popup
        vm.selectedSeenIn = .safari
        XCTAssertFalse(vm.canSubmit)
    }

    func test_completeSubmit_passesSelectedAdTypeToClient() async {
        let client = CaptureClient()
        var didSucceed = false
        let vm = makeViewModel(client, onSuccess: { _ in didSucceed = true })
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .fakeClose
        vm.selectedSeenIn = .safari
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertTrue(didSucceed)
        XCTAssertEqual(client.lastSubmittedAdType, .fakeClose)
        // 送信後 selectedAdType はリセットされて次回未選択になる
        XCTAssertNil(vm.selectedAdType)
    }
}
