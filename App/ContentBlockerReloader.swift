import Foundation
import SafariServices
import UIKit

/// Safari のコンテンツブロッカーを読み込み直す唯一の窓口（全経路をここに集める）。
///
/// 2026-10-03 発覚: トグルを OFF→ON した直後にアプリが閉じられると、Safari 側のコンパイル
/// （基本保護は約 11 万件で数秒〜十数秒かかる）がアプリと一緒に止まり、Safari には直前の
/// 「広告ブロックなし」のルールが残った。画面は ON のまま、アプリを開き直しても直らなかった。
///
/// - 依頼した時点で「未完了」の印を残し、Safari から成功が返ったときだけ消す。印が残っていれば
///   次の起動・前面復帰で `resumePending()` が読み込み直す（途中で止められても必ず追いつく）
/// - 依頼した時点からバックグラウンドでの実行延長を取る（ON の直後に Safari へ移っても止められにくい）
/// - 読み込みは 1 本ずつ順番に行う（重いコンパイルを同時に走らせない）
/// - Safari から返事が来なくても時間切れで次へ進む（1 本の返事待ちで後ろが永久に止まらない）
@MainActor
final class ContentBlockerReloader {
    typealias RawReload = @MainActor (_ identifier: String, _ completion: @escaping @Sendable (Error?) -> Void) -> Void
    /// 実行延長を取り、返す処理を返す。
    typealias BackgroundGuard = @MainActor () -> (@MainActor () -> Void)

    /// Safari の返事を待つ上限。基本保護（約 11 万件）のコンパイルは実機で十数秒かかるので十分に長く取る。
    static let defaultTimeout: TimeInterval = 120

    struct TimedOut: Error {}

    static let shared = ContentBlockerReloader(
        defaults: .standard,
        rawReload: { identifier, completion in
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
                if let error {
                    print("[reload] \(identifier) error: \(error.localizedDescription)")
                }
                completion(error)
            }
        },
        backgroundGuard: ContentBlockerReloader.beginBackgroundTask,
        timeout: defaultTimeout
    )

    private let ledger: PendingReloadLedger
    private let rawReload: RawReload
    private let backgroundGuard: BackgroundGuard
    private let timeout: TimeInterval
    /// 直前に依頼された読み込み（次の読み込みはこれの完了を待ってから始める）。
    private var tail: Task<Void, Never>?
    /// この起動中に依頼済みで、まだ終わっていない数（前面復帰で重ねて読み込まないため）。
    private var inFlight: [String: Int] = [:]
    /// この起動中にルールのファイルを書き換えている最中の数（`beginModification` 参照）。
    private var modifying: [String: Int] = [:]

    init(defaults: UserDefaults, rawReload: @escaping RawReload, backgroundGuard: @escaping BackgroundGuard,
         timeout: TimeInterval) {
        self.ledger = PendingReloadLedger(defaults: defaults)
        self.rawReload = rawReload
        self.backgroundGuard = backgroundGuard
        self.timeout = timeout
    }

    /// 未完了の印が残っているブロッカー。
    var pendingIdentifiers: [String] { ledger.pendingIdentifiers }

    /// 読み込み直しを依頼して、完了を待たずに戻る。
    func request(_ identifier: String) {
        _ = enqueue(identifier)
    }

    /// 読み込み直しを依頼して、完了まで待つ。成功なら true。
    /// 呼び出し元が打ち切られたら（バックグラウンド更新の時間切れ等）、順番待ちの途中でも Safari には頼まず、
    /// 印だけ残して次の機会に回す。
    @discardableResult
    func reload(_ identifier: String) async -> Bool {
        guard !Task.isCancelled else {
            markPending(identifier)
            return false
        }
        let task = enqueue(identifier)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 読み込みはせず、印だけ付ける（次の `resumePending()` で読み込み直す）。
    /// ルールを書き換える直前に呼ぶ＝書き換え直後〜読み込みの依頼までの間にアプリが終了しても取りこぼさない。
    func markPending(_ identifier: String) {
        ledger.mark(identifier)
    }

    /// これからルールのファイルを書き換える（書き込み・削除の直前に呼ぶ）。印を付け、`finishModification` までは
    /// 読み込みが成功しても印を消さず、前面復帰のやり直しも始めない。
    /// 書き換え前のファイルを読んだ読み込みの成功で印が消え、書き換えの後〜依頼の前に終了されると、
    /// 次の起動では作り直しも読み込みも起きず Safari に古いルールが残るため。
    func beginModification(_ identifier: String) {
        ledger.mark(identifier)
        modifying[identifier, default: 0] += 1
    }

    /// 書き換えが終わった。読み込みを依頼する（完了を待たない）。
    func finishModification(_ identifier: String) {
        endModification(identifier)
        request(identifier)
    }

    /// 書き換えが終わった。読み込みを依頼して完了まで待つ。成功なら true。
    @discardableResult
    func finishModificationAndReload(_ identifier: String) async -> Bool {
        endModification(identifier)
        return await reload(identifier)
    }

    private func endModification(_ identifier: String) {
        guard let count = modifying[identifier] else { return }
        modifying[identifier] = count > 1 ? count - 1 : nil
    }

    /// 版が変わった最初の起動で、指定のブロッカーに印を付ける（続く `resumePending()` が読み込み直す）。
    /// この仕組みより前の版で、読み込みが途中で止まったまま残った端末を治すため。
    func scheduleOnceForBuild(_ build: String, identifiers: [String]) {
        ledger.markOnceForBuild(build, identifiers: identifiers)
    }

    /// 前回の起動（または今回のバックグラウンド中）に終わらなかった読み込みをやり直す。
    /// 起動時と前面復帰時に呼ぶ。この起動で読み込み中・書き換え中のものは重ねない（印も消さない）。
    func resumePending() {
        let busy = Set(inFlight.filter { $0.value > 0 }.keys).union(modifying.keys)
        for identifier in ledger.identifiersToResume(excluding: busy) {
            _ = enqueue(identifier, isRetry: true)
        }
    }

    private func enqueue(_ identifier: String, isRetry: Bool = false) -> Task<Bool, Never> {
        // ★印と実行延長は「依頼した瞬間」に取る（直後にアプリが閉じられても印が残るように）。
        let generation = ledger.begin(identifier, isRetry: isRetry)
        let endBackground = backgroundGuard()
        inFlight[identifier, default: 0] += 1
        let previous = tail
        let task = Task { () -> Bool in
            await previous?.value
            defer {
                inFlight[identifier, default: 1] -= 1
                endBackground()
            }
            // 順番を待つ間に呼び出し元が打ち切られたら、新しいコンパイルは始めない（印は残っている）。
            guard !Task.isCancelled else { return false }
            // やり直しの回数は Safari に渡す時点で数える（順番待ちのまま終了した分は数えない）。
            if isRetry { ledger.countAttempt(identifier, generation: generation) }
            let error = await askSafari(identifier)
            // 書き換えの最中に返った成功は、書き換え前のファイルを読んだかもしれないので印を消さない。
            ledger.finish(identifier, generation: generation, succeeded: error == nil && modifying[identifier] == nil)
            return error == nil
        }
        tail = Task { _ = await task.value }
        return task
    }

    /// Safari に読み込みを頼み、返事か時間切れのどちらか早い方を返す（遅れて届いた返事は捨てる）。
    private func askSafari(_ identifier: String) async -> Error? {
        let timeout = self.timeout
        return await withCheckedContinuation { (cont: CheckedContinuation<Error?, Never>) in
            let once = RunOnce()
            let timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                print("[reload] \(identifier): \(Int(timeout)) 秒待っても返事が無いので次へ進む")
                once { cont.resume(returning: TimedOut()) }
            }
            rawReload(identifier) { error in
                timer.cancel()
                once { cont.resume(returning: error) }
            }
        }
    }

    static func beginBackgroundTask() -> (@MainActor () -> Void) {
        final class Box { var id: UIBackgroundTaskIdentifier = .invalid }
        let box = Box()
        let end: @MainActor () -> Void = {
            guard box.id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(box.id)
            box.id = .invalid
        }
        box.id = UIApplication.shared.beginBackgroundTask(withName: "ContentBlockerReload") {
            // 時間切れ。印は残っているので次の起動・前面復帰でやり直される。
            MainActor.assumeIsolated { end() }
        }
        return end
    }
}

/// 「Safari の読み込みが終わっていないブロッカー」の記録。アプリが終了しても残るよう UserDefaults に置く。
struct PendingReloadLedger {
    /// やり直し（失敗・中断の後の読み込み直し）がこの回数に達したら諦める。毎回の起動で重いコンパイルを繰り返さない。
    static let maxAttempts = 3

    private static let entriesKey = "contentBlockerReload.pending"
    private static let sequenceKey = "contentBlockerReload.sequence"
    private static let lastBuildKey = "contentBlockerReload.lastBuild"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var pendingIdentifiers: [String] { entries.keys.sorted() }

    /// 読み込みを依頼する直前に呼ぶ。この依頼の世代番号を返す。
    /// 新しい依頼（トグル・ルール更新など）は中身が変わったので、やり直しの回数を数え直す。
    func begin(_ identifier: String, isRetry: Bool) -> Int {
        let generation = defaults.integer(forKey: Self.sequenceKey) + 1
        defaults.set(generation, forKey: Self.sequenceKey)
        var all = entries
        let attempts = isRetry ? (all[identifier]?["attempts"] ?? 0) : 0
        all[identifier] = ["generation": generation, "attempts": attempts]
        entries = all
        return generation
    }

    /// やり直しを Safari に渡す直前に呼ぶ。回数は「やり直し」だけを、実際に Safari へ渡した分だけ数える
    /// （1 本目の途中で終了され続けると、順番待ちの 2 本目は一度も渡らないまま上限に達してしまうため）。
    func countAttempt(_ identifier: String, generation: Int) {
        var all = entries
        guard var entry = all[identifier], entry["generation"] == generation else { return }
        entry["attempts", default: 0] += 1
        all[identifier] = entry
        entries = all
    }

    /// 読み込みはせず、新しい依頼と同じ印だけ付ける。
    func mark(_ identifier: String) {
        _ = begin(identifier, isRetry: false)
    }

    /// Safari から返事が来たときに呼ぶ。成功で、しかもそれが最後の依頼だったときだけ印を消す
    /// （OFF の分が先に成功しても、ON の分が終わっていなければ印は残す）。
    func finish(_ identifier: String, generation: Int, succeeded: Bool) {
        guard succeeded else { return }
        var all = entries
        guard all[identifier]?["generation"] == generation else { return }
        all[identifier] = nil
        entries = all
    }

    /// 前回と違う版で初めて呼ばれたときだけ、指定のブロッカーに印を付ける（前の版で諦めた回数も数え直す）。
    func markOnceForBuild(_ build: String, identifiers: [String]) {
        guard defaults.string(forKey: Self.lastBuildKey) != build else { return }
        identifiers.forEach(mark)
        defaults.set(build, forKey: Self.lastBuildKey)
    }

    /// やり直す対象（読み込み中のものは除く）。やり直しが上限に達したものは印ごと消して返さない。
    func identifiersToResume(excluding running: Set<String>) -> [String] {
        var all = entries
        var resume: [String] = []
        for (identifier, entry) in all where !running.contains(identifier) {
            if (entry["attempts"] ?? 0) >= Self.maxAttempts {
                print("[reload] \(identifier): \(Self.maxAttempts) 回やり直しても終わらなかったので諦める")
                all[identifier] = nil
            } else {
                resume.append(identifier)
            }
        }
        if all.count != entries.count { entries = all }
        return resume.sorted()
    }

    private var entries: [String: [String: Int]] {
        get { defaults.dictionary(forKey: Self.entriesKey) as? [String: [String: Int]] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.entriesKey) }
    }
}

/// 最初の 1 回だけ実行する（Safari の返事と時間切れのどちらが先でも、待っている側を 1 回だけ再開する）。
final class RunOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func callAsFunction(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
