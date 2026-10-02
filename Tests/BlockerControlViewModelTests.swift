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
        let vm = BlockerControlViewModel(store: store, markPending: { _ in }, reloader: { _ in })
        XCTAssertTrue(vm.adEnabled)
        XCTAssertTrue(vm.securityEnabled)
    }

    func test_initial_state_loaded_from_existing_file() throws {
        try store.write(BlockerTogglesState(adEnabled: false, securityEnabled: true))
        let vm = BlockerControlViewModel(store: store, markPending: { _ in }, reloader: { _ in })
        XCTAssertFalse(vm.adEnabled)
        XCTAssertTrue(vm.securityEnabled)
    }

    func test_toggle_persists_to_store_after_debounce() async throws {
        let expectation = expectation(description: "reloader called")
        var reloaderId: String?
        let vm = BlockerControlViewModel(
            store: store,
            markPending: { _ in },
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
            markPending: { _ in },
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

    /// 2026-10-03: ON を保存した直後〜読み込みの依頼までにアプリが終了すると、保存は ON・Safari は OFF の
    /// まま治らなかった。保存より前に「読み込みが要る」印を付ける。
    func test_状態を保存する前に_読み込みが要る印を付ける() async throws {
        let store = self.store!
        let marked = expectation(description: "marked")
        var markedID: String?
        var savedAdEnabledWhenMarked: Bool?
        let vm = BlockerControlViewModel(
            store: store,
            markPending: { id in
                markedID = id
                savedAdEnabledWhenMarked = store.read().adEnabled
                marked.fulfill()
            },
            reloader: { _ in },
            regenerate: {}
        )
        vm.adEnabled = false
        await fulfillment(of: [marked], timeout: 2.0)
        XCTAssertEqual(markedID, "com.kureho.adblockkeshi.blocker")
        XCTAssertEqual(savedAdEnabledWhenMarked, true, "印を付けた時点では、まだ新しい状態を保存していない")
    }

    /// 基本保護（約 15 万件）のコンパイルと 2 本目の作り直しを同時に走らせない
    /// （起動時・CDN 更新時の経路と同じ順番にそろえる）。
    func test_toggle_regenerates_second_blocker_after_basic_reload_finishes() async throws {
        var events: [String] = []
        var finishReload: CheckedContinuation<Void, Never>?
        let vm = BlockerControlViewModel(
            store: store,
            markPending: { _ in },
            reloader: { _ in
                events.append("reload-start")
                await withCheckedContinuation { finishReload = $0 }
                events.append("reload-end")
            },
            regenerate: { events.append("regenerate") }
        )
        vm.adEnabled = false
        for _ in 0..<200 where finishReload == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(events, ["reload-start"], "基本保護の読み込みが終わる前に作り直さない")
        finishReload?.resume()
        for _ in 0..<200 where events.count < 3 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(events, ["reload-start", "reload-end", "regenerate"])
    }
}
