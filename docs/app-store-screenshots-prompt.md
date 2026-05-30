# App Store スクショ 5枚 生成プロンプト (ChatGPT gpt-image-1)

## 使い方
1. 下記「添付ファイル」をすべて ChatGPT に投入
2. その下の「プロンプト」全文をコピペ送信
3. 生成された 5 枚を `~/Downloads` に保存
4. ファイル名を `01-onboarding.png` 〜 `05-family.png` にリネーム
5. 私が `~/claude/AdblockKeshi/fastlane/screenshots/ja/` に配置

## 添付ファイル（5つ送る）
- `/Users/oharakureho/claude/AdblockKeshi/docs/screenshots/raw/01-onboarding.png` (アプリ Onboarding 画面)
- `/Users/oharakureho/claude/AdblockKeshi/docs/screenshots/raw/02-completed.png` (アプリ Completed 画面)
- `/Users/oharakureho/claude/AdblockKeshi/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (アプリアイコン)

## プロンプト

```
これは iOS Safari Content Blocker アプリ「広告消し」の App Store 提出用スクショ 5枚を作るための素材です。
添付したアプリ画面とアイコンをベースに、以下 5 枚を統一トーンで生成してください。

【共通仕様】
- サイズ: 各 1290 x 2796 px (iPhone 17 Pro Max 縦長)
- 出力: PNG、5枚別ファイル
- レイアウト: 上 30% に大きなキャッチコピー（黒太字、白〜淡い水色背景）、下 70% にアプリ画面 or イラスト
- フォント: iOS システム標準風 (San Francisco / Noto Sans JP)
- カラー: アプリのブランドカラー (#007AFF Safari blue + 白 + 淡い水色グラデ)

【厳禁】
- ¥ / 円 / Free / 無料 / 割引 / お得 / セール 等の価格表現は一切入れない
- 文字以外の余計な装飾（虹色グラデ、大量のキラキラ、emoji）禁止
- アプリ画面の UI を改変しない（添付画像をそのまま枠で囲って配置）
- 「サブスクなし」「買い切り」は表記OK（価格には触れない範囲）

【5枚の中身】

### 1枚目: コア訴求
- キャッチ: 「Safariの広告を、シンプルに消す。」（黒太字、サイズ大）
- サブ: 「これ1つ、入れるだけ。」（少し小さく、グレー）
- 下半分: 添付の「01-onboarding.png」を iPhone のフレーム（白縁、角丸）に入れて配置
- 背景: 淡い水色グラデ

### 2枚目: 「設定は1分。あとは、何もしなくていい。」
- キャッチ: 「設定は1分。」「あとは、何もしなくていい。」(2行、黒太字)
- 下半分: 添付の「02-completed.png」を iPhone フレームに入れて配置
- 背景: 淡い緑グラデ（CompletedView の雰囲気に合わせて）

### 3枚目: 「Before / After」
- キャッチ: 「広告だらけの記事ページが…」「すっきり読める」(2行)
- 下半分: 左右並び。左 = 「Before」全画面広告だらけのニュース記事サイト風モックアップ（実 URL や実サイト名は入れない）、右 = 「After」同じ記事レイアウトで広告領域が空白 or 記事に置き換わってる
- 上部の小ラベル: 左「Before」/ 右「After」（赤と緑の小バッジ）

### 4枚目: 「Safariの中だけで、ちゃんと効く」
- キャッチ: 「Safariの中だけで、ちゃんと効く。」
- サブ: 「アプリ内の広告には触れません。」（プライバシー誠実訴求）
- 下半分: iPhone の Safari 拡張機能設定画面のモックアップ（iOS 標準設定画面風、トグルが ON）+ 矢印で Safari アイコンを指す
- 背景: 白〜薄グレー

### 5枚目: 「ご家族のiPhoneにも、ぜひ」
- キャッチ: 「ご家族のiPhoneにも、ぜひ」
- サブ: 「設定画面ゼロだから、教えやすい。」
- 下半分: 親子のシンプルなイラスト or 「親→子」の iPhone 渡しイラスト（生成時に温かいトーン）
- 背景: 淡いオレンジ〜白グラデ

【最終確認】
- 5枚すべてに価格表現がない
- 5枚通してブランドカラー（青）の統一感がある
- 各キャッチコピーが日本語として自然
- iPhone フレームの中身は添付画像をそのまま使う（生成画像で UI を変えない）

最後に「価格表現チェック OK」と一言添えてください。
```

## 配置先 (生成後)
- /Users/oharakureho/claude/AdblockKeshi/fastlane/screenshots/ja/01-onboarding.png
- /Users/oharakureho/claude/AdblockKeshi/fastlane/screenshots/ja/02-setup.png  
- /Users/oharakureho/claude/AdblockKeshi/fastlane/screenshots/ja/03-before-after.png
- /Users/oharakureho/claude/AdblockKeshi/fastlane/screenshots/ja/04-safari-only.png
- /Users/oharakureho/claude/AdblockKeshi/fastlane/screenshots/ja/05-family.png

