# AdblockKeshi 教訓集

## 2026-07-29: 上流 DNS のハードコードは NAT64/DNS64 モバイル網で全断する（4.0.0 本番障害 → 4.0.1 hotfix）

### 事象
v4.0.0 の DNS 型アプリ内広告ブロック（NEPacketTunnelProvider）が、IPv6 単独 + NAT64/DNS64 のモバイル回線で名前解決全断＝通信不能。Wi-Fi（デュアルスタック）では正常なため、提出前 E2E（7/15・Wi-Fi のみ）で検出できず本番流出した。

### 根本原因
上流 DNS を Cloudflare 1.1.1.1 にハードコードしていたため、キャリアの DNS64 変換（IPv6 単独網が IPv4 リソースへ到達する要）を迂回し、合成 AAAA が得られず全滅。

### 修正（4.0.1・build 10001）
1. 上流はシステム DNS snapshot 優先・取得不可時のみ public DNS fallback（UpstreamPlanner）
2. DNSHealthMonitor watchdog（無応答検知 → rotate → 全滅で stopTunnel フェイルセーフ）
3. ネットワーク切替 reassert の DNS 再取得予算は DHCP 配布遅延を見込んで 30 秒（2 秒では実機で枯渇 → トグル勝手 OFF を実測）

### 教訓
1. **ネットワーク系機能の E2E は Wi-Fi とモバイル回線の両方を通す**（可能なら IPv6 単独網）。回線種別は sim-blind な検証軸（skill submitting-ios-build Phase 2.5 と同型）
2. **上流サーバーのハードコードは「現在の網が提供する経路」を壊す**。まずシステム提供値・fallback は後置
3. 失陥時に黙って壊れない watchdog（検知 → 自動復旧 → 最終的に安全側停止）を最初から入れる

---

## 2026-06-12: 月次フィルタ更新が runner イメージ更新で silent fail（6/1〜6/12 の12日間停止）

### 事象
`monthly-filter-update.yml` の 2026-06-01 schedule 実行が `python3 -m pip install --user pyyaml` で failure（PEP 668 externally-managed-environment）。GitHub の macos-latest イメージ更新で Homebrew Python が素の pip install を拒否するようになった。気づいたのは 6/12 に kureho がアプリ内「フィルタ最終更新: 2026/05/30」表示で異変を察知してから。

### 修正
`--break-system-packages` フラグ追加（576b11e）。使い捨て CI 環境なので安全。workflow_dispatch で実走検証し、version.json 更新 → GitHub Pages CDN 反映まで確認済み。

### 教訓
1. **月次など低頻度 schedule は失敗に気づきにくい**。失敗時に何も通知が無い構造だった。github-actions-audit.sh は timeout/hang 監査のみで「failure 通知」はしない
2. **runner イメージ更新は予告なく依存を壊す**。pip 直叩き・brew 依存・OS バンドルツールに依存する step は破壊リスクを持つ
3. v2.1.0 で入れた「フィルタ最終更新日のアプリ内表示」が異変検知に機能した（ユーザー向け機能が監視としても働いた）

### 同時対応
checkout@v4 → v5 を全 9 workflow に適用（2026-06-16 からの Node.js 24 強制対応、8d71a3d）。

---

## 2026-06-03 v2.1.0: iOS は Safari スタートページを開く公開 API を持たない

### 事象
v2.0 の CompletedView に置いた「Safari を開く」ボタンが `UIApplication.shared.open(URL(string: "https://www.apple.com"))` を呼んでいて、押すと Apple 公式ページに飛ぶ UX 不具合になっていた。kureho からは「Safari のスタートページを開きたい」と要望。

### 調べたこと
- iOS には Safari の **スタートページ / 新規タブ** を直接開く公開 URL スキームが存在しない
- `UIApplication.shared.open` は `http://` / `https://` の URL しか受け付けず、`about:blank` 等は無視される
- 過去動いた `x-web-search://` は Apple のプライベート URL スキーム扱いで App Store 審査リジェクト事例あり

### 判断
代替案 (google.co.jp / yahoo.co.jp / 自社サポートサイト / ボタン削除) を kureho に提示し、「動線無いほうがスッキリ」でボタン削除を選択。Safari Content Blocker の CTA は「設定完了したらユーザーは自分の使い方で Safari を使えばよい」前提で十分。

### 適用範囲
Content Blocker / ブラウザ補助系アプリ全般。「Safari を開く」CTA を入れたくなった時は、まず本当に必要か疑う。必要なら中立的な検索エンジン URL を渡すしかないが、押し付けがましさのデメリットを比較する。

---

## 2026-06-03 v2.1.0: フィルタ更新日は CDN generated_at を bundle 同梱で読む

### 事象
「ブロックルールがいつ最終更新されたか」をユーザーに見せたかった。候補は (a) 端末 DL 時刻 (b) CDN 生成日時 (c) 両方。

### 判断
**(b) CDN 生成日時** を採用。理由:
- 開発者 (kureho) がフィルタを頻繁に更新している事実をユーザーが認識できる = 信頼形成に寄与
- (a) 端末 DL 時刻は CDN 側に変更が無くても更新される (= 嘘の鮮度感)

### 実装ポイント
- `docs/cdn/version.json` の `generated_at` (ISO8601 UTC) を `VersionInfoStore` で App Group → bundle の順に解決
- 初回起動 (CDN DL 前) でも表示できるよう `App/Resources/version.json` を **bundle 同梱**
- `scripts/convert.sh` で `docs/cdn/version.json` 生成と同時に `cp` で App bundle 版も同期
- 月次 `.github/workflows/monthly-filter-update.yml` の `git add/diff` に App/Resources/version.json も追加 → アプリ再リリースなしに bundle 同梱版を最新化

### 適用範囲
本番ルールセット / マスターデータを CDN 配信する全アプリ。「鮮度を見せたい時は CDN 側の生成時刻」「初回 UX を壊さないために bundle 同梱の組合せ」がパターン。

---

## 2026-06-11 報告フォーム: UIViewRepresentable の UITextField は横方向優先度を下げないと行を突き破る

### 事象（ユーザー報告 2 件）
1. 長い URL を入力すると入力欄がカードからはみ出し、「貼り付け」ボタンが画面外に押し出される
2. メモ欄（複数行 TextField）のキーボードを閉じる手段が無く、送信ボタンが押せない

### 根本原因
1. UIViewRepresentable で包んだ UITextField は intrinsicContentSize の幅がテキスト長に比例して伸びる。SwiftUI はそれを尊重するので、HStack/Form の行幅を突き破る。`setContentHuggingPriority(.defaultLow, for: .horizontal)` + `setContentCompressionResistancePriority(.defaultLow, for: .horizontal)` が必須
2. `TextField(axis: .vertical)` は Return キーが改行になるため、キーボードツールバーの「完了」ボタン（`ToolbarItemGroup(placement: .keyboard)`）+ `.scrollDismissesKeyboard(.interactively)` を付けないとキーボードを閉じられない

### 検証方法
XCUITest ターゲット `AdblockKeshiUITests` を新設（`UITests/ReportFormUITests.swift`）。DEBUG 起動引数 `--show-report-tab` で報告タブ直行。red-green 確認済み（修正前: 両テスト失敗 / 修正後: pass）

### 適用範囲
SwiftUI アプリ全般。UIViewRepresentable で UIKit テキスト入力を包む時・複数行 TextField を置く時は毎回この 2 点をチェックする。

---

## 2026-08-09 報告機能: 「拒否 = abuse」設計が正直ユーザーを自動 ban する（問い合わせで発覚）

### 事象（お問い合わせ「報告の送信に失敗しました」と何度も出てくる・メール未入力）
D1 実測で確定: 問い合わせ主は `apps.apple.com`（広告のリンク先 = App Store ページ）を 22:30〜22:49 JST に 9 回報告 → 全て critical_domain 400 で拒否 → 各拒否が abuse_log に加算され **3 件閾値で L1 auto-ban（24h）発動**。別ユーザーも `search.yahoo.co.jp` で同型 4 回。直近 7 日の報告失敗は全件この構造起因。

### 根本原因（設計レベル）
1. ユーザーは「広告配信元ドメイン」ではなく**見えている URL（広告が出たページ / 広告のリンク先）を報告する**。それは高確率で critical-list 上の大手ドメイン
2. critical_domain 拒否を ban 材料に数えていた（悪意と誤操作を区別しない）
3. エラー表示が「入力エラー (url): critical_domain: apple.com is protected」という英語技術文言で、ユーザーは理由を理解できず再試行 → ban が加速

### 修正
- **サーバ側（即時・push だけで反映）**: `BAN_ELIGIBLE_REASONS` を ban-engine-core に一本化し critical_domain を除外（rate_limit/spam_memo/invalid_url は維持）。実行系は hourly-aggregation（GitHub Actions）なので Worker deploy 不要
- **クライアント側（次回アプリ更新に同梱）**: 送信前に `CriticalDomainGuard` で弾いて日本語説明をインライン表示 + サーバ 400 のフォールバック文言も日本語化（`APIError.criticalDomainProtected`）

### 教訓・適用範囲
- **「サーバが拒否した」と「ユーザーに悪意がある」は別物**。ペナルティ集計に入れてよいのは「正直なクライアント UI からは物理的に発生しない」失敗だけ（例: クライアント検証を通らない invalid_url）。クライアントから普通に発生し得る拒否を ban 材料にすると、機能を熱心に使うユーザーから順に封じられる
- 検証・拒否ルールはクライアントとサーバで**同じリストを送信前に効かせる**（サーバだけにあると失敗往復 + abuse 加算だけが残る）
- 問い合わせフォームのメール任意入力は「返信不可」問い合わせを生む。原因を運営側データで特定できる設計（今回は D1 の abuse_log）が命綱

## 2026-09-02 4.2.0 提出
- `fastlane beta` の archive が「No Accounts: Add a new account in Accounts settings」／「provisioning profile に Apple Development: Created via API (8AQ38HX67R) が無い」で落ちる → Xcode にログインするのではなく、`build_app` の `xcargs` に `-allowProvisioningUpdates -authenticationKeyPath <p8> -authenticationKeyID 8AQ38HX67R -authenticationKeyIssuerID <issuer>` を渡す（`4fef73f`・GenbaCamera/oshilog と同型）。署名は API キーで cloud signing させる
- 4.2.0 は実機確認をスキップして出した（kureho 判断）。配信後に「壊れ報告が効かない」「一時停止が戻らない」が来たら、end-to-end の報告経路・per-site 例外の Safari 反映・DNS 一時停止の自動再開を最初に疑う

## 2026-09-06 週次 Tranco 同期が D1 無料枠の 4 倍を毎週焼いていた（Cloudflare アラートで発覚）

### 事象
Cloudflare から「D1 の rows_written 1 日上限（10 万行）を超過」のアラートメール。Gmail 上ではこれが初回だが、D1 Analytics（GraphQL）で日次を引くと **8/9・8/16・8/23・8/30・9/6 の日曜が全て 40 万行ちょうど**、平日は 0〜30 行。つまり超過は初回ではなく、少なくとも 1 か月前から毎週発生していた。

### 根本原因
`weekly-tranco-sync.yml`（日曜 02:00 UTC）が毎週 `DELETE FROM tranco_top_1m` → 10 万行 INSERT の**全入れ替え**をしていた。D1 の rows_written はインデックス更新も 1 行として数えるため、`domain TEXT PRIMARY KEY` の暗黙インデックス + `idx_tranco_synced_at` で **1 行あたり実質 4 行** = 40 万行。無料枠の 4 倍。超過後は当日 24:00 UTC まで D1 書き込みが全部エラー（= 日曜 16:00 JST〜月曜 09:00 JST は報告受付が落ちる窓だった）。

### 修正
D1 から Tranco を外し、唯一の読み手である `daily-validation.yml`（GitHub Actions の Node プロセス）が CSV を直接メモリに載せる方式へ。`decideL3` は元から in-memory `Set<string>` を受け取る設計だったので、判定ロジックは無改造。週次同期 workflow とスクリプトは削除。DL は週替わりキャッシュキーで週 1 回に維持。実測 10 万件 57ms / 87MB。

### 教訓・適用範囲
- **「無料枠に収まるか」は行数ではなく〈行数 × (1 + インデックス数)〉で見積もる**。D1 に限らず、行課金のマネージド DB は暗黙の PK インデックスも書き込みに数える
- **参照専用の静的リストを DB に置かない**。読み手が 1 本のバッチだけなら、そのバッチがファイルを読めば DB 書き込みはゼロになる。実際この repo の `build_security_rules.py` は同じ Tranco を最初からファイルとして扱っていた＝先例が repo 内にあった
- **全入れ替え（DELETE→再 INSERT）は行課金では最悪手**。差分が数 % でも毎回 100% 分を払う
- **無料枠の超過は「アラートが来た日」ではなく「実測の時系列」で確認する**。今回もアラート初回 = 超過初回ではなかった。`wrangler d1 info <db>` の 24h 値と Cloudflare GraphQL の `d1AnalyticsAdaptiveGroups` で日次が取れる
- **Cloudflare の超過アラートは「枠の期間が閉じた直後」にもう 1 通来る**。2026-09-07 09:12 JST（= 00:12 UTC）に届いた 2 通目は、本文の「上限がリセットされる」時刻が **9/7 00:00 UTC = 受信の 12 分前**で、9/6 分（UTC 日 9/6）の締めの通知だった。**新規の超過と読み違えない**。判定方法 = ①メール本文のリセット時刻が受信時刻より前なら過去分 ②`wrangler d1 info` の `rows_written_24h` が既知の 1 イベント分ちょうど（今回 400,000）なら当日分は 0
- **GitHub Actions の cron は数時間ずれる**。`0 2 * * 0` の同期が実際に走ったのは 02:58〜07:54 UTC（6〜9 月の全 13 回）。「cron 時刻に走った前提」で UTC 日の切り分けをすると原因を取り違える。`gh run list --json createdAt` の実測で見る
- **10 万行のテーブルを消しても rows_written はほぼ増えない（実測）**。2026-09-07 10:38 JST に migration `workers/migrations/0014_drop_tranco_top_1m.sql` を `wrangler d1 migrations apply --remote` で適用 → `rows_written_24h` 400,000 → **400,006**（+6・うち 2 行は `d1_migrations` への記録分）、`database_size` **6.91 MB → 123 kB**。Cloudflare の公式 pricing は「DDL は read/write 行の両方に寄与しうる」としか書いておらず未文書だったが、**DELETE で消すと 40 万行なのに DROP なら実質 0 行**。大きなテーブルの廃止は行を消さずテーブルごと落とす
- **D1 の使用量メトリクスは数分遅れる**。適用直後は `rows_written_24h` も `write_queries_24h` も 1 も動かず、7 分後に +6 / +2 が反映された。「増えていない」を直後の 1 回で判断しない
- ★安全ガード `~/claude/.claude/hooks/destructive-command-guard.sh` は Bash コマンド文字列に `DROP TABLE` が含まれるだけで exit 2 する（heredoc で SQL を書くのも不可）。**migration ファイルは Write ツールで作り、適用は kureho が実行する**のが通し方
- **修正が効いたことの確認（2026-09-15）**: `wrangler d1 info` が `rows_written_24h` 0 / `write_queries_24h` 0、`num_tables` 6・`database_size` 123 kB（6.91 MB には戻っていない）、`gh workflow list` に `weekly-tranco-sync` 無し、日曜 9/13 の run は hourly 系だけ、コード内の `tranco_top_1m` 参照はコメントとテストのみ。★**24h 窓のメトリクスは「先週の日曜」を含まない**ので、週次の再発を事後に見るなら ①DB サイズが元に戻っていないこと ②その書き込みを起こす workflow が存在しないこと、で裏取りする（日次を直接見たいなら D1 Analytics の GraphQL が要る）。

---

## 2026-10-03: トグル OFF→ON の直後にアプリを閉じると、Safari に「広告ブロックなし」のルールが残り続ける（4.4.0 まで）

### 事象
kureho「広告ブロック、一回外して再度 on にしたら広告が表示されるようになった」。画面のトグルは ON のまま、Safari では広告が出る。アプリを開き直しても直らない。

### 根本原因（シミュレータで再現・修正後に治ることを確認）
1. トグルの reload は投げっぱなし（完了も失敗も見ない）。Safari のコンパイル担当（`ContentBlockerLoader`）はアプリの子プロセスとして動くので、ON の直後にアプリが終了すると基本保護（約 15 万件・数秒〜十数秒）のコンパイルも止まり、OFF 時に作った「詐欺サイトだけ」のリストが Safari に残る（ON の 1.5 秒後に終了させて再現。OFF のコンパイルは 1 秒弱で終わるので非対称になる）
2. 起動時に基本保護を読み込み直すのは CDN に差分があるときだけ＝**画面の状態（state.json）と Safari の実際のリストがずれても、誰も気づかず直さない**

### 修正
- reload を全経路 `App/ContentBlockerReloader.swift` に集約: 依頼の瞬間に未完了の印（世代番号つき・UserDefaults）を残し、Safari から成功が返った時だけ消す → 起動時・前面復帰時（状態確認の XPC が終わった後。返らなければ 20 秒後）にやり直す（やり直し 3 回で諦める。回数は Safari へ実際に渡した分だけ数え、新しい依頼が来たら数え直す）。依頼の瞬間から beginBackgroundTask。reload は 1 本ずつ・返事が 120 秒来なければ次へ進む・順番待ちの間に呼び出し元が打ち切られたら始めない
- 印は**書き換えの前**に付ける＝トグルの状態保存の前、2 本目・例外用 combined の書き込みと削除の前（builder の `willModify`）。書き換え後の依頼は `Task` で後回しにせずその場で出す（書き換え〜依頼の間に終了されると、次の起動では meta が一致して作り直しも読み込みも起きないため）。トグルは基本保護の完了を待ってから、実行延長を取って 2 本目を作り直す
- 更新後の初回起動で 2 本とも 1 回読み込み直す＝この仕組みが無い版で止まったまま残った端末を治す。ポップアップ対策の CDN 同期は中身が変わったときだけ読み込む（毎回の前面復帰で重いコンパイルを走らせ、やり直しの上限も数え直していた）
- 「書き換え中」を数える（`beginModification` / `finishModification`）: 書き換えの直前に印を付けて数を足し、数が残っている間は Safari の成功でも印を消さず、前面復帰のやり直しも始めない。終わりで数を戻してから読み込む。CDN の取得（`FilterDownloader` の `willReplace`＝中身が変わるときだけ）・ルール更新（`RuleUpdater` の `willApply`＝最初の書き込みの前に 1 回）・combined の作り直し（`ModificationScope`）の 3 か所すべてに通した
- 合成ファイル（combined）は入力（標準・残り・ポップアップ対策）から作るので、入力を差し替えたら必ず作り直しを予約する: ルール更新はどのファイルが差し替わっても予約、ポップアップ対策の取得は中身が同じでも毎回予約（4.4.0 と同じ。入力のハッシュで判定するので変化が無ければ何もしない）。取得したファイルは中身が同じなら書かない

### 教訓
1. **reloadContentBlocker は「呼んだら反映される」ではない**。完了まで数秒〜十数秒かかり、その間にアプリが止まれば反映されない。呼び出しは成否を記録し、終わらなかったら次の機会にやり直す
2. **「画面の状態」と「実際に効いている状態」が別の場所にある仕組みは、ずれたときに戻す経路を最初から作る**（起動時に毎回つじつまを合わせる・未完了の印を残す）。片方向に書くだけだと、一度ずれたら永久にずれたまま
3. **「完了を待つ」仕組みを入れたら、完了が来ない場合と、待っている間に重なった依頼の数え方まで決める**（レビューで、返事が来ないと後ろの読み込みが全部止まる・重なった依頼を「失敗」と数えて早く諦める・順番待ちのまま終わった分まで回数に数える、が見つかった）。**印は「書き換える前」に付ける**（2 回目のレビューで、状態保存の後・ファイル削除の後に付けていた経路が残っていた）
4. **「書き換えの前に印」だけでは足りない。書き換えの最中に終わった読み込みの成功で印が消える**（3 回目のレビュー）。世代番号は「依頼の新旧」しか区別できず、「その読み込みが書き換え前のファイルを読んだか」は分からない＝書き換えの始まりと終わりで区切り、その間の成功は信じない。あわせて、変更のたびに**ファイルを書く経路を全部数え上げる**（ルール更新の途中書き込み・CDN 保存が、印の無いまま残っていた）
5. **「重い処理を減らす」ための近道は、それが一緒に担っていた役目を消していないか確かめる**（4 回目のレビュー）。「中身が同じなら何もしない」で読み込みと一緒に作り直しの予約まで止め、4.4.0 では毎回の作り直しで隠れていた「標準だけの差し替えで combined が古いまま」「途中で止まった作り直しが次の起動まで残る」を表に出した。Safari が読むのは合成ファイルなので、**入力のファイルを読み込み直しても成功は「最新」を意味しない**＝入力を変えたら作り直しまでつなぐ
6. シミュレータでは「ホームに戻る」だけでは止まらず再現しなかった。**アプリの終了（XCUIApplication.terminate）まで試す**と再現した＝バックグラウンドの厳しさは実機と違うので、最悪側（終了）で確かめる
