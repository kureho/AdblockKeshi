# Streamtape 強力モード 実測検証（修正前後の比較）

- 対象: `streamtape.com` の動画埋め込みページ（`/v/<REDACTED>`）
- 計測日: 2026-06-23 / 計測環境・コンテンツ保護方針は `baseline.md` と同一
- ハーネス: `tasks/streamtape-hardening/harness/measure.js`（baseline / `--static-sim` / protection の 3 モード）

## 三段比較（各 3 コールドロード合計・各ロード 10 操作）

| モード | 実 popup 総数 | うち cross-site | current-tab redirect | プレーヤー生存 | media 発火 |
|---|---|---|---|---|---|
| **baseline（保護なし）** | **22**（7/7/8） | **19** | 0 | 3/3 | 3/3 |
| static-sim（L1 既知網 + L2 第三者script全block 相当） | 7（2/3/2） | 7 | 0 | 3/3 | 3/3 |
| **protection（強力モード popup-shield 注入）** | **0** | **0** | 0 | **3/3** | **3/3** |

- **静的ルールは不十分**: L1+L2 を network 層で適用しても（third-party script 4件/ロード block）、サイト本体の
  first-party inline `window.open` popunder は残存（7件）。
- **強力モードは十分**: popup-shield（MAIN-world で window.open を介入）注入で **cross-site popup 0 件**、
  かつ **プレーヤー生存 3/3・正規 media 発火 3/3**（誤ブロックなし）。ページは真っ黒にしていない。

## 受入条件 → 検証手段マップ（自動化範囲の明示）

| # | 受入条件 | 検証手段 | 結果 |
|---|---|---|---|
| 1 | 対象 URL 3 回コールドロード | measure.js --runs 3（baseline/protection 各3） | ✅ |
| 2 | 意図しない新規タブ 0 | protection の realPopups（context.on('page')） | ✅ 0 |
| 3 | 意図しない別ウィンドウ 0 | 同上（window/tab 区別なく page 生成を計数） | ✅ 0 |
| 4 | 広告ドメインへの current-tab redirect 0 | route で top-frame cross-site nav を計数 | ✅ 0 |
| 5 | about:blank 経由の広告遷移 0 | baseline で about:blank open 計装 + protection で popup 0 / fixture STUB | ✅ |
| 6 | プレーヤー UI 初期化 | protection の player_alive（video/player DOM 検出） | ✅ 3/3 |
| 7 | 正規 media を誤ブロックしない | protection の media_request（media/playlist リクエスト発火） | ✅ 3/3 |
| 8 | 真っ黒で解決していない | player 生存 + media 発火で確認（host-block ではない） | ✅ |
| 9 | 主要サイト回帰 green | 既存 Swift 全テスト + WebKit compile | ✅ Swift 122（0 fail・既存 App Group 1 skip） |
| 10 | bundle == cdn 一致 | build_popunder_rules.py + SHA 照合 + pytest | ✅（同一 SHA・再生成漏れ検出 test 付き） |
| 11 | WebKit compile green | PopunderRuleCompileTests（L2 代表 + 出荷 JSON 全体） | ✅ 2/2 |
| 12 | 全自動テスト green | core/plan unit(node) + fixture(node) + pytest + Swift | ✅ Node 28・fixture 11・pytest 14・Swift 122 |
| 13 | 新規権限の必要性・プライバシー説明 | design.md / privacy.md / アプリ内日本語説明 | ✅ |
| 14 | 修正前後の実測比較 | 本表（baseline 19 → protection 0） | ✅ |

### 自動化できた範囲 / できなかった範囲（正直な区別）

- **自動化済（headless ハーネス・実 streamtape）**: 受入条件 1〜8（popup 0・プレーヤー/メディア生存）。
  ＝「**エンジンロジックが、発火フレームに override がある状態で、実 streamtape の popunder を end-to-end で無害化する**」ことの実証。
- **自動化済（決定論 fixture・top-frame のみ注入＋traversal）**: 「**iOS 17 の同一オリジン about:blank フレーム
  カバーを、親→子 traversal で実現できる**」ことの実証（`PopupShieldExtension/Tests/fixtures/run-fixture.js`）。
  ※ protection の live run は Playwright が全フレーム注入する“楽観側”のため、iOS17 のフレーム制約は fixture で別途担保。
- **自動化できなかった（提出前の実機確認が必要）**:
  1. iOS 17 実機 Safari で `scripting.registerContentScripts({world:"MAIN"})` が override を実際に注入・実行するか
     （Apple エンジニア言明では 16.4+ サポートだが 2023 年・実地で動かないとの報告もあり＝device 確認必須）。
  2. 強力モードのトグル ON→Safari 設定→実機 streamtape での目視（3回×10操作）。
  3. クロスオリジン広告 iframe 由来の popunder（host_permissions 非対象フレーム）は content script が届かず対象外＝既知の限界。

## 修正後の生成物

- popunder ルール（静的・defense-in-depth）: 40 ルール。bundle == cdn 一致（SHA: 下記コマンドで照合可）。
  ```
  shasum -a 256 PopunderBlockerExtension/Resources/popunder-rules.json docs/cdn/popunder-rules.json
  ```
- 強力モード（Safari Web Extension）: `PopupShieldExtension/`（manifest + background + popup-shield-core/js + native handler）。

## 再現コマンド（URL は env 渡し・ファイルに残さない）

```
cd tasks/streamtape-hardening/harness
NP="$HOME/.npm/_npx/<hash>/node_modules"   # or any playwright-core path
export TARGET_URL='https://streamtape.com/v/<REDACTED>'
NODE_PATH="$NP" node measure.js --url "$TARGET_URL" --mode baseline   --runs 3 --settle 8000
NODE_PATH="$NP" node measure.js --url "$TARGET_URL" --mode baseline --static-sim --runs 3 --settle 8000
NODE_PATH="$NP" node measure.js --url "$TARGET_URL" --mode protection --engine ../../../PopupShieldExtension/Resources/popup-shield.js --runs 3 --settle 8000
```
