import XCTest
@testable import AdblockKeshi

/// ポップアップ対策の CDN 同期は前面復帰のたびに走る。中身が同じときに読み込み直すと、
/// 重いコンパイルを毎回走らせ、読み込み直しの回数制限（ContentBlockerReloader）も毎回数え直してしまう。
@MainActor
final class PopunderGlobalSyncTests: XCTestCase {
    private var events: [String] = []

    private func sync(download: (_ willReplace: () async -> Void) async -> Bool) async {
        await PopunderGlobalSync.sync(
            download: download,
            beginModification: { self.events.append("begin") },
            regenerate: { self.events.append("regenerate") },
            finishModification: { self.events.append("finish") }
        )
    }

    func test_取得に失敗したら_何もしない() async {
        await sync { _ in false }
        XCTAssertEqual(events, [])
    }

    /// 作り直しは入力のハッシュで判定するので、変化が無ければ何もしない（4.4.0 までと同じく毎回予約する）。
    /// 予約しないと、途中で止まった作り直しや、別ファイルの差し替えで古くなった combined が、次の起動まで残る。
    func test_中身が同じでも_取得できたら作り直しを予約し_読み込みはしない() async {
        await sync { _ in true }
        XCTAssertEqual(events, ["regenerate"])
    }

    func test_中身が変わったら_書き換えの前に印を付け_作り直してから読み込む() async {
        await sync { willReplace in
            await willReplace()
            self.events.append("write")
            return true
        }
        XCTAssertEqual(events, ["begin", "write", "regenerate", "finish"])
    }

    func test_書き込みに失敗しても_書き換えを始めたら読み込みまで行う() async {
        await sync { willReplace in
            await willReplace()
            return false
        }
        XCTAssertEqual(events, ["begin", "regenerate", "finish"])
    }
}
