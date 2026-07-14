## 概要

Streamtape 等の動画サイトで多発するタブ乗っ取り型 popunder を根絶するため、**強力モード（Safari Web Extension `PopupShieldExtension`）**を追加。あわせて、実機検証中に発見した**自己学習フィルタによる top-level document 誤ブロック**を根治した。

最終的に Safari の機能拡張は現状の4本構成（標準フィルタ / 自己学習フィルタ / ポップアップ広告対策 / 強力ポップアップ対策）のまま。拡張本数の集約（4→2）は本 PR のスコープ外で、本 PR マージ後に別 PR で行う。

---

## 実装 1: 強力モード（PopupShield Web Extension）

- **MAIN / ISOLATED world 分離**: ページコンテキストで `window.open` 等を介入する `popup-shield-main.js`（MAIN world）と、Extension API を扱う `popup-shield-bridge.js`（ISOLATED world）を分離。
- **MAIN world から Extension API を直接呼ばない**: MAIN 側は `CustomEvent` bridge 経由で ISOLATED に通知する設計（静的テスト `popup-shield-static.test.js` で MAIN world に Extension API が無いことをロック）。
- **bridge の strict schema validation**: event の許可キー（version/type/frame/reason）と reason whitelist・rate limit を実装。
- **状態管理の堅牢化**: `desiredEnabled`（ユーザー意図）と `registrationState`（登録実態）を分離し、`off / registering / registered / active / unsupported / failed` の状態機械で管理。registration error を握りつぶさず明示状態に反映。stale ready のクリア・reconcile の直列化を実装。
- **本番アイコン同梱・split target 配線済み**。

## 実装 2: 自己学習フィルタ誤ブロックの根治（本セッションで発見・修正）

### 症状
実機で **4拡張すべて ON にすると Streamtape 等のサイト自体が Safari で開けなくなる**事象を発見。一度起きると端末に永続。

### 根本原因（`superpowers:systematic-debugging` で確定）
クライアント側の自己報告ファストレーン `Shared/ReportedRuleBuilder.swift` の `blockRule(forURL:)` が、**報告された URL の host を `resource-type` / `load-type` 無制限の `block` ルール**にしていた。
- → top-level document（訪問中ページ自体）を含む全リクエストを遮断。
- → 端末 `rules-self.json` に永続（除去経路なし）。
- ユーザーは Safari に見えるページ URL を報告しがちなので、Streamtape 上で報告すると streamtape.com 自体がブロック対象になった。
- **bundle / CDN / サーバ昇格パイプラインは無実**（ライブ CDN は空配列、サーバは `css-display-none` cosmetic のみ出力で `block` 経路ゼロ）。詳細は `tasks/streamtape-hardening/PHASE1-root-cause-evidence.md`。

### 修正（多層防御・TDD）
1. **生成ルールの安全化**: `load-type:["third-party"]` ＋ `resource-type`（`document` を除外した image/style-sheet/script/font/raw/svg-document/media/popup の8種）を付与。訪問中サイトは first-party なので絶対に遮断されず、その host が他サイトで third-party 広告として現れる時だけブロックする。
2. **判定述語** `Shared/ReportedRuleSafety.isDocumentBlockingRisk(_:)`: `block` かつ「document 除外 + third-party 限定」でないものを risk と判定。生成側・merged 側・migration の3点で適用。
3. **起動時 migration（既存端末治癒）** `App/AdblockKeshiApp.migrateReportedRulesIfNeeded()`: 旧版で生成された危険な self-rule を起動時に purge。ネットワーク非依存・idempotent。self の除去**または** merged 内容の変化があった時だけ Content Blocker を reload。
4. **merged 生成時 strip** `Shared/SelfReportedRulesStore.rebuildMerged()`: 経路を問わず document-block を merged から除外。dedup を url-filter ではなくルール内容で行い、cosmetic（url-filter `.*` 共有）の取りこぼしも解消。
5. **サーバ不変条件をテストでロック** `workers/tests/lib/l6-decision.test.ts`: `decideL6` が `block` を絶対に出さない（cosmetic のみ）ことを検証し、将来の退行を検知。

---

## 実機結果（kureho 目視・2026-06-23）

- device: KPhone / iPhone 17 Pro（iOS 26 系）／ tested commit `e3d625b`（→ docs `7912257`）／ app 3.4.0 build 24
- device build / install / launch: **成功**。起動時 migration を含む build を起動。
- **4拡張すべて ON で Streamtape 表示可能**（kureho 目視）。
- **自己学習フィルタ ON でも top-level document 非遮断**（ページが開ける・kureho 目視）。
- **強力ポップアップ対策 有効時も、表示・操作・広告抑止とも良好**（kureho 目視。意図しない広告遷移・表示崩れを目視で確認せず）。
- 実機 E2E ゲートは **kureho が PASS 判断**。
- ⚠️ 実機確認は **kureho による目視**であり、headless ハーネスの自動計測値（`verification.md` の popup 22→0 等）とは別物。
- ⚠️ **iOS 17 実機での `world:MAIN` 実動作は未確認**（KPhone は iOS 26 系。iOS 17 端末が別途必要）= 残存リスク。

詳細は `tasks/streamtape-hardening/device-verification.md`。

---

## テスト結果（fresh 実行・HEAD 7912257）

| 層 | 結果 | 実行元 |
|---|---|---|
| Swift `AdblockKeshiTests` | **135 pass / 1 skip / 0 fail** | ローカル + CI macos-xcode |
| WebKit Content Rule List compile | green（`PopunderRuleCompileTests`） | CI macos-xcode |
| Release build（app + 全拡張・unsigned） | green | CI macos-xcode |
| workers（vitest） | **195 pass** | ローカル + **CI linux-checks**（workers step を追加） |
| Node（PopupShield unit・全 `*.test.js`） | **54 pass** | ローカル + CI linux-checks（core/bridge/plan/health + static） |
| Python（popunder ルール生成） | **14 pass** | ローカル + CI linux-checks |
| deterministic fixture（`run-fixture.js`・MAIN/ISOLATED 経路） | **14 checks pass** | CI linux-checks（headless chromium） |
| 生成物整合（bundle == cdn・SHA 一致） | green | CI linux-checks |
| manifest / resource / version 整合 | green | CI linux-checks |

CI run（HEAD 80ad65b・全 green）: https://github.com/kureho/AdblockKeshi/actions/runs/28013649970

---

## 制約

- main へのマージ・push なし（feature branch のみ）。
- App Store upload / TestFlight / 審査提出なし。
- 拡張本数の集約（4→3 / 4→2）は本 PR スコープ外（別 PR）。
