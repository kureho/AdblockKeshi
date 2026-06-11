# AdblockKeshi 教訓集

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
