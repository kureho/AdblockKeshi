# AdblockKeshi v3 - 永続 TODO

## 次版で必ず反映

- [x] **リンク到着で購入画面（設定タブの Pro 購入画面）を閉じる**（2026-10-02・電光掲示板 1.0.1 と同じ漏れ。広告欄の「広告を消す」は無いアプリ）→ 53bce7a。次の版に同乗する。

## ★次版で必ず反映: DL 診断 v2 第 2 群の keywords（台帳 A-81・2026-10-01 kureho 承認）

kureho「推奨で進めていいよ」（10/1）＝**4.4.0 の次の版に同乗**（keywords だけの版は作らない）。提出版の ja localization に PATCH → GET で一致を確認 → `fastlane/metadata/ja/keywords.txt` も同じ値に揃える。

- **keywords**（88/100字・機械計測）: `消す,アプリ内広告,他アプリ,うざい,詐欺,フィッシング,セキュリティ,ポップアップ,迷惑広告,詐欺サイト,広告非表示,全画面広告,バナー,動画広告,勝手に開く,広告ブロッカー`
- name / subtitle は変えない。スクショ 1 枚目の副題（課金の条件を 1 語）は**保留継続**（画像は今回の範囲外）
- 正典 `/Users/oharakureho/claude/tasks/dl-diagnosis-2026-09-22/v2/08-execution-list.md` §13

## ★A-88: 報告→ブロックの作り直し（2026-09-27 kureho 方針確定・4.4.0 で出す）

kureho「この形で進める（推奨）」＝**土台の修理 → 週 1 回の判定 → 報告者への結果表示と送信エラーの修正を、まとめて次の版で出す。土台の修理は主要サイトの効きを前後で測りながら入れる**。
根拠: 点検 `/Users/oharakureho/claude/AdblockKeshi/tasks/report-pipeline-audit-2026-09-27.md`／調査 `/Users/oharakureho/claude/AdblockKeshi/tasks/report-method-research-2026-09-27.md`
**設計（正）: `/Users/oharakureho/claude/AdblockKeshi/tasks/a88-design-2026-09-27.md`**（事実表・5 部の方針・進め方 6 段）。**今どこ**（9/27 夕）: ①基準の計測 = 完了（設計書 §1 に表。今の既定は広告だけオンより漏れが多い・全量 2 分割で漏れ 44% 減）。③ サーバー = **本番反映済み**（入力判定の修正 Version 069c0f15・結果 API + migration 0015 Version 3821202d・Actions の試運転成功。戻し先 dbb96069-fcf1-43d3-8c57-b2f08f050aed）。★訂正: 本番の `abuse_log` に `invalid_url`・`spam_memo` は 0 件＝サーバーの誤判定で止められた人は実際にはいなかった。「報告できない」の主因候補はアプリ側のロボット確認失敗が無言で消える不具合（④で修正済み）。④ 送信エラー = ブランチ `a88-report-errors`（d3e93cd・コード差分とエラー画面 5 枚を確認済み・未 merge）。★ブランチはリポジトリ本体に残る（作業ツリーは scratchpad `/private/tmp/claude-501/-Users-oharakureho-claude/d0f3538c-1c3f-4d35-8011-035183a11cbd/scratchpad/a88-*-wt` だが消えても `git worktree prune` → `git switch <branch>` で戻せる）。★アプリ側の追加事項: 報告履歴はサーバーの報告 ID を保存していない（`App/Storage/LocalReportHistoryStore.swift` の id は端末で作った UUID）＝段 4 で `ReportHistoryItem` に任意項目としてサーバー ID を足す（4.3 以前の履歴は結果を引けない）。（↑9/27 夕の記録）

**★再開はここから（9/27 21:40・4.4.0 審査待ち）**: ✅**9/27 21:26 JST 審査に提出**（提出 ID 9c9fed3e-f184-4f28-8113-a5e4c92f2b06・build 10400）。main = 0db3b8f（kureho の push で確定）＋ a5b4277（作業記録）。作業ツリー 3 つは main に取り込み済みなので取り外し済み＝以後の作業はリポジトリ本体 `/Users/oharakureho/claude/AdblockKeshi` で行う。✅kureho が画面文言（9/27）とストア画像 4 枚（9/27「ok これですすめよう！」）を承認済み＝**承認済みの画面文言・画像は変えない**
1. ✅ セキュリティ 3 万件は 2 本目の末尾（3ffe37c）。計測 R_B（2 本とも）67.0 vs 今 77.0 ✅／R_S（基本保護だけ）116.0 vs 79.0 ❌
2. ✅ **R_S ❌ の原因と修正（1cdaf33）**: 基本保護を変換器の並び（要素隠し → 遮断）で詰めていたため、最後に繋ぐ EasyList の主要な遮断（doubleclick・pagead2・ads-twitter）が 2 本目へ押し出され、全部入れた例外（gpt.js を通す等）の先を止める規則が基本保護に無かった＝設計書 §1。修正 = `scripts/build_split_rules.py` の優先順を「重要 → 遮断 → 汎用の要素隠し → サイト別の要素隠し」に（2 本目に回るのはサイト別の要素隠し 15,052 件だけ）。同時にレビュー指摘 C（2 本目の伸び代をセキュリティ予算で数える）・D（説明の訂正）・F（`split_rules` からセキュリティ引数を外す・弱いテストの強化）・週次のセキュリティが前回の半分未満なら止める、を入れた（pytest 101 件通過）。配信ファイル・同梱ファイルは 19:5x に月次手順で作り直し済み（generated_at 2026-09-27T10:54:48Z・表示テストの期待値も更新）
3. ✅ **再計測 run8（9/27 20:23）**: T_S（基本保護だけ）68.0 ✅（A1S 79.0・A2S 62.0 の基準内・補正後 22.0）／T_B（2 本とも）67.5 ✅（A1N 77.0）。素の数で毎日新聞だけ +5.0 だが、増えた先はフィルタが毎日新聞で通す例外（cxense 等）＝補正後 0.0 同士。記録＝設計書 §1 の表
4. ✅ **アプリ側（9/27 20:30 頃）**: 指摘 A（時間切れでは前の 2 本目を残す）・B（同じ sha は 1 回だけ取得）を RED 確認 → 実装 → GREEN
5. ✅ 全テスト: pytest 101・xcodebuild 単体 497（skip 5）＋UI 4 すべて成功 → コミット 1cdaf33・5ef30b7・1fd1108（ブランチ a88-release-4.4.0・未 push）
6. ✅ 更新内容: 「一部のサイトが正しく動かないことがある問題を改善」を追加（計測で例外の部品が 13〜15 サイトで読まれることを確認した範囲。「開けない」とは書かない）。審査メモ 3. にも例外ルールの扱いを 1 文追加
7. ✅ **提出の準備（9/27 21:10）**: pre-deploy ✅／build 10400 を ASC 版 4.4.0（a8541870-9425-4ba9-b91c-449ec0ef9da9・PREPARE_FOR_SUBMISSION）に紐付け＋contactPhone 再設定／説明文・キーワード（「ポップアップ」入り）・更新内容・URL が ASC とブランチの `fastlane/metadata/ja` で全一致／プライバシー URL を正規形 `/privacy/adblock-keshi` に修正／提出前監査 ⑰㉑③⑱ ほか全部 0 件／㉓照合表 = `/Users/oharakureho/claude/AdblockKeshi/tasks/release-4.4.0-consistency.md`（スクショ 4 枚が旧画面だったので、旧スクショの画面部分だけを 4.4.0 の実画面に機械的に差し替え＝`/Users/oharakureho/claude/AdblockKeshi/tasks/screenshot-drafts-v440/final/`・ASC の 5 枚は md5 一致。撮影のため 0db3b8f で撮影モードだけ案内を隠した＝製品版は不変）
8. ✅ **提出（9/27 21:26）**: kureho が push を実行（0db3b8f で確定）→ Pages 反映後に CDN 13 ファイルと version.json・version-security.json の sha を全一致で確認 → 提出前監査 ⑰㉑ を回し直して exit 0 → Phase 5 ログ `~/.claude/logs/submission-precheck/2026-09-27-adblockkeshi-build10400.json` → 提出 → 4 点監査 OK（4.3.0 配信中・4.4.0 審査待ち・175 地域・pro=APPROVED）・審査用連絡先 ✅
9. ✅**2026-09-29 実施（4.4.0 は 9/28 08:17 JST 配信）**: 4 点監査・URL 照合・aso_snapshot・events.json（`f1ff174`）・プライバシー主張の台帳（実装照合して ok）・C-88/C-91 の広告消し記述の削除まで完了。LP とポリシーは app-support `4a006ff` で 9/29 に本番反映（kureho デプロイ）→ 本番ページで新文言を確認済み＝A-88 ① 完了。残りは下の 10 だけ。〔以下は当初の手順〕**承認されたら（承認後定型）**: 4 点監査（`python3 ~/claude/tasks/scripts/audit_4points.py`）・URL 照合（`audit_asc_urls.py`）・`aso_snapshot.py`・apps-metrics-dashboard の events.json に 4.4.0 を追記して push（施策級＝報告→ブロックの作り直し・開けないサイト対策）→ app-support の LP（`/Users/oharakureho/claude/app-support/src/lib/products.ts` 3943 行付近「週 7-14 日サイクル…」）とプライバシーポリシー（同 4235 行付近・報告 ID の送信が未記載）を 4.4.0 に合わせて直して本番反映（照合表 `/Users/oharakureho/claude/AdblockKeshi/tasks/release-4.4.0-consistency.md` の末尾）→ 台帳 C-88 から広告消しの記述を消す。A-88 は下の 10 の確認も済んでいたら行ごと消す（まだなら 10 だけを残す）
10. ✅**2026-10-02 確認**: 月次ワークフロー（monthly-filter-update）は 10/1 18:38 JST に成功（main 622d01e）。CDN の version.json・version-security.json の sha と実ファイル 6 本（blockerList / second-ads / security-rules / merged-rules / empty-rules / second-ads-sec）が全一致（version.json の generated_at 2026-10-01T09:39:58Z・148,800 件）＝**A-88 は台帳から削除済み**
11. 却下されたら: 提出スキルの「Cancel 発生時の必須プロセス」どおり Phase 1〜4 をやり直す（main が 4.4.0 の正本）

- [ ] ① 土台の修理（全員に効く）
  - ★9/27 実測: `docs/cdn/merged-rules.json`（広告＋セキュリティ両方オン用・13 万件）に**セキュリティ由来ルールが 0 件**＝`scripts/build_merged_rules.py` が広告（15 万件）→セキュリティの順に詰めて 13 万件で切るため。両方オンの人は詐欺サイト対策が効いていない
  - コンテンツブロッカーは 2 本ある（`ContentBlockerExtension`・`PopunderBlockerExtension`＝40 件だけ）＝2 本目の空きを使えば「捨てるルールを選ぶ」並べ替え（6/2 に yahoo.co.jp 70→0 の前例）を避けられる可能性
  - 手順: 上限なしの総数を実測 → 2 本への分け方を決める（例外ルールは同じブロッカー内でしか効かない点に注意）→ 主要サイトの効きを前後で測る仕組みを作る → 入れ替え
  - ★9/27 kureho 追加依頼「広告除去をオンにしてると閲覧できないサイトがある。うまく突破できるように」→ 主因候補 = 上限で捨てている例外（日本のサイト向け 309 サイト分。TVer・テレ朝・Lemino・ニコニコの動画部品 ima3.js、Yahoo!トップのタイムライン、ABEMA 等が今は無条件に止まる）。設計書 §0 の表・§1 に記録
  - ❌**C3 は不採用（9/27 夜に 2 つの誤りを発見）**: ①前回の分割計測の表は `C1B`=2 本とも有効・`C1S`=基本保護だけ（`split-measure/run2.sh` で確認）。「リスト単位で分けて基本保護だけの人の漏れ 40」は読み違いで、正しくは **241（今の 5 倍）**＝リスト単位の分け方は「2 本目が無効な人でも今より悪くならない」を満たさない。今の順番で切る C2（セキュリティ 3 万＋上限なし全量の先頭 12 万）の基本保護だけは **55.0**（今 52.5）でほぼ同等。②C3 は例外を全部末尾へ移したが、変換器の先頭側にある約 2,000 本の例外（`url-filter ".*"`＋`if-domain`＝「このサイトでは汎用の要素隠しをしない」）は**直前の汎用要素隠しだけを打ち消す位置**に置かれている。末尾へ移すとそのサイトの広告ブロックが全部外れる（計測サイトでは pointmall.rakuten・amazon.co.jp が該当）＝C3 の計測結果は使えない
  - ★**正しい形 = 「並び順を保ったまま、例外は両方に全部残し、例外以外のルールだけを 2 本に振り分ける」**（どのルールも、上限なしの 1 本のときと同じ例外が自分の後ろに並ぶ＝2 本の合わせ技が上限なし 1 本と同じ効き方になる）。変換器の並び（`SafariCbBuilder.createEntries`）: 汎用の要素隠し 1,571 → その例外 2,060 → サイト別の要素隠し 21,915 → 例外 23 → 遮断 193,498 → 例外 7,613 → 重要な遮断 84 → 重要な例外 113。上限の切り方は末尾から＝**今は重要ルールとサイト丸ごとの例外から先に捨てている**
    - 振り分け: 基本保護 = 例外全部＋（重要な遮断 → 要素隠し → 遮断を並び順）で埋める＋末尾にセキュリティ 3 万（例外で打ち消されない位置）。2 本目 = 例外全部＋残りの広告ルール → アプリが後ろにポップアップ・報告ルール・一時オフを足す
    - ★追加（9/27 夜）: **重複除去**（4 リストの重複 約 6.2 万件を「後ろのコピーを残す」で除く）と **ポップアップ対策の許可ホスト宛てのルールを基本保護へ最優先**（2 本目では後ろのポップアップ対策の例外に打ち消されるため）。詳細は設計書 §1
    - 上限: 基本保護 ≤ 148,800（149,000 − 一時オフ 200）／2 本目 ≤ 146,000（報告と一時オフの予約 2,000・ポップアップの伸び代 1,000）。あふれたら遮断の末尾（easylist 側）から捨て、例外と重要ルールは捨てない
    - ファイル（新名・旧版の形式は不変）: 基本保護 `basic-ads-sec.json`・`basic-ads.json`／2 本目 `second-ads-sec.json`・`second-ads.json`。セキュリティの枠は 3 万固定（週ごとの件数で振り分けが揺れないように）＝週次ジョブは `basic-ads-sec.json` の末尾のセキュリティ部分だけ入れ替える
    - ★**旧版にも効かせる**: 基本保護の新ファイルは今の `merged-rules.json`・`blockerList.json` と同じ形式・同じ上限内＝計測で基準を満たせば、その 2 つの中身を新ファイルで置き換えると 4.3 の利用者にもアップデートなしで「例外（開けないサイト対策）」と「詐欺サイト対策」が届く
    - 変換（CI）: SafariConverterLib を clone 後に `SafariVersion.rulesLimit` の上限を外す 1 行パッチ（当たらなければ失敗させる）→ 上限なし全量を 1 回変換
  - [ ] 計測（新しい形・判定基準は計測前に固定）: 基本保護だけ `P_S` vs 今の基本保護だけ `A1S`（merged 単体）＝**漏れの合計が A1S の 1.1 倍以内・1 サイトで平均 5 件以上増えるサイトなし・崩れの疑いが増えない**。2 本とも `P_B` vs 今 `A1N` ＝漏れが減る。例外の対象（ima3.js・posall・yads・newrelic）が P で読まれるか。★漏れは「P_B でも読まれる＝上限なし 1 本でも許可される通信」を除いた数でも出す（例外で正しく通した通信を漏れと数えないため）。広告だけオンの人は `Q_S`（basic-ads 単体）vs `A2S`（blockerList 単体）
  - [x] 実装（TDD・ブランチ `a88-rule-split`・未 merge）: `scripts/build_split_rules.py`（Python テスト 100 本 green）→ ワークフロー（月次 `scripts/convert.sh`: 上限を外した変換器〈版固定 2462a48〉→ 振り分け → `blockerList.json`/`merged-rules.json` を基本保護で置き換え＋`second-ads(-sec).json`＋sha／週次: merged の末尾のセキュリティだけ差し替え）→ アプリ（`Shared/SecondBlockerBase.swift`・Coordinator・更新後の作り直し）→ 同梱（月次手順を手元で試運転した出力＝変換 227,085・基本保護 148,800・2 本目 54,015/24,015・捨て 0・WebKit コンパイル成功）と `bundled-rules-info.json`。★**merge＝GitHub Pages への配信＝旧版の利用者にも即効く**ので、計測が基準を満たしてから merge する
  - 残る手: 例外でも直らない「広告ブロッカー検知の壁」は、既存の Safari 機能拡張（`PopupShieldExtension`・今は streamtape.com 限定）で壁外しスクリプトを動かせるが、全サイトで動かすには利用者の追加許可が要る＝体験が変わるので、C3 で直らないサイトが実在した時に kureho に案を出す
- [ ] ② 報告の週 1 回判定（Claude が日本のシミュレータの Safari で開く）→ そのサイト限定のルール → 朝のレポートに結果。止まっている `kureho_queue`・期限切れ `pending` にも出口。本番 DB は直接触らず、判定結果はリポジトリのファイル経由で定期処理が反映する形にする
  - ✅ 仕組み（9/27・commit 13d62bb）: 束づくり `scripts/review/build_review_packet.py`（月曜 06:30 launchd `com.kureho.adblockkeshi-review-packet`・plist は `~/Library/LaunchAgents/` に配置済み）／手書きルール `review/rules/`（旧版にも届く）／止まった候補は `candidates` で閉じる／朝のレポートに件数／起動時に新しい束を 1 回だけ案内（`~/.claude/hooks/session-start-trends.sh` 3 つ目）。手順 `/Users/oharakureho/claude/AdblockKeshi/tasks/a88-review-runbook.md`
  - [x] launchd への登録（9/27 21:45 kureho が `!` で bootstrap・エラー出力なし。毎週月曜 6:30 に起動。Claude のツールからは launchctl が権限で拒否されるため、登録状態の確認も kureho 側）
  - [x] 初回の判定（9/27）: 23 件＝ルール追加 6・アプリ内広告 6・再現せず 6・無効 4・サイト自身の広告 1／止まった候補 2 件を閉じた。サイト限定ルール 4 ファイル 8 本（`review/rules/2026-09-27-*.json`）は入れる前後を計測ツールで開き、広告の通信が消えて壁・崩れが出ないことを画面で確認してから配信
- [ ] ③ 報告者に結果（履歴に 確認中／反映済み／このアプリでは消せない種類。アプリ内広告の報告には「アプリ内広告ブロック」の案内）
- [ ] ④ 送信エラーの修正（ロボット確認の失敗を「もう一度」付きで表示・送信停止中は正しい文言・月の上限の文言・サーバー文言をそのまま出さない）
- [ ] ⑤ 約束の文言（報告画面「通常 7〜14 日」・説明文「アプリ内広告ブロックにも反映」）を②③でできることに合わせる
- [ ] 同乗: 下の B7（ja keywords に「ポップアップ」）・C-88 ディープリンク・オンボーディングの旧経路の疑い
- 見た目が変わる画面（③の履歴・④のエラー表示）は**既存の部品の使い回しだけで作り、提出前に kureho に画面を見せて OK をもらう**（memory `user_profession_designer`）

## 表示の誤りの疑い（2026-09-24 獲得調査でコード読みから記録・未修正・未配信）

オンボーディングの案内が旧経路「Safari → 機能拡張」のまま（`App/OnboardingView.swift:48`）。✅**9/27 確定**: Apple 公式ユーザガイド（support.apple.com/ja-jp/guide/iphone/iphab0432bf6/ios・iOS 27 版・9/27 取得）の手順は「設定 →『アプリ』→『Safari』→『機能拡張』」＝「アプリ」が抜けている。さらに下のボタン（`UIApplication.openSettingsURLString`）は「設定 → アプリ → 広告消し」に着地するので、そこから「アプリ」へ 1 つ戻る案内が要る。→ 4.4.0 の段 4（文言）で直し、kureho に見せる画面に含める。正典 `/Users/oharakureho/claude/tasks/owned-channels-2026-09-24/phase2/30-deliverables.md`「アプリ側の別タスク」。

## ★次版で必ず反映: ja keywords に「ポップアップ」（B7）

★2026-09-23 kureho 承認（獲得調査 段 1・台帳 C-91）。**この変更だけのために版を作らない**＝理由を問わず次に出す通常版に載せる（A-81 の画像待ちとは無関係・待たない）。**段 2（A-81 本体の name/subtitle/keywords）は今回承認外＝混ぜない**。提出版の localization へ keywords を PATCH → 提出前に GET で読み直して一致を確認 → 載せたら台帳 C-91 の該当アプリを消す。根拠 `/Users/oharakureho/claude/tasks/acquisition-research-2026-09-23/06-decision-package.md`
- **審査中の 4.3.0 には触らない**。4.3.0 の次の通常版に載せる
- kureho の実機確認は Mac 上の自動検証に置き換え（2026-09-23・kureho「テストコスト高いのでやらなくて済む方法」）: `/Users/oharakureho/claude/AdblockKeshi/scripts/check-popunder-rules-webkit.swift` で配信中の `popunder-rules.json` を WebKit（iOS Safari と同じ規則エンジン）に読ませた結果、**既知の広告網 33 件のスクリプトが全件停止・規則外の CDN は読み込める**。規則なしでは 17 件が実通信の応答待ち＝停止は規則によるもの。★止められるのは既知の広告網だけ＝説明文・宣伝文で「すべてのポップアップを消す」とは書かない。規則を更新したらこのスクリプトを再実行する
- 変更前（4.2.1・4.3.0 とも）: `広告,消す,ブロック,アプリ内広告,他アプリ,うざい,詐欺,フィッシング,セキュリティ,報告,進化`（49 字）
- 変更後: 上の末尾に `,ポップアップ`（56 字）
- ★このリポジトリは `fastlane/metadata/ja/keywords.txt` もある＝提出経路が deliver なら同じ値をそこにも入れる

## 2026-09-23: ディープリンク `adblockkeshi://<host>` 実装済み（C-88・次の版に同乗）

対応 host: `home`（ブロッカータブ）/ `report`（報告タブ）/ `settings`（設定タブ）。
アプリ内イベントの deepLink には `adblockkeshi://home` 等を使う。

## Issue #36 Sub-2: Privacy Redaction (2026-06-27・spec/plan とも reviewer Approved)

実装計画: `~/claude/docs/superpowers/plans/2026-06-27-adblock-privacy-redaction.md`
spec: `~/claude/docs/superpowers/specs/2026-06-27-adblock-privacy-redaction-design.md`
方針: 2層 redaction（層A=14日 status非依存 backstop=correctness floor / 層B=既存ジョブの status遷移に畳み込む optimization）。tldts で eTLD+1・url_path_hash 維持・abuse_log は reason分岐。

- [x] **【実装前ゲート】l6_check カラム不在バグ — ローカル修正完了（remote 適用のみ kureho 承認待ち）** (2026-06-27 systematic-debugging)
  - 根本原因（実ログで確定）: `scripts/validation/playwright-validate.ts:62` が `SET l6_check=?` するが migration(0001-0009) に `l6_check` 不在（`l3/l4/l5_check` のみ）。daily-validation 直近8 run は全 success・L6出力 `{promoted:0,rejected_score:0,rejected_scope:0}` = **UPDATE は一度も到達していない**（到達すれば `no such column: l6_check` で exit(1)→run赤）。よって**潜在バグ（時限爆弾）**: validatePage が成功する広告ページが1件来た瞬間に daily-validation 全体 crash。
  - ✅ migration `0010_rule_candidates_l6_check.sql`（`ALTER TABLE rule_candidates ADD COLUMN l6_check TEXT`）作成
  - ✅ 回帰テスト `workers/tests/scripts/playwright-validate-l6-schema.test.ts`（PRAGMA ガード + 実 UPDATE）RED(`no such column: l6_check`)→GREEN。全 197 テスト pass
  - [x] **remote D1 適用完了（2026-06-27 kureho 承認）**: list --remote で 0001-0009 applied / 0010 pending を確認(tracking 同期)→ `db:migrate:prod` で適用 → `No migrations to apply!` + PRAGMA `has_l6_check:1` で検証。爆弾解除完了。
  - 注: l4_check は L6 が selector-scope 判定を吸収したため dead column 化（意図的・今回触らない）
- [x] **【validation reliability】validating 永久滞留 — 修正完了（2026-06-27 kureho GO・本番反映済 main `4d2ed28`）**: 根本原因＝`runPlaywrightValidate` が validatePage の全例外を transient 扱い（`catch{continue}`）で**試行上限も terminal 脱出も無し** → 構造的に開けない URL（tpead.net 等の動画 CDN）が status='validating' に永久滞留（昇格も reject もされず LIMIT 200 プール占有 starvation + <14日は full-URL PII 保持）。修正＝試行カウンタ `validation_attempts`（migration **0011** additive INTEGER NOT NULL DEFAULT 0）を追加し、連続失敗が MAX(3) に達したら terminal `status='rejected_unreachable'`（url を eTLD+1 縮約）に落としてプールから外す。NULL-url も同経路。両 UPDATE に `AND status='validating'` guard（再実行安全）。TDD（unit 10 + schema guard 3）+ Codex review 反映で全220 pass。
  - 本番手順: remote に 0011 適用（`validation_attempts` 列 INTEGER NOT NULL DEFAULT 0 を PRAGMA で検証・既存行は 0）→ main へ ff push（DB先・コード後）。
  - 滞留 0ad49530（tpead.net・age 3日）は kureho 判断で**自然 drain**: deploy 後の daily-validation（cron 03:00 UTC・1日1回）3回で自動的に rejected_unreachable + url 縮約（age 3日 ≪ 14日層A なので層A より先に終端化）。
  - 残（軽微・別バグ class ではない）: cdn-check / tranco-check も status='validating' を読むが、それらは即 status を遷移させるため滞留しない（playwright 段のみが skip ループだった）。
- [x] Chunk 1: `normalizeURL`(tldts・冪等) + redactPII 冪等性テスト（6e0f2ff / 5ba4e0b）
  - 注: tldts は plan の `^6.x` に対し **`^7.4.4` が install された**（getDomain API 互換・全テスト pass・**2026-06-27 本番 workflow run success で実環境動作も実証済み**）。事後確認のみで可。
- [x] Chunk 2: 層A retention backstop（status非依存14日・reason分岐）+ workflow配線（`if: always()`）（dc7a656）
- [x] Chunk 3: 層B aggregation per-group redact + L6 per-row redact（946f211 / ffbb59d）
- [x] **【最終統合レビュー指摘・修正完了】層A floor starvation（523bc93）**: reports/rule_candidates の SELECT に `url LIKE '%/%'` を追加し既縮約行を LIMIT 対象外に。これが無いと aged 行 10000 超で未縮約 long-tail が永久 starve され 14日 floor が非自己修復で崩れる。**plan line-361 の paging=YAGNI 判断を意図的に覆す**（throughput でなく correctness 問題）。floor self-heal 回帰テスト追加・全 208 pass。
- [x] **【実測で解決】abuse_log の floor self-heal = 選択肢(c) 現状維持＋監視**: 2026-06-27 prod 実測で 14日超・url非NULL の abuse_log 行 = **0件**（reports backlog=3 / candidates backlog=1 も LIMIT 10000 を遥か下回り初回1パスで drain）。starvation は現時点で実在しないため marker 列/時間窓は過剰。slash 述語非適用は妥当。**将来 abuse_log が育った場合に備え hourly run の abuse_log_redacted 件数を監視**（恒常的に増えるなら marker 列を再検討）。
- [x] **【申し送り→モニタ実施 2026-07-29】rule_candidates の first_reported_at 起点 over-redaction**: 層B L6 redact は status 遷移時に full URL を eTLD+1 化するが、first_reported_at が 14日超の候補は層A でも縮約され得る。spec 準拠・privacy 安全側だが L6 selector 抽出の yield をわずかに下げる可能性（reviewer nit）。**モニタ結果 = 実害ゼロ**: 直近7日（7/22〜7/29）の daily-validation は passed/queued/promoted/rejected 全て 0（候補流入ゼロ）・hourly-aggregation 直近 run の層A backstop も reports/candidates/abuse_log redacted 全て 0 → 縮約対象自体が無く yield 低下は発生していない。監視経路 = **GitHub Actions ログ（CF 認証不要）**: daily-validation の L6 出力 JSON + hourly-aggregation「Retention backstop」step の出力（wrangler 直クエリは非対話環境で OAuth 更新不可 = CLOUDFLARE_API_TOKEN 必要のため不採用）。v4.0 無料化で報告が流れ始めたら同ログ行で再確認。
- [x] **Chunk 1-3 本番反映 完了（2026-06-27 kureho「反映して」承認）**: migration 0010 適用 → main へ ff push(10 commit `cde14ae..3a82aa1`) → hourly-aggregation を workflow_dispatch で smoke test = **success**（Retention backstop step ✓）→ backlog 実測 reports 3→0 / candidates 1→0 で**設計通り縮約を実証**。Workers deploy は src ロジック不変のため不要。全11 workflow を push 前監査（macos/push トリガー課金リスク無し）。
  - 申し送り(軽微): GitHub Actions の Node20 deprecation 警告（actions/setup-node@v4→v5 へ将来更新・緊急性なし・run は success）。
- [x] **Chunk 4: backfill 完了（2026-06-27 kureho sign-off → 実行 → 検証 green）**: whitelist 方式（terminal status のみ redact・in-flight は構造的に非対象・advisor 承認）でスクリプト2本実装（`scripts/migration/redact-existing-urls.ts` + `run-redact-existing-urls.ts`）+ TDD 4テスト（commit `fae515b`・全212 pass）。dry-run 実測 = reports **2** / candidates **0** / abuse_log **0**（層A floor + smoke-test で aged backlog 既 drain 済のため near-zero・予想通り）。snapshot（9.95MB・100,026行）取得 → AskUserQuestion で per-table 件数 + 縮約後ドメイン提示 → GO 取得 → 実行。
  - 実行方式: CF_API_TOKEN が手元に無いため tsx 直実行はせず、テスト済み `normalizeURL` で eTLD+1 を計算 → wrangler(OAuth) 経由で `UPDATE reports SET url=? WHERE id=?` ×2（縮約対象・redact ロジックは tsx 経路と同一・transport だけ差異）。reports 2件を tokyomotion.net / tpead.net へ縮約（changes:1 ×2）。
  - 検証: dry-run COUNT 再実行で reports/candidates/abuse_log すべて **0**（成功基準=post-COUNT=0 達成）+ 該当2行が eTLD+1（slash 無し）であることを目視。snapshot は PII（完全URL）を含むため検証パス後に削除。
  - 注: line-15 の validating 滞留候補（0ad49530 tpead.net）は **rule_candidates の in-flight = 設計通り非対象**（candidates count=0 と整合）。floor fix の slash 述語方針は Chunk 1-3 で確定済（line-20）。

## Plan C/D 残項目 — stale 究明監査結果（2026-06-27 実施・kureho 承認）

⚠️ **下記セクションは v3.0 ローンチ前(2026-06-07)の計画。アプリは既に App Store live(3.4.0)・Workers/D1/全 workflow 本番稼働中**（本セッションで本番 D1 に対し hourly-aggregation/daily-validation を実行・成功で実証）。各項目を live 実コード/状態と照合した結果、**ブロッキングな未実装はゼロ**。分類:

### ✅ 出荷済み（DONE）
- **Task 4.4 実 ReportAPIClient 接続**: `AdblockKeshiApp.swift:9` が実 `ReportAPIClient`(URLSession+Workers) を注入。Stub は未使用。`ReportHistoryViewModel` も Stub history extension 撤去済。
- **Chunk 5 moat 表示**: `ContentView.swift` CompletedView:193 が `versionInfo?.moatDisplayText` を InfoRow 表示（version.json 経由）。
- **Plan D（E2E + ASC 提出）**: アプリが **3.4.0 で live**（v3.0 出荷後に 3.3→3.4 と更新）。提出・審査・Dashboard 連携は完了済み（MEMORY「学習する広告消し3.4.0 live」2026-06-26）。
- **Turnstile token cache**: `ReportAPIClient.swift:63` に scope 別 token cache(expiresAt 付き) 実装済。TTL 内はスキップ＝当時の「UX 議論」は出荷実装で解決。

### 🔄 SUPERSEDED（出荷時にアーキ進化・該当機能は別実装に置換／デッドコード化）
- **Chunk 2 StatusBannerView 統合**: 出荷 UI は state ベースの `CompletedView`/`OnboardingView`/`ErrorView`(blockerState 分岐)。`StatusBannerView.swift` は**完全未参照のデッドコード**。
- **Chunk 3.3 起動時 fetchAndUpdate + Tab B flag ガード**: 出荷版は報告タブを**常時表示**(flag ゲート無し)・RemoteConfigStore を起動時に呼ばない。`RemoteConfigStore.swift`/`FeatureFlags.swift` は**自テストのみ参照の未配線デッドコード**。
- 自己学習は「報告反映(popunder)」拡張に統合済（旧 reportedblocker 廃止・`AdblockKeshiApp.swift:92-94`）。ReportedGlobalSync/PopunderGlobalSync/CombinedRuleListCoordinator が当時計画に無い進化版アーキ。

### ⏸️ deferred nicety（非ブロッキング・出荷版で動作・将来検討）
- **server_salt dynamic 化**: `loadServerSaltFromBundle()` の bundle static のまま。出荷版で正常動作。spec 厳密化の nicety（互換性影響なし）。
- **Chunk 6 ASC App Privacy / app-support privacy ページ**: アプリ live = Apple 必須の privacy は配備済みのはず（app-support repo / ASC 上）。**本リポ外**のため未直接確認。気になれば app-support の `apps/adblock-keshi/privacy` と ASC Nutrition Label を別途監査。
- **運用 compatibility_date `2024-09-09`**: 本番 wrangler が deploy 時 override。Workers 稼働中＝実害なし。
- **運用 Tranco Top 100k 制限**: weekly sync 稼働中。Top 1M 復帰は D1 batch API 移行が前提（将来）。

### 🧹 デッドコード除去 — 完了（2026-06-27 kureho 承認・main `38b30f1`）
- 削除6ファイル: `App/Views/StatusBannerView.swift` / `App/RemoteConfig/`(RemoteConfigStore+FeatureFlags+tests) / `App/Networking/StubReportAPIClient.swift`。
- 全リポ grep で参照ゼロ確認 → 削除 → xcodegen 再生成 → `xcodebuild build`/`test`(iPhone 17) 共に exit 0（全テスト pass・回帰なし）。
- `docs/cdn/feature-flags.json` は公開 CDN アーティファクトのため残置（孤立だが無害）。

（2026-06-08 generated、2026-06-27 stale 究明監査で live 3.4.0 と照合し全項目を再分類）

## 4.0.1 hotfix — モバイル回線(NAT64/DNS64)全断障害（2026-07-29 発覚・kureho 承認済み方針=案A）

根本原因: ハードコード Cloudflare 上流が IPv6単独+NAT64/DNS64 のモバイル網でキャリア DNS64 を迂回 → 全断。
Wi-Fi(デュアルスタック)では正常 = 7/15 E2E が Wi-Fi のみだったため出荷前に検出できず。

- [x] promotionalText 注意書き反映（kureho `!` 実行 2026-07-29・ASC 再 GET で反映確認済み・審査なし即時）
- [x] TDD: SystemDNSResolvers.parse（resolv.conf → nameserver 抽出）
- [x] TDD: UpstreamPlanner.plan（sentinel/loopback 除外・dedupe・Cloudflare fallback 後置）
- [x] TDD: DNSHealthMonitor（無応答検知 → rotate → 全滅で stopTunnel = watchdog フェイルセーフ・reset() 含め12テスト GREEN）
- [x] PacketTunnelProvider 配線（起動前 snapshot・単一上流+rotation・受信ループ常時再武装・path change reassert）
- [x] DNSSettingsView 文言更新（:89 端末内判定・:91 通常は回線 DNS/取得できない場合のみ代替 DNS）
- [x] sim 全テスト GREEN（iPhone 17・TEST SUCCEEDED）→ 3レビュー完了 + 指摘全反映（下記）
- [x] 実機 E2E 合格（モバイル回線・KPhone Debug 版・2026-07-29 ラウンド3）: トグル ON で yahoo.co.jp 解決 / apple.com 素通し / doubleclick.net ブロック / アクティブブラウジング下 132 秒生存 + watchdog 誤発火なし = v4.0.0 障害解消を実機確認
- [x] **実機で Wi-Fi 切替障害を検出 → 修正**: Wi-Fi ON 切替で reassert の snapshot リトライ予算（0.5s×4=2秒）が DHCP の DNS 配布前に枯渇 → cancel でトグル勝手 OFF（20:11:45 実測。死因は fetchLastDisconnectError 診断テストで「ネットワーク切替後に回線の DNS を取得できない…」文言を実機から取得し確定）。修正 = `ReassertRetryPolicy` 新設で予算 30 秒化（TDD RED「2.0<30.0」→GREEN・回帰テスト付き）。診断用 `TunnelDisconnectDiagnosticsTests` 追加（sim は XCTSkip）
- [x] **切替テスト合格（30 秒予算版・2026-07-29 20:27〜20:28）**: トグル ON → Wi-Fi ON → Wi-Fi OFF → 機内モード往復 → 手動 OFF を完走。途中のエラー停止なし（監視 = 起動 20:27:23 / 消滅 20:28:03 の1サイクルのみ・fetchLastDisconnectError = nil = 最後の切断は正常切断）
- [x] **Codex レビュー（30 秒予算化・codex-rescue read-only）→ must-fix 1件修正済み（`497f5a9`）**: stopTunnel 後に遅延完了した setTunnelNetworkSettings ハンドラが `activateUpstreams()` で上流を再生成し得る穴 → 再適用側・解除側の両完了ハンドラに `guard !isShuttingDown` 追加。30 秒予算は「妥当」判定。should-fix（reassert 状態遷移の単体テスト化 = provider の DI リファクタ要）は最小 hotfix 方針で見送り（4.0.2 以降の候補）。sim 315 テスト GREEN + UITests PASS で再検証済み
- [ ] 実機検証の残り（任意・優先度低）＝**スリープ復帰直後のみ**（suspend-gap 処理・長時間放置が必要で自動化不能。kureho 最小手順: 夜トグル ON のまま就寝 → 朝 Safari で yahoo.co.jp が開き、設定アプリの VPN 表示が ON のままなら合格）。他 2 件は検証済み（2026-07-29）: **他 VPN 排他 = Apple 公式 docs で裏取り済み**（NEVPNManager.isEnabled:「Only one Personal VPN configuration can be enabled simultaneously on the system. If another Personal VPN configuration is enabled, then this property will be automatically set to false」・NETunnelProviderManager は NEVPNManager 継承 = システムが排他を保証・アプリ側対応不要）/ **受信エラー→再武装 = ユニットテスト済み**。**⚠ xcodebuild test は実機でアプリ再インストール → 稼働中 extension が死ぬ。生存測定と併用不可（手動 Safari プローブで代替）**
- [x] 4.0.1 リリース時: MARKETING_VERSION 4.0.1 / build 10001 採番済み・reviewNotes に上流変更明記済み（stage_v401.py・審査時回答との整合更新）・app-support products.ts:3938(FAQ)/:4026(privacy) 文言更新はブランチ `adblock-401-dns-wording`（380aa5f・build 検証済み）で準備済み — **deploy は 4.0.1 配信確認後**（live 4.0.0 の実挙動と食い違わせない）
- [x] 提出済み（2026-07-29 21:04 JST・kureho「残りも全て進めて」= 提出 GO と解釈・precheck ログ 2026-07-29-adblockkeshi-build10001.json）: SUBMISSION_ID=19738462-fd05-4d00-993c-9d95c843bbd9 state=WAITING_FOR_REVIEW・releaseType=AFTER_APPROVAL・4点監査 PASS（live 4.0.0 無傷・175地域・IAP pro=APPROVED）・promotionalText は 4.0.1 側でクリーン版（障害注意書きは配信と同時に自動解消）

### 3レビュー（Codex adversarial=no-ship 4件 / Codex review=2件 / code-reviewer=条件付き承認）指摘 → 反映済み7領域

1. [x] reassert の settings nil 失敗無視 → error 明示処理 + cancelTunnelWithError（fallback 直行の再導入防止）
2. [x] 停止後の受信ループ再武装復活 + stopTunnel クロスキュー競合 → upstreamGeneration トークン + isShuttingDown + workQueue.async 化
3. [x] 期限切れ/未知 ID 応答で watchdog リセットされる穴 → recordResponse を forwarding.resolve 成功後へ移動
4. [x] snapshot 空で無警告 fallback → reassert 側は 0.5s×4 リトライ + 取れなければ cancel（fallback-only 運転拒否）
5. [x] 末尾上流の範囲外 rotate（no-op で DNS 握り続け）→ startUpstream をラップアラウンド化（monitor の rotation 予算と意味論一致）
6. [x] Cloudflare 固定化（NAT64 で部分全断が無期限化・watchdog では検知不能）→ ①サスペンドギャップで health.reset() ②電波 unsatisfied 中は watchdog 停止+reset ③60s ごとの index 0 復帰プローブ（example.com A クエリ・本線非干渉）
7. [x] reassert 中の path 変化握りつぶし → pendingReassert で消化 / UI 文言の fallback 整合

## ⚠️ description の「報告タブを使わない限り外部通信しない」が不正確（2026-08-17 検出・**文面確定済み / 8-26-27 提出待ち**）

live v4.0.3 の ja description:

> 【データの取り扱い】
> 報告タブを使わない限り、本アプリは外部通信を行いません。

実際にはフィルタ更新のための通信が、報告タブに触れなくても走る:

- `App/AdblockKeshiApp.swift:81` — 起動時に `Task.detached { await DNSListUpdater.shared()?.updateIfNeeded() }`
- `App/ContentView.swift:94` — 起動時に `RuleUpdater`（CDN = GitHub Pages からルール DL）
- `App/BackgroundTaskManager.swift:43` — バックグラウンド更新でも同じ経路

同段落の後半「報告タブから送信されるデータは、URL とメモのみ。閲覧履歴・氏名・連絡先・位置情報は
一切送信しません」は**正しい**（更新はダウンロードのみで個人データを送らない）。誤っているのは
「外部通信を行いません」という言い切りだけ。育つフィルタが売りである以上、更新 DL があること自体は
むしろ訴求になるので、隠す理由がない。

★**2026-08-18 追記: 4.1.0 は 8/17 22:59 JST に配信済み（`appStoreState=READY_FOR_SALE` / itunes lookup で
実配信を確認）。「審査中だから触らない」という下の前提はもう成立しない。** ただし description は live 版を
直接編集できない項目なので、**次の提出（8/26-27 の ASO 判定後）に載せる**のは変わらない。
★**live 4.1.0 の description にも「報告タブを使わない限り、本アプリは外部通信を行いません。」はそのまま残っている**
（4.1.0 提出時に直したのは別の 2 行 = 診断情報の明記と報告の反映経路）。**是正は未消化**。

★**手元 `fastlane/metadata/ja/description.txt` は 2026-08-18 に live 値へ同期し、そのうえで下の是正文面を投入済み。**
同期前は 2026-07-15 の版で、`upload_to_app_store`（`skip_metadata: false`）を回すと live の 4.1.0 文面を
巻き戻す状態だった。**現在の手元は「live 4.1.0 + 是正 1 箇所」＝次の提出で出したい値**なので、
ちりつも・StillCam と同じ「手元が新しい」状態。deliver しても巻き戻らない。

→ 差し替え文面（**2026-08-18 kureho 承認済み**・投入済み）:
```
報告タブを使わない限り、あなたのデータが外部へ送信されることはありません。
（フィルタを最新に保つためのダウンロードのみ行います）
```
残タスクは **8/26-27 の ASO 判定後の提出に載せること**だけ（live 版の description は直接編集できないため）。

### 追加検出（2026-08-18・同じ台帳監査で 2 件目）

`audit_store_privacy_claims.py` が拾ったもう 1 つの主張 **「・端末内で処理し、外部サーバーは経由しません」も不正確**だった。
ブロック判定が端末内なのは正しいが、**回線の DNS を取得できない場合は Cloudflare 1.1.1.1 へ転送する**
（`/Users/oharakureho/claude/AdblockKeshi/PacketTunnelExtension/PacketTunnelProvider.swift:52` の `fallbackUpstreams`・
plan は `/Users/oharakureho/claude/AdblockKeshi/Shared/DNS/UpstreamPlanner.swift:8` が `systemServers + fallbacks` の順で
候補を作るため、`systemServers` が空 or 全て除外条件に該当すると先頭が Cloudflare になる）。
→ **「・ブロック判定は端末内で行い、当社のサーバーを経由しません」**に差し替え済み（手元 fastlane 投入済み・同じ提出に載る）。

**この差し替え文面は 2026-08-18 に kureho 承認済み**（8/17 の承認は「報告タブ」の行だけだったため、別途取り直した）。

**LP 側にも同じ主張が 4 箇所あり、そちらも是正済み**
（`/Users/oharakureho/claude/app-support/src/lib/products.ts`: worldSection / FAQ / **プライバシーポリシー本文 2 箇所**）。
ポリシー本文は Cloudflare fallback を元から明記していて事実としては正確だったが、
同じ文の中で「判定もクエリも端末内で完結し」と書いていて**自己矛盾**していたため、
「ブロック判定は端末内で完結し」に狭めた。加えて「報告タブを使わない場合、本アプリは引き続き外部通信を一切行いません
（Content Blocker のフィルタ更新を除く）」の除外リストに **v4.0 の名前解決の転送**が入っていなかったので追記した。

★**app-support は Vercel 手動デプロイなので本番 kureho.app にはまだ旧文言が出ている**
（`curl https://kureho.app/apps/adblock-keshi | grep -c 外部サーバーは経由しません` = **6**）。
**ローカル `npm run build` の出力では 0 件**（新文言「当社のサーバーを経由しません」が同じ 6 箇所に入れ替わることを確認済み。
6 = 2 ユニーク文字列 × HTML 本体 / JSON-LD / RSC payload の重複）。**デプロイ後に同じ curl を打って 0 になることを確認する**。
なおデプロイすると **おたよりカレンダー LP の新学期シーズナル更新（`717ba5f`・8/15）も一緒に本番に出る**
（未デプロイなのはこの 2 commit のみ＝ちりつも画像更新 `19a09bb` とミダシ LP 解除 `6b3ba31` は live 反映済みを curl で確認）。
