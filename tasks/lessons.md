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
