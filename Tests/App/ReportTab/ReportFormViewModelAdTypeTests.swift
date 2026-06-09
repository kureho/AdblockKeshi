import XCTest
@testable import AdblockKeshi

@MainActor
final class ReportFormViewModelAdTypeTests: XCTestCase {

    private final class CaptureClient: ReportAPIClientProtocol, @unchecked Sendable {
        var lastSubmittedAdType: AdType?
        var lastSubmittedURL: URL?
        var didCallRequestToken = false

        func submitReport(url: URL, memo: String?, adType: AdType?) async throws {
            lastSubmittedURL = url
            lastSubmittedAdType = adType
        }

        func requestToken(turnstileResponse: String, scope: TokenScope) async throws {
            didCallRequestToken = true
        }
    }

    func test_canSubmit_isFalse_whenAdTypeNotSelected() {
        let vm = ReportFormViewModel(apiClient: CaptureClient(), onSuccess: {})
        vm.urlInput = "https://example.com/article"
        XCTAssertNil(vm.selectedAdType)
        XCTAssertFalse(vm.canSubmit, "ad type を選んでいないときは送信不可")
    }

    func test_canSubmit_isTrue_whenAdTypeSelectedWithValidURL() {
        let vm = ReportFormViewModel(apiClient: CaptureClient(), onSuccess: {})
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .interstitial
        XCTAssertTrue(vm.canSubmit)
    }

    func test_canSubmit_isFalse_evenWithAdType_whenURLInvalid() {
        let vm = ReportFormViewModel(apiClient: CaptureClient(), onSuccess: {})
        vm.urlInput = ""
        vm.selectedAdType = .popup
        XCTAssertFalse(vm.canSubmit)
    }

    func test_completeSubmit_passesSelectedAdTypeToClient() async {
        let client = CaptureClient()
        var didSucceed = false
        let vm = ReportFormViewModel(apiClient: client, onSuccess: { didSucceed = true })
        vm.urlInput = "https://example.com/article"
        vm.selectedAdType = .fakeClose
        vm.beginSubmit()
        await vm.completeSubmit(turnstileResponse: "tt_dummy")

        XCTAssertTrue(didSucceed)
        XCTAssertEqual(client.lastSubmittedAdType, .fakeClose)
        // 送信後 selectedAdType はリセットされて次回未選択になる
        XCTAssertNil(vm.selectedAdType)
    }
}
