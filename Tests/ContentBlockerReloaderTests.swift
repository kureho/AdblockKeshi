import XCTest
@testable import AdblockKeshi

/// Safari の reload を代わりに受ける偽物。完了はテストが手で返す（返さない＝途中でアプリが終了した）。
private final class FakeSafari {
    var calls: [String] = []
    private var completions: [(Error?) -> Void] = []

    func reload(_ identifier: String, _ completion: @escaping @Sendable (Error?) -> Void) {
        calls.append(identifier)
        completions.append(completion)
    }

    func completeOldest(error: Error? = nil) {
        completions.removeFirst()(error)
    }

    func completeLatest(error: Error? = nil) {
        completions.removeLast()(error)
    }
}

private struct LoaderError: Error {}

/// 2026-10-03: トグルを OFF→ON した直後にアプリが閉じられると、Safari に広告ブロックなしの
/// ルールが残り、アプリを開き直しても直らなかった（画面は ON のまま）。その再発防止。
@MainActor
final class ContentBlockerReloaderTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var safari: FakeSafari!
    private var backgroundBegun = 0
    private var backgroundEnded = 0

    override func setUp() {
        super.setUp()
        suiteName = "ContentBlockerReloaderTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        safari = FakeSafari()
        backgroundBegun = 0
        backgroundEnded = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// アプリの起動 1 回分。同じ defaults を渡す＝前回の起動の記録が残っている。
    /// 前の起動の分は完了を返さずに放っておく＝その起動のプロセスは終了した扱い。
    private func launch(timeout: TimeInterval = 60) -> ContentBlockerReloader {
        let safari = self.safari!
        return ContentBlockerReloader(
            defaults: defaults,
            rawReload: { id, done in safari.reload(id, done) },
            backgroundGuard: { [unowned self] in
                self.backgroundBegun += 1
                return { self.backgroundEnded += 1 }
            },
            timeout: timeout
        )
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("条件が 2 秒以内に満たされなかった", file: file, line: line)
    }

    /// 起きていないことを確かめるために、少しだけ処理を進める。
    private func settle() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - 途中で止まったら次の起動でやり直す

    func test_読み込みの途中でアプリが終了したら_次の起動で読み込み直す() async {
        launch().request("blocker")
        await waitUntil { safari.calls == ["blocker"] }
        // 完了を返さないままアプリが終了した

        let second = launch()
        second.resumePending()
        await waitUntil { safari.calls == ["blocker", "blocker"] }
        safari.completeLatest()
        await waitUntil { second.pendingIdentifiers.isEmpty }
    }

    func test_読み込みが失敗したら印を残し_次の起動でやり直す() async {
        let first = launch()
        first.request("blocker")
        await waitUntil { safari.calls.count == 1 }
        safari.completeOldest(error: LoaderError())
        await settle()
        XCTAssertEqual(first.pendingIdentifiers, ["blocker"])

        let second = launch()
        second.resumePending()
        await waitUntil { safari.calls == ["blocker", "blocker"] }
    }

    func test_読み込みが成功したら次の起動では何もしない() async {
        let first = launch()
        first.request("blocker")
        await waitUntil { safari.calls.count == 1 }
        safari.completeOldest()
        await waitUntil { first.pendingIdentifiers.isEmpty }

        let second = launch()
        second.resumePending()
        await settle()
        XCTAssertEqual(safari.calls, ["blocker"])
    }

    func test_同じブロッカーの後の依頼が終わるまでは_前の依頼の成功で印を消さない() async {
        let first = launch()
        first.request("blocker")   // OFF の分
        first.request("blocker")   // ON の分
        await waitUntil { safari.calls.count == 1 }
        safari.completeOldest()     // OFF の分だけ終わった
        await waitUntil { safari.calls.count == 2 }
        // ON の分が終わる前にアプリが終了した
        XCTAssertEqual(first.pendingIdentifiers, ["blocker"])
    }

    func test_印だけ付けたものも_次の起動で読み込み直す() async {
        // 2 本目はトグル後に作り直してから読み込むので、作り直しの前に印だけ付けておく
        launch().markPending("popunder")
        XCTAssertTrue(safari.calls.isEmpty, "印を付けるだけで、読み込みはしない")

        let second = launch()
        second.resumePending()
        await waitUntil { safari.calls == ["popunder"] }
    }

    // MARK: - ルールのファイルを書き換えている間

    /// 書き換え前のファイルを読んだ読み込みの成功で印を消すと、書き換え後〜依頼前に終了されたとき直らない。
    func test_書き換え中に読み込みが成功しても印を消さず_書き換えの終わりで読み込み直す() async {
        let reloader = launch()
        reloader.request("popunder")
        await waitUntil { safari.calls.count == 1 }
        reloader.beginModification("popunder")
        safari.completeOldest()      // 書き換え前のファイルを読んだ分が成功
        await settle()
        XCTAssertEqual(reloader.pendingIdentifiers, ["popunder"])

        reloader.finishModification("popunder")
        await waitUntil { safari.calls.count == 2 }
        safari.completeOldest()
        await waitUntil { reloader.pendingIdentifiers.isEmpty }
    }

    /// 世代番号だけでは守れない順序: 書き換え中に新しく頼んだ読み込み（最新の世代）が、書き換えの途中のファイルを読んで成功する。
    func test_書き換え中に新しく頼んだ読み込みが成功しても_印は消さない() async {
        let reloader = launch()
        reloader.beginModification("blocker")
        reloader.request("blocker")
        await waitUntil { safari.calls.count == 1 }
        safari.completeOldest()
        await settle()
        XCTAssertEqual(reloader.pendingIdentifiers, ["blocker"], "書き換えの途中のファイルを読んだかもしれない")

        let task = Task { await reloader.finishModificationAndReload("blocker") }
        await waitUntil { safari.calls.count == 2 }
        safari.completeOldest()
        _ = await task.value
        XCTAssertTrue(reloader.pendingIdentifiers.isEmpty)
    }

    /// ルール更新と CDN 同期が同じ拡張のファイルを同時に書き換えることがある＝片方の終わりで印を消さない。
    func test_書き換えが重なったら_両方が終わるまで印を消さず_やり直しも始めない() async {
        let reloader = launch()
        reloader.beginModification("popunder")
        reloader.beginModification("popunder")
        let first = Task { await reloader.finishModificationAndReload("popunder") }
        await waitUntil { safari.calls.count == 1 }
        safari.completeOldest()
        _ = await first.value
        XCTAssertEqual(reloader.pendingIdentifiers, ["popunder"], "もう片方はまだ書き換えている")
        reloader.resumePending()
        await settle()
        XCTAssertEqual(safari.calls.count, 1, "書き換えの途中のファイルを読ませない")

        let second = Task { await reloader.finishModificationAndReload("popunder") }
        await waitUntil { safari.calls.count == 2 }
        safari.completeOldest()
        _ = await second.value
        XCTAssertTrue(reloader.pendingIdentifiers.isEmpty)
    }

    func test_書き換え中は_前面復帰のやり直しを始めない() async {
        let reloader = launch()
        reloader.beginModification("popunder")
        reloader.resumePending()
        await settle()
        XCTAssertTrue(safari.calls.isEmpty, "書き換えの途中のファイルを読ませない")

        reloader.finishModification("popunder")
        await waitUntil { safari.calls == ["popunder"] }
    }

    func test_書き換えの途中でアプリが終了したら_次の起動で読み込み直す() async {
        launch().beginModification("popunder")
        let second = launch()
        second.resumePending()
        await waitUntil { safari.calls == ["popunder"] }
    }

    func test_書き換えの終わりを待ってから読み込む版は_完了まで待って成否を返す() async {
        let reloader = launch()
        reloader.beginModification("blocker")
        let task = Task { await reloader.finishModificationAndReload("blocker") }
        await waitUntil { safari.calls == ["blocker"] }
        safari.completeOldest()
        let succeeded = await task.value
        XCTAssertTrue(succeeded)
        XCTAssertTrue(reloader.pendingIdentifiers.isEmpty)
    }

    // MARK: - 順番・時間切れ

    func test_読み込みは1本ずつ順番に行う() async {
        let reloader = launch()
        reloader.request("blocker")
        reloader.request("popunder")
        await waitUntil { safari.calls == ["blocker"] }
        await settle()
        XCTAssertEqual(safari.calls, ["blocker"], "1 本目が終わる前に 2 本目のコンパイルを始めない")
        safari.completeOldest()
        await waitUntil { safari.calls == ["blocker", "popunder"] }
    }

    func test_Safariから返事が来なくても_時間切れで次の読み込みに進み_印は残す() async {
        let reloader = launch(timeout: 0.05)
        reloader.request("blocker")
        reloader.request("popunder")
        await waitUntil { safari.calls == ["blocker", "popunder"] }
        XCTAssertEqual(reloader.pendingIdentifiers, ["blocker", "popunder"])
    }

    func test_時間切れの後に返事が届いても二重に扱わない() async {
        let reloader = launch(timeout: 0.05)
        let task = Task { await reloader.reload("blocker") }
        let succeeded = await task.value
        XCTAssertFalse(succeeded, "時間切れは失敗として返す")
        safari.completeOldest()   // 遅れて成功が届く（二重に再開するとここで落ちる）
        await settle()
        XCTAssertEqual(reloader.pendingIdentifiers, ["blocker"], "時間切れの分は次の機会にやり直す")
    }

    func test_読み込み中のものは復帰時に重ねて読み込まない() async {
        let reloader = launch()
        reloader.request("blocker")
        await waitUntil { safari.calls.count == 1 }
        reloader.resumePending()   // 前面復帰
        await settle()
        XCTAssertEqual(safari.calls.count, 1)
    }

    // MARK: - やり直しの回数

    func test_やり直しは3回までで諦める() async {
        launch().request("blocker")
        await waitUntil { safari.calls.count == 1 }
        for expected in 2...4 {
            launch().resumePending()
            await waitUntil { safari.calls.count == expected }
        }

        let fifth = launch()
        fifth.resumePending()
        await settle()
        XCTAssertEqual(safari.calls.count, 4, "毎回の起動で重いコンパイルを繰り返さない")
        XCTAssertTrue(fifth.pendingIdentifiers.isEmpty)
    }

    func test_回数はやり直しだけを数え_同じ起動で重なった依頼は数えない() async {
        // OFF→ON（2 回の依頼）の途中で終了。Safari に渡ったのは 1 回だけ
        let first = launch()
        first.request("blocker")
        first.request("blocker")
        await waitUntil { safari.calls.count == 1 }

        for expected in 2...4 {
            launch().resumePending()
            await waitUntil { safari.calls.count == expected }
        }
        // 依頼の数で数えると、ここまでに諦めて 4 回目が来ない
        XCTAssertEqual(safari.calls.count, 4)
    }

    func test_新しい依頼が来たら_やり直しの回数を数え直す() async {
        launch().request("blocker")
        await waitUntil { safari.calls.count == 1 }
        launch().resumePending()
        await waitUntil { safari.calls.count == 2 }
        launch().resumePending()
        await waitUntil { safari.calls.count == 3 }

        launch().request("blocker")   // 中身が変わった新しい依頼（トグル・CDN 更新など）
        await waitUntil { safari.calls.count == 4 }
        for expected in 5...7 {
            launch().resumePending()
            await waitUntil { safari.calls.count == expected }
        }
    }

    /// 2 本に印が残っていて、毎回 1 本目の途中でアプリが終了した。2 本目は一度も Safari に渡っていない。
    func test_順番待ちのまま終わったものは_やり直しの回数に数えない() async {
        let first = launch()
        first.markPending("a")
        first.markPending("b")
        for expected in 1...3 {
            launch().resumePending()
            await waitUntil { safari.calls.count == expected }
            await settle()
        }
        XCTAssertEqual(safari.calls, ["a", "a", "a"])

        let fourth = launch()
        fourth.resumePending()
        await waitUntil { safari.calls.last == "b" }
        XCTAssertEqual(fourth.pendingIdentifiers, ["b"], "Safari に渡っていない分まで諦めない")
    }

    func test_読み込み中のものは_回数が上限でも印を消さない() async {
        launch().request("blocker")
        await waitUntil { safari.calls.count == 1 }
        launch().resumePending()
        await waitUntil { safari.calls.count == 2 }
        launch().resumePending()
        await waitUntil { safari.calls.count == 3 }
        let current = launch()
        current.resumePending()        // 3 回目のやり直しが読み込み中
        await waitUntil { safari.calls.count == 4 }

        current.resumePending()        // 読み込み中に前面復帰
        await settle()
        XCTAssertEqual(current.pendingIdentifiers, ["blocker"], "まだ終わっていないものの印は消さない")
    }

    // MARK: - 更新後の 1 回

    /// この修正より前の版で壊れた状態になった端末は印を持っていない。更新後の初回起動で 1 回だけ読み込み直して治す。
    func test_アプリ更新後の初回起動だけ_指定のブロッカーを読み込み直す() async {
        let first = launch()
        first.scheduleOnceForBuild("10500", identifiers: ["blocker"])
        first.resumePending()
        await waitUntil { safari.calls == ["blocker"] }
        safari.completeOldest()
        await waitUntil { first.pendingIdentifiers.isEmpty }

        let sameBuild = launch()
        sameBuild.scheduleOnceForBuild("10500", identifiers: ["blocker"])
        sameBuild.resumePending()
        await settle()
        XCTAssertEqual(safari.calls, ["blocker"], "同じ版の 2 回目以降の起動では読み込み直さない")

        let nextBuild = launch()
        nextBuild.scheduleOnceForBuild("10501", identifiers: ["blocker"])
        nextBuild.resumePending()
        await waitUntil { safari.calls == ["blocker", "blocker"] }
    }

    func test_更新後の読み込み直しが途中で止められても_次の起動でやり直す() async {
        let first = launch()
        first.scheduleOnceForBuild("10500", identifiers: ["blocker"])
        first.resumePending()
        await waitUntil { safari.calls.count == 1 }
        // 完了を返さないままアプリが終了した

        let second = launch()
        second.scheduleOnceForBuild("10500", identifiers: ["blocker"])
        second.resumePending()
        await waitUntil { safari.calls.count == 2 }
    }

    func test_前の版でやり直しを使い切った印があっても_更新後は読み込み直す() async {
        launch().request("blocker")
        await waitUntil { safari.calls.count == 1 }
        for expected in 2...4 {
            launch().resumePending()
            await waitUntil { safari.calls.count == expected }
        }

        let updated = launch()
        updated.scheduleOnceForBuild("10501", identifiers: ["blocker"])
        updated.resumePending()
        await waitUntil { safari.calls.count == 5 }
    }

    // MARK: - その他

    func test_依頼した瞬間からバックグラウンドでの実行延長を取り_完了で返す() async {
        let reloader = launch()
        reloader.request("blocker")
        XCTAssertEqual(backgroundBegun, 1, "Safari へ移ってもアプリが止められないよう、依頼の時点で取る")
        await waitUntil { safari.calls.count == 1 }
        XCTAssertEqual(backgroundEnded, 0)
        safari.completeOldest()
        await waitUntil { backgroundEnded == 1 }
    }

    /// バックグラウンド更新の時間切れ（呼び出し元の打ち切り）の後に、新しいコンパイルを始めない。
    func test_呼び出し元が打ち切られていたら_Safariには頼まず印だけ残す() async {
        let reloader = launch()
        let task = Task { await reloader.reload("blocker") }
        task.cancel()   // 中身が動き出す前に打ち切られた
        let succeeded = await task.value
        XCTAssertFalse(succeeded)
        XCTAssertTrue(safari.calls.isEmpty)
        XCTAssertEqual(reloader.pendingIdentifiers, ["blocker"], "次の起動・前面復帰で読み込み直す")
    }

    func test_順番待ちの間に呼び出し元が打ち切られたら_Safariには頼まず印だけ残す() async {
        let reloader = launch()
        reloader.request("blocker")
        await waitUntil { safari.calls.count == 1 }
        let task = Task { await reloader.reload("popunder") }
        await settle()   // popunder は 1 本目の完了待ち
        task.cancel()    // その間にバックグラウンド更新の時間切れ
        safari.completeOldest()
        let succeeded = await task.value
        XCTAssertFalse(succeeded)
        await settle()
        XCTAssertEqual(safari.calls, ["blocker"], "打ち切られた後に新しいコンパイルを始めない")
        XCTAssertEqual(reloader.pendingIdentifiers, ["popunder"])
        XCTAssertEqual(backgroundEnded, 2, "実行延長は返す")

        reloader.resumePending()   // 次の前面復帰
        await waitUntil { safari.calls == ["blocker", "popunder"] }
    }

    func test_reloadは完了まで待って成否を返す() async {
        let reloader = launch()
        var returned = false
        let task = Task { () -> Bool in
            let succeeded = await reloader.reload("blocker")
            returned = true
            return succeeded
        }
        await waitUntil { safari.calls.count == 1 }
        await settle()
        XCTAssertFalse(returned, "Safari の返事が来るまで戻らない")
        safari.completeOldest()
        let succeeded = await task.value
        XCTAssertTrue(succeeded)

        let failing = Task { await reloader.reload("blocker") }
        await waitUntil { safari.calls.count == 2 }
        safari.completeOldest(error: LoaderError())
        let failed = await failing.value
        XCTAssertFalse(failed)
    }
}

final class RunOnceTests: XCTestCase {
    func test_何度呼んでも最初の1回だけ実行する() {
        let once = RunOnce()
        var count = 0
        once { count += 1 }
        once { count += 1 }
        XCTAssertEqual(count, 1)
    }

    func test_別スレッドから同時に呼んでも1回だけ() {
        let once = RunOnce()
        let lock = NSLock()
        var count = 0
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            once {
                lock.lock(); count += 1; lock.unlock()
            }
        }
        XCTAssertEqual(count, 1)
    }
}
