# 「報告→反映」を実際に動かす TDD実装計画（2026-06-16 夜・GO後に実行）

> 目的: kureho ビジョン「既存フィルタ＋報告で学習して反映（黒画面も含む）・買い切り維持」を、実際に動く状態にする。診断は `report-feature-audit-2026-06-16.md`、戦略は `ceo-strategy-2026-06-16.md`。
> 作業ブランチ: `fix/reported-rules-device-wiring`（作成済み）。superpowers:test-driven-development で red→green。

## 進捗 (2026-06-16 夜・auto)
- ✅ **Phase 1a 完了・コミット済み `0d107e2`**: 報告Extension(`ReportedContentBlockerRequestHandler`)を App Group の `rules-reported.json` 消費に配線（標準側 `BlockerListResolver` を `ReportedRulesResolver.make()` で再利用）。bundleリソース名を `rules-reported.json` に統一。TDD RED(`cannot find ReportedRulesResolver`)→GREEN(`ReportedRulesResolverTests` 3件pass・全スイート回帰なし)。
  - 訂正: 当初プランの「App Group `filters/rules-reported.json`」は誤り。実際の保存先は**コンテナ直下**（`BlockerListResolver.appGroupURL()` も `FilterDownloader` もコンテナ直下を使用）。本計画の以降の `filters/` 記述はコンテナ直下に読み替え。
- ✅ **Phase 2 完了・コミット `92451e7`**（kureho GO①）: 自己報告ファストレーン。報告成功→`ReportedRuleBuilder`(URL→host-blockルール)→`SelfReportedRulesStore`(App Groupで self+global を union し `rules-reported.json` 書込)→reportedblocker reload。`ReportFormViewModel` に `SelfReportApplier` 注入（本番`ReportFormView`で配線、送信失敗時は発火しない）。新規13テストGREEN・回帰なし。
- ✅ **Phase 1b 完了・コミット `81c058e`**（kureho ④）: `FilterDownloader.reportedURL` + `ReportedGlobalSync.sync()` でグローバル配信分を `rules-global.json` に取得→union→reload。`ContentView`/`BackgroundTaskManager` の標準更新後に発火。定数ガードテスト2件。
- ✅ **安全弁 完了・コミット `a63e017`**: `CriticalDomainGuard`（サーバ critical-list と同期：決済/銀行/大手/政府/kureho自身）。`ReportedRuleBuilder` が critical ホストには rule を作らない＝誤報告でも正規サイトを端末ブロックしない。
- ✅ **即時フィードバック 完了・コミット `e840806`**: 報告が端末で即反映できたら履歴に「この端末で反映済」(`ReportStatus.appliedLocally`)。元の不満「活かされてるか分からない」への直接の答え。
- ✅ **Phase 3 完了・コミット `e372177`**（kureho GO②）: 信頼レポーター(kureho)バイパス。`computeAggregations` に `trustedUuidHashes` 追加→信頼ハッシュを含むグループは3人閾値をバイパス。`run.ts` が `TRUSTED_UUID_HASHES` env を読み、`hourly-aggregation.yml` に env パススルー（no-op when unset）。workers 191テスト pass。**有効化は Settings→Secrets に `TRUSTED_UUID_HASHES`(kureho の uuid_hash) を設定するだけ＝kureho 判断**（昇格後も L3/L5/L6 安全ゲートは通常どおり）。
- ⏭ **残る検証（最重要）**: シミュレータ実機E2E — アプリ起動→URL報告→App Groupの `rules-reported.json` にルールが入り Safari が実ブロックするか。報告フローは Turnstile(ネットワーク)を通るため `run`/`verify` skill で別途。現状は**単体・配線テストまで（system挙動は未検証）**。

## 確定した前提（実コードで確認済み）
- 拡張は2つ: 標準（`ContentBlockerRequestHandler`＋`BlockerListResolver`でApp Group→bundle→empty解決）と報告（`ReportedContentBlockerRequestHandler`＝現状bundle空配列のみ・id `com.kureho.adblockkeshi.reportedblocker`）。
- App Group: `group.com.kureho.adblockkeshi`、フィルタ保存先 `filters/`（FilterDownloaderが使用）。
- reload配管: `SFContentBlockerManager` 経由（ContentView / BlockerControlView / BackgroundTaskManager / ContentBlockerStateChecker / ContentRuleListState が既に呼ぶ）。
- アプリは `.reportedOnly` モード等で報告拡張のON/OFFを既にUI管理。
- ルール生成のサーバ実装あり: `workers/src/lib/rules.ts`（`buildReportedRulesJSON`/`generateContentBlockerRule`）— 端末側のローカル生成はこの形を踏襲する。

---

## Phase 1: 端末側配線バグ修正（安全・設計判断不要・今すぐ着手可）
**狙い**: グローバル配信された `rules-reported.json` を端末が消費できるようにする。標準フィルタ側と同型にするだけのバグ修正。

- **Test R1**（`ReportedRulesExtension` resolver）: App Group `filters/rules-reported.json` が存在すればその内容を返し、無ければ bundle 同梱の空配列にフォールバックする。
  - 実装: `BlockerListResolver` を参考に `ReportedRulesResolver`（または共通化）を新設。`ReportedContentBlockerRequestHandler.beginRequest` を App Group→bundle fallback に書き換え。
- **Test R2**（`FilterDownloader`）: `downloadAndStore()` が `rules-reported.json` も取得し App Group `filters/` に保存する。
  - 実装: `downloadAndStore` に `try await downloadFilter(filename: "rules-reported.json")` を追加。404時はbest-effort（標準フィルタを巻き込まない）。
- **Test R3**（reload）: 報告ルール更新後に `reportedblocker` の reload が呼ばれる。
- 検証: `xcodebuild test`（FilterDownloader系・resolver系の単体）。実機/シミュレータ不要の純ロジックに切り出す。

## Phase 2: 自己報告ファストレーン（kureho GO① 後・ビジョンの核）
**狙い**: 3人閾値を待たず、報告した本人の端末で即ブロック。「俺が報告しても反映されない」を解消。黒画面解決もここに乗る。

- **Test F1**: `submitReport` 成功時、報告URLのドメイン（+横取りスクリプト/リダイレクト先があればそれ）を Content Blocker ルール化し、App Group `filters/rules-self.json` に追記する。
- **Test F2**: 追記後に `reportedblocker` の reload が呼ばれる（自端末で即有効）。
- **Test F3**（安全）: クライアント側でも `isCriticalDomain`（決済/銀行/大手）相当をチェックし、自己報告でも critical は局所ブロックしない（誤爆で自分の銀行を遮断しない）。ユーザーは各自己報告ルールを個別にOFF/削除できる。
- **Test F4**（resolver合成）: `ReportedRulesResolver` は `rules-self.json`（自己）と `rules-reported.json`（グローバル）をマージして返す。重複排除。合計が報告拡張の上限（別枠15万）内。
- **Status二層化**: `ReportStatus` に `.appliedLocally`（「この端末で反映済」）を追加し、サーバ `.approved`（「全体反映済」）と区別。`detailDescription` を「この端末では即反映。全体反映は検証中（最大7日）」に。
- 検証: ルール生成・マージ・critical除外・status遷移の単体テスト。

## Phase 3: サーバ低スケール・ブートストラップ（kureho GO② 後・本番D1変更）
**狙い**: グローバル昇格が「3人到達不可」で永久ゼロな問題の緩和。**本番設定変更を伴うため kureho 承認必須**。
- 案A: 信頼レポーター（kureho の uuid_hash）の報告は L2 閾値をバイパスし L3-L6 の質ゲートのみで昇格。
- 案B: 初期 `DEFAULT_MIN_UUID` を一時的に下げ（例 1〜2）、L3(Tranco/critical)・L5(CDN)・L6(Playwrightスコア)の質ゲートで安全担保。ユーザーが増えたら戻す。
- どちらも `aggregation-threshold.ts` の `AggregationOptions`（minUuid/minIp/windowDays 注入可能）で実装可。**コードは変更容易、判断が要る**。
- 併せて GitHub Pages の `rules-reported.json` 404（配信元commit/ブランチ設定）を修正。

## 実行順と安全境界
1. **Phase 1 は GO 不要・ローカル完結・即着手可**（ただしPhase 2と同じファイルを触るので、F系設計を織り込んでから一度で実装すると手戻り無し）。
2. Phase 2 は kureho GO①（自己報告の即時ローカル適用方針）後。
3. Phase 3 は kureho GO②（本番D1/閾値変更）後。本番反映・課金に触れるため单独で承認を取る。
4. いずれも提出（reviewSubmission）は kureho の最終GO。審査中 build 19 の扱い（cancel/差し替え）も別途判断。

## オープンな技術確認（実装前に潰す）
- `App/ReportTab/ReportHistory*` がサーバ承認状態とどう同期するか（ローカル履歴のみか）→ status二層化の接続先。
- 報告UIが「黒画面に飛ばされた」ケースで、リダイレクト先URL/横取りスクリプトをどう取得・報告できるか（ユーザーが踏んだ後にどう報告動線に乗せるか）= 黒画面解決機能のUX設計。
- 報告拡張のルール上限と自己＋グローバル合算の予算管理。
