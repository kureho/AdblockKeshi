import XCTest
import Combine
@testable import AdblockKeshi

@MainActor
final class BlockerControlViewModelTests: XCTestCase {
    private var tempDir: URL!
    private var store: StateStore!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = StateStore(stateFileURL: tempDir.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_initial_state_both_enabled_when_no_file() {
        let vm = BlockerControlViewModel(store: store, reloader: { _ in })
        XCTAssertTrue(vm.adEnabled)
        XCTAssertTrue(vm.securityEnabled)
    }

    func test_initial_state_loaded_from_existing_file() throws {
        try store.write(BlockerTogglesState(adEnabled: false, securityEnabled: true))
        let vm = BlockerControlViewModel(store: store, reloader: { _ in })
        XCTAssertFalse(vm.adEnabled)
        XCTAssertTrue(vm.securityEnabled)
    }

    func test_toggle_persists_to_store_after_debounce() async throws {
        let expectation = expectation(description: "reloader called")
        var reloaderId: String?
        let vm = BlockerControlViewModel(
            store: store,
            reloader: { id in
                reloaderId = id
                expectation.fulfill()
            }
        )
        vm.adEnabled = false
        await fulfillment(of: [expectation], timeout: 2.0)
        let saved = store.read()
        XCTAssertFalse(saved.adEnabled)
        XCTAssertTrue(saved.securityEnabled)
        XCTAssertEqual(reloaderId, "com.kureho.adblockkeshi.blocker")
    }

    func test_rapid_toggles_debounced_to_single_reload() async throws {
        let expectation = expectation(description: "reloader called once")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true
        let vm = BlockerControlViewModel(
            store: store,
            reloader: { _ in expectation.fulfill() }
        )
        // 連打
        vm.adEnabled = false
        vm.adEnabled = true
        vm.securityEnabled = false
        await fulfillment(of: [expectation], timeout: 2.0)
        // 最終 state が保存されている
        let saved = store.read()
        XCTAssertTrue(saved.adEnabled)
        XCTAssertFalse(saved.securityEnabled)
    }
}
