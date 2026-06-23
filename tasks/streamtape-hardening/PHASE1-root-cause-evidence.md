# Phase 1 根本原因 確定証拠 — 自己学習フィルタ Streamtape 誤ブロック（PR #29）

調査日: 2026-06-23 / branch `fix/streamtape-adblock-hardening` HEAD f23c59d / origin/main 65063b0
手法: superpowers:systematic-debugging（Iron Law 遵守・推測修正なし）

## 結論（1行）
**主因はクライアント側の自己報告ファストレーン `ReportedRuleBuilder.blockRule(forURL:)`。**
報告URLの host を `resource-type`/`load-type` 無制限の `block` host-block にし、top-level document を含む全リクエストを遮断する。オンデバイス `rules-self.json` に永続するため、CDN を空にしても消えない。bundle/CDN/サーバ側は全て無実。

## RESUME 主仮説の検証結果 → 否定
RESUME は「CDN/bundle の reported ルールに streamtape host-block が存在」を主仮説としたが、実データで否定:

| 検証対象 | 実測 | 判定 |
|---|---|---|
| `ReportedRulesExtension/Resources/rules-reported.json`（bundle fallback） | `[]` 2バイト・length 0 | **空＝無実** |
| `docs/cdn/rules-reported.json`（local repo） | `[]` 2バイト・length 0 | **空＝無実** |
| **ライブ CDN** `https://kureho.github.io/AdblockKeshi/cdn/rules-reported.json`（端末が実際にDLする実体） | `[]` http 200 size 2 | **空＝無実** |
| 標準 `Extension/Resources/ad-rules.json` の streamtape | 巨大な `*streamtape.com` 等ドメイン配列（if/unless-domain スコープ用） | 標準のみONで実機表示可＝無実 |
| git 履歴 | reported 系は初期コミット以降 streamtape 出現なし | — |

## 確定した破壊経路（実コード）
1. `App/ReportTab/ReportFormViewModel.swift:94,99` — ユーザーが報告フォームに入力した URL (`validatedURL`) を `selfReportApplier.apply(reportedURL: url)` に渡す。
   - ※ ユーザーは Safari アドレスバーに見える**ページURL**を貼りがち（広告URLは不可視/一時的）。＝ streamtape 上で報告すると streamtape.com 自体が報告されやすい。
2. `App/ReportTab/SelfReportApplier.swift:16` — `ReportedRuleBuilder.blockRule(forURL:)` → `SelfReportedRulesStore.appendSelfRule(rule)`。
3. `Shared/ReportedRuleBuilder.swift:23-33` — **主因コード**:
   - host 抽出 → 唯一のガードは `CriticalDomainGuard.isCritical(host)`（大手/決済/銀行の静的 allowlist のみ・streamtape 非該当）
   - 生成: `trigger.url-filter = ^[^:]+://+([^:/]+\.)?<host>[/:]` / `action.type = block`
   - **`resource-type` 無し → main_frame(document) を含む全リクエストをブロック**
   - **`load-type` 無し → first/third 区別なし＝自分が訪れているサイトも遮断**
4. `Shared/SelfReportedRulesStore.swift:37-60` — `rules-self.json` に追記 → `rules-reported.json = union(self, global)` を再構築。**self-rule を除去する経路が存在しない＝永続バグ**。
5. `ReportedRulesExtension/ReportedContentBlockerRequestHandler.swift` + `Shared/BlockerListResolver.swift:23` — App Group の `rules-reported.json` を**無加工**で Safari に渡す（compile時ガード無し）。

「自己学習 OFF → 表示可」= 報告Extension を無効化すると上記コンパイル済み block が外れるため。実機の切り分け結果と完全に整合。

## サーバ側は構造的にシロ（再発防止の前提）
- `grep` で `'block'` アクションを出すサーバ経路は**ゼロ**。
- `workers/src/lib/l6-decision.ts:47` が出すのは `css-display-none`（cosmetic・要素を隠すのみ・document をブロック不可）。しかも `score>=0.7` かつ `isAcceptableSelector` 必須。
- `workers/src/lib/selector-scope.ts` は **null セレクタ（=URL全体ブロック）と広いセレクタ（`*`/`body`/`div`/`main`/`[class*=]`/`#app`/`#root` 等）を明示 reject**。
- `scripts/sync/reported-rules-build.ts` は D1 `stable` の `rule_text`（=全て css-display-none）を flatten するだけ。
→ **サーバ昇格パイプラインは document-block を生成不可能**。streamtape 破壊の原因にはなり得ない。

## 既存端末への影響（要件④で最重要）
破壊ルールは端末 `rules-self.json` に**永続**。CDN を空にしても既存被害端末は治らない。
→ 修正には**アプリ起動時に危険な self-rule を purge する migration が必須**（単なる CDN 操作では不十分）。

## D1 / 主因の関係（要件④サーバ部分）
ライブ CDN が `[]` ＝ D1 stable から端末へ公開された reported ルールは現状ゼロ。かつサーバは cosmetic のみ。
→ 仮に D1 に streamtape 候補があっても (a) 未公開 (b) css-display-none で document を壊せない。**現在の実機破壊とは無関係**。
→ D1 mutation は「main へ push しない」制約と衝突（read-only peek workflow も main 追加が必要）。kureho 判断事項。
