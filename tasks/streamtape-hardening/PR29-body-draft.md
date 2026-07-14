# fix: 報告した訪問中サイトが Safari で開けなくなる誤ブロックを修正（多層防御 + 既存端末治癒）

## 症状
ユーザーが streamtape.com など「いま見ているページの URL」を報告フォームで報告すると、
そのページ自体が Safari で開けなくなる。一度起きると端末に永続し、解除手段が無い。

## 根本原因（確定・実コード）
誤ブロックの主因は**クライアント自己報告ファストレーン**。
`Shared/ReportedRuleBuilder.swift` の `blockRule(forURL:)` が、報告 URL の host を
**resource-type / load-type 無制限の `block`** ルールにしていた。
→ top-level document（訪問中ページ自体）ごと遮断し、端末 `rules-self.json` に永続（除去経路なし）。

### サーバ・CDN・bundle は無実（実証）
- ライブ CDN（`rules-reported.json`）= `[]` 空・bundle / local CDN も空 → 静的ソースは誤ブロックを生まない。
- サーバ昇格経路（`workers/src/lib/l6-decision.ts`）は `css-display-none`（cosmetic）のみ出力。
  `'block'` を出す経路はゼロ。L4 で広い/null セレクタは reject。→ document を壊せない。

## 修正（多層防御）
1. **生成ルールの安全化**（主因の根治）: `load-type:["third-party"]` ＋ `resource-type`（`document` を除外した
   image/style-sheet/script/font/raw/svg-document/media/popup の8種）を付与。
   → 訪問中サイトは first-party なので**絶対に遮断されない**。その host が他サイトで
   third-party 広告として現れる時だけブロックする。
2. **起動時 migration（既存端末治癒）**: `App/AdblockKeshiApp.swift migrateReportedRulesIfNeeded()`。
   旧版で生成された危険な self-rule を起動時に purge。ネットワーク非依存・idempotent。
   self の除去 **または** merged 内容の変化があった時だけ Content Blocker を reload して即反映。
   → 被害端末はアップデートして起動するだけで治る。
3. **merged 生成時 strip**: `Shared/SelfReportedRulesStore.swift rebuildMerged()` が経路を問わず
   document ブロックを merged から除外（global/CDN 経由の混入も無効化）。dedup は url-filter ではなく
   ルール内容で行い、cosmetic（url-filter `.*` 共有）の取りこぼしも解消。
4. **判定述語**: `Shared/ReportedRuleSafety.swift isDocumentBlockingRisk(_:)`。`block` かつ
   「document 除外 ＋ third-party 限定」でないものを risk と判定。生成側・merged 側・migration の3点で適用。
5. **サーバ不変条件をテストでロック**: `workers/tests/lib/l6-decision.test.ts` に
   「decideL6 は `'block'` を絶対に出さない（cosmetic のみ）」を追加。将来の退行を検知。

## テスト
TDD（RED→GREEN を各サイクルで目視）。
- Swift: `AdblockKeshiTests` 135 tests / 1 skipped / 0 failures
- workers (vitest): 195 tests pass（l6-decision に不変条件 +4）
- Node (`PopupShieldExtension`): 54 pass
- Python (`build_popunder_rules`): 14 pass

## コードレビュー
`superpowers:code-reviewer` ＋ Codex の2系統。両者とも WebKit 一次資料でセマンティクスを裏取りし、
**critical/high なし・SHIP WITH NOTES**。指摘 LOW（観測性・将来堅牢性）のうち、両者が独立に挙げた
「migration reload gate を merged 変化まで広げる」は本 PR で実装済み（#5 の reload gate 拡張）。

## 残（マージ前）
- 実機 E2E（KPhone）: 4拡張 ON で streamtape を cold load し、ページ/プレーヤー/メディアが開けること・
  popunder/リダイレクト0 を目視。Safari でのトグル有効化と目視は手動。
- マージ可否はこの実機結果を確認してから判断。

## 制約遵守
本ブランチのみ。main への push・マージ・App Store 提出は行っていない。
