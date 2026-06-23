# PR #29 マージ前ハードニング記録（2026-06-23）

新機能追加ではなく、Safari Web Extension の実機動作保証・無言失敗の排除・責務分離・CI・提出前品質の確定。

## 1. MAIN / ISOLATED world 責務分離（最重要修正）

**問題**: 旧 `popup-shield.js` は MAIN world で動きながら `browser.runtime.sendMessage` を呼んでいた。
MAIN world では content script 専用 Extension API が使えず、件数報告は**動かない前提**だった。

**修正**: 2 ファイル＋別 world 登録に分離。

| ファイル | world | 責務 | Extension API |
|---|---|---|---|
| `popup-shield-core.js` | MAIN | 純関数の判定エンジン | 無し |
| `popup-shield-main.js` | MAIN | window.open/anchor.click/overlay 介入・traversal・判定実行・**ready/blocked イベント発行** | **無し**（静的検査で保証） |
| `popup-shield-bridge.js` | ISOLATED | MAIN からのイベント受信→**schema 検証**→`runtime.sendMessage` で background へ | 有り |

- MAIN→ISOLATED は **window への CustomEvent（一方向・最小情報）** のみ:
  `{ version:1, type:"ready"|"blocked", reason:<許可済みのみ>, frame:"top"|"child" }`。URL・ページ内容は構造的に載らない。
- bridge は: event.target===window 検証 / 固定 event 名 / version:1 / 許可済み type・reason のみ受理 /
  余分 property 破棄 / 不正 frame は top にフォールバック / 60件/秒のレート制限。
  **forged event でも最大「端末内件数の増加」のみ**（権限操作・任意コマンドは一切実行しない）。
- 静的検査テスト（`popup-shield-static.test.js`）で MAIN world ファイルに
  `browser.runtime / chrome.runtime / browser.storage / chrome.storage / sendMessage(` が無いことを CI で保証。

## 2. 実稼働状態の管理（偽の有効状態の排除）

**問題**: 旧 `background.js` は `registerContentScripts(...).catch(function(){})` で登録失敗を握りつぶし、
画面 ON でも実際は未登録の「偽の有効状態」が起き得た。

**修正**: `desiredEnabled`（ユーザー設定）と `registrationState`（実稼働）を分離。

- storage: `desiredEnabled / pausedHosts / registrationState / lastRegistrationError /
  lastRegistrationAttemptAt / lastReadyAt / registeredMatches / counts`。
- `registrationState` enum: `off / registering / registered / active / unsupported / failed`。
  - registered = Safari API 登録成功・ページ内 ready 未確認 / active = bridge から ready 受信＝実際に動いた証跡。
- 登録失敗は握りつぶさず **正規化分類のみ保存**（`api_unavailable / main_world_unsupported /
  registration_rejected / permission_missing / unknown_registration_error`）。**元エラー全文・URL・OS 機密は保存しない**。
- world MAIN / API 非対応は `unsupported` へ遷移。失敗は `failed`。
- popup UI は状態別に表示（オフ / 登録中 / 有効=動作確認待ち / 有効・動作確認済み / この端末では利用不可 /
  登録に失敗）。**トグル ON だけでは「有効」と表示しない**。failed/unsupported 時は再試行ボタン。

## 3. Content Script 登録方式（Phase 4）

- MAIN(`popup-shield-main`) と bridge(`popup-shield-bridge`) を **別 ID** で登録（world MAIN / ISOLATED）。
- reconcile は決定論的: registering→unregister(旧 ID `popup-shield` の cleanup 含む)→register→registered。
  desiredEnabled=false / 全 pause なら何も登録しない（off）。ready 受信で active。
- 純関数（`popupShieldPlan` / `buildRegistrations` / `classifyRegistrationError` / `deriveUiStatus`）を
  node でテスト（ON で 2 登録 / OFF で解除 / pause 除外 / 中間状態自己修復 / 失敗→failed / 非対応→unsupported /
  retry / startup 復元 / 重複登録しない）。

## 4. 診断（Phase 5）

popup の「詳細（診断）」に privacy-safe な状態を表示: registrationState / desiredEnabled / lastReadyAt /
lastRegistrationError 分類 / registeredMatches / pausedHosts / ブロック件数 / reason 別件数。
**URL 全文・ページタイトル・DOM・閲覧履歴は表示も保存もしない。**

## 5. CI（Phase 7）

`.github/workflows/pr-popup-shield.yml`（timeout / concurrency / cache / secret 不要 / push しない）:
- **linux-checks（無料）**: pytest / Node 単体（core/bridge/plan/health）/ 静的検査 / 生成物再生成一致(bundle==cdn) /
  manifest JSON 検証 / Web Extension リソース構造 / manifest⇔project version 一致。
- **macos-xcode（kureho 承認済み [paid-approved-by-kureho]・PUBLIC repo=無料）**: xcodegen→Swift 単体+WebKit compile→Release build。
- 既存 `popunder-rules-update.yml` を main 限定トリガーに修正（feature branch の git push 失敗＝PR 偽 red を解消）。

## 6. アイコン（Phase 9）

既存アプリアイコン（文字なし青シールド・ブランド整合）を `sips` で機械リサイズし
`PopupShieldExtension/Resources/images/icon-{16,32,48,96,128,256,512}.png` を生成。manifest の icons / action.default_icon に設定。
（強力モード専用の差別化バリアント=shield+bolt 等は将来のデザイン課題。現状は流用シールドで App Store 受理可能。）

## 7. 検証マップ更新（自動化範囲）

- 自動（CI・無料 Linux）: ルール生成 / Node 単体 / 静的検査 / 生成物一致 / manifest / 構造 / version。
- 自動（CI・macOS 承認済み）: Swift 単体 + WebKit compile + Release build。
- 自動（ローカル headless）: 決定論 fixture（MAIN/ISOLATED 分離後も全 vector block + ready/blocked イベント PII 無し）/
  実 streamtape protection（popup 0・player 3/3・media 3/3）。
- **未自動（実機・kureho 手動）**: 強力モード ON→Safari 拡張有効化→権限付与→streamtape での 3 cold load×10 操作の目視。
  iOS 17 実機での registerContentScripts world:MAIN 実動作。→ `device-verification.md` 参照。
