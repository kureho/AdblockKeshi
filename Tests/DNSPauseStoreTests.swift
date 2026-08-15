import XCTest
@testable import AdblockKeshi

/// DNSPauseStore（DNS 保護の時限一時停止・dns-pause.json）のテスト。
/// 仕様: 一時停止は「期限つき」でのみ存在する。期限切れ・未存在・不正 JSON は
/// すべて「停止していない」に倒す（fail-safe = 保護が生きる方向）。
final class DNSPauseStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dns-pause-\(UUID().uuidString).json")
    }

    func test_read_missingFile_returnsNil() {
        XCTAssertNil(DNSPauseStore(fileURL: tempURL()).readPausedUntil())
    }

    func test_pause_thenRead_roundTrips() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSPauseStore(fileURL: url)
        let until = Date(timeIntervalSince1970: 2_000_000_000)   // 未来の固定時刻
        try store.pause(until: until)
        let read = store.readPausedUntil(now: Date(timeIntervalSince1970: 1_999_999_000))
        XCTAssertEqual(read?.timeIntervalSince1970 ?? 0, until.timeIntervalSince1970, accuracy: 1)
    }

    func test_read_expired_returnsNil() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSPauseStore(fileURL: url)
        let until = Date(timeIntervalSince1970: 1_000)
        try store.pause(until: until)
        XCTAssertNil(store.readPausedUntil(now: Date(timeIntervalSince1970: 1_001)),
                     "期限切れは「停止していない」= 保護が自動で戻る方向に倒す")
    }

    func test_read_exactDeadline_returnsNil() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSPauseStore(fileURL: url)
        let until = Date(timeIntervalSince1970: 1_000)
        try store.pause(until: until)
        XCTAssertNil(store.readPausedUntil(now: until), "期限ちょうどは再開済み扱い")
    }

    func test_read_corruptJSON_returnsNil() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(DNSPauseStore(fileURL: url).readPausedUntil(), "不正 JSON は fail-safe で停止なし")
    }

    func test_clear_removesPause_andIsIdempotent() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSPauseStore(fileURL: url)
        try store.pause(until: Date(timeIntervalSince1970: 2_000_000_000))
        try store.clear()
        XCTAssertNil(store.readPausedUntil(now: Date(timeIntervalSince1970: 0)))
        XCTAssertNoThrow(try store.clear(), "2 回目の clear も throw しない（冪等）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "ファイル自体を残さない")
    }

    func test_pause_overwritesPreviousDeadline() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSPauseStore(fileURL: url)
        try store.pause(until: Date(timeIntervalSince1970: 1_500))
        let longer = Date(timeIntervalSince1970: 5_000)
        try store.pause(until: longer)
        let read = store.readPausedUntil(now: Date(timeIntervalSince1970: 1_600))
        XCTAssertEqual(read?.timeIntervalSince1970 ?? 0, longer.timeIntervalSince1970, accuracy: 1,
                       "後から選んだ停止時間で上書きされる（15分→1時間の変更）")
    }
}
