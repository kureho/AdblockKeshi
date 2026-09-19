import XCTest
import WebKit
@testable import AdblockKeshi

/// combined 再生成が **バックグラウンドで WebKit を初期化して落ちる**回帰を防ぐ。
///
/// 事故（2026-09-18・v4.2.0 で per-site 例外を入れて以降）:
/// 例外サイトが 1 件でもあると起動直後に `scheduleRegenerate()` → `regenQueue`（= メイン以外）
/// → `compileVerify` → `WKContentRuleListStore.default()` と進み、そこで WebKit のグローバル
/// 初期化 `WebKit::InitializeWebKit2()` が走る。この初期化は **メインスレッド限定**で、
/// メイン以外から最初に触ると `RELEASE_ASSERT` に引っかかり `EXC_BREAKPOINT (SIGTRAP)` で
/// プロセスごと落ちる（= アプリが起動した瞬間にホーム画面へ戻る）。
///
/// ★このクラスは **プロセス内で WebKit がまだ初期化されていないこと**が前提の再現テスト。
///   単体で走らせる（`-only-testing:AdblockKeshiTests/CombinedRuleListCoordinatorThreadingTests`）と
///   確実に再現する。全体実行では他クラスが先にメインで WebKit を初期化していると
///   素通りするので、契約そのものを見る `test_onMainThread_*` を併せて置いている。
final class CombinedRuleListCoordinatorThreadingTests: XCTestCase {

    /// WebKit に触る処理は、呼び出し元がどのスレッドでもメインで実行されること。
    /// （再現テストと違い実行順に依存しない＝常に契約を検査する）
    func test_onMainThread_runsOnMainEvenWhenCalledOffMain() {
        let done = expectation(description: "executed")
        var ranOnMain = false
        DispatchQueue.global(qos: .utility).async {
            XCTAssertFalse(Thread.isMainThread, "前提: 呼び出し元はメイン以外")
            CombinedRuleListCoordinator.onMainThread {
                ranOnMain = Thread.isMainThread
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 10)
        XCTAssertTrue(ranOnMain, "WebKit に触る処理がメインスレッド以外で実行された（SIGTRAP の原因）")
    }

    /// 例外サイトがある状態で、起動時と同じ経路（off-main）から再生成しても落ちないこと。
    func test_regenerateIfNeeded_offMain_withSiteException_doesNotCrash() throws {
        let store = try XCTUnwrap(SiteExceptionsStore.sharedAppGroup(),
                                  "App Group が引けない環境ではこの再現は検査できない")
        let saved = store.readDomains()
        defer {
            // 実機/シミュレータの実データを壊さないよう、必ず元へ戻す。
            for d in store.readDomains() where !saved.contains(d) { try? store.remove(d) }
            for d in saved { try? store.add(d) }
        }
        try store.add("example.com")

        let done = expectation(description: "regenerate finished")
        CombinedRuleListCoordinator.scheduleRegenerate {
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
    }
}
