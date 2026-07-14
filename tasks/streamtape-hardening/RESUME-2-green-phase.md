# 再開プロンプト2 — Streamtape 誤ブロック修正 GREEN フェーズから（PR #29）

旧 RESUME（`RESUME-reported-filter-bug.md`）の**主仮説は実証で否定済み**。本ファイルが最新の正。
Phase 1 証拠は `tasks/streamtape-hardening/PHASE1-root-cause-evidence.md`。

## 状況（最重要・制約）
- repo `/Users/oharakureho/claude/AdblockKeshi` / PR **#29** / branch `fix/streamtape-adblock-hardening`
- 編集前 HEAD `f23c59d` / origin/main `65063b0`。**私の編集はまだ uncommitted**。
- **禁止: マージ / App Store 提出 / main へ push。** D1 監査/rollback は今サイクル**見送り**（kureho 承認済）。
- 使うスキル: `superpowers:test-driven-development`（RED→GREEN 継続中）→ 完了前 `superpowers:verification-before-completion` + `superpowers:code-reviewer` + Codex（skill `codex-default-review`）。日本語優先。
- ⚠️ 今セッションで tool-call が literal text 化する不具合多発（memory `feedback_no_literal_tool_call_text`）。必ず実 tool-call で。

## 根本原因（確定・実コード）
実機を壊す主因は**クライアント自己報告ファストレーン**。`Shared/ReportedRuleBuilder.swift` の
`blockRule(forURL:)` が報告URLの host を **resource-type/load-type 無制限の `block`** にする →
top-level document ごと遮断 → 端末 `rules-self.json` に**永続**（除去経路なし）。
ユーザーは Safari に見えるページURLを報告しがちなので streamtape 上で報告すると streamtape.com 自体が落ちる。
- bundle / local CDN / **ライブ CDN（`kureho.github.io/.../rules-reported.json`）= 全て `[]` 空** → 静的ソース無実。
- サーバ昇格は `css-display-none`（cosmetic）のみ・`'block'` 出力経路ゼロ・L4 で広い/null セレクタ reject → document を壊せない → 無実。

## kureho が確定した修正方針（実装中）
1. 生成ルールに `load-type:["third-party"]` ＋ `resource-type`(=document 除外の8種) を付与（訪問中サイトは first-party で絶対に遮断されない／その host が他サイトで third-party 広告として出る時のみブロック）。
2. アプリ起動時の **migration**（ネットワーク非依存）で旧 self-rule を purge＝既存被害端末を治癒。
3. 防御多層: merged 生成時に document-block を strip（CDN/global 経由の混入も無効化）。
4. サーバ側不変条件をテストでロック（`'block'` を絶対に出さない）。

## 現在のコード状態（uncommitted・RED 用スタブ入り）
**変更済みファイル**:
- `Shared/ReportedRuleBuilder.swift` — `ContentBlockerRule` モデル拡張済（Trigger に `ifDomain/unlessDomain/resourceType/loadType` optional＋explicit init＋CodingKeys `if-domain/unless-domain/resource-type/load-type`、Action に `selector` optional＋init、両方 Codable+Equatable+**Hashable**）。**`blockRule` 本体は未変更（=RED）**。
- `Shared/ReportedRuleSafety.swift` — **新規作成**（既存 xcodeproj が期待してたパス）。`enum ReportedRuleSafety.isDocumentBlockingRisk(_:)` が **STUB（return false）=RED**。
- `Shared/SelfReportedRulesStore.swift` — `sanitizeStoredSelfRules()` **STUB**（rebuildMerged 呼ぶだけ・return false）追加。`rebuildMerged` は**未変更**（url-filter dedup・safety フィルタ無し=RED）。
- `Tests/ReportedRuleBuilderTests.swift` — RED テスト7本追記済。
- `Tests/SelfReportedRulesStoreTests.swift` — RED テスト5本追記済。
- `tasks/streamtape-hardening/PHASE1-root-cause-evidence.md`、本ファイル — 新規。

## ★最初にやること: xcodeproj 再生成（必須）
既存 `.xcodeproj`（git-ignore・生成物）が**過去セッションの幽霊ファイル参照**を持っていてビルド不能:
`Shared/ReportedRuleSafety.swift`（→今回実在させた）と `Tests/ReportedRuleSafetyTests.swift`（不要・作らない）。
project.yml は pure glob。**`cd /Users/oharakureho/claude/AdblockKeshi && xcodegen generate`** で現ディスク状態に合わせる（xcodegen 2.45.3 in /opt/homebrew/bin）。
→ その後スコープ RED 確認:
```
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AdblockKeshiTests/ReportedRuleBuilderTests \
  -only-testing:AdblockKeshiTests/SelfReportedRulesStoreTests CODE_SIGNING_ALLOWED=NO
```
RED 期待: third_party_only / excludes_document / encodes_load_type / safety_flags_legacy / sanitize_purges / rebuild_strips_global / rebuild_keeps_distinct が fail。

## GREEN 実装（RED 確認後）
**`Shared/ReportedRuleSafety.swift`**:
```swift
static func isDocumentBlockingRisk(_ rule: ContentBlockerRule) -> Bool {
    guard rule.action.type == "block" else { return false }
    let excludesDocument = rule.trigger.resourceType.map { !$0.contains("document") } ?? false
    let thirdPartyOnly = rule.trigger.loadType == ["third-party"]
    return !(excludesDocument && thirdPartyOnly)
}
```
**`Shared/ReportedRuleBuilder.swift` の blockRule**（host 抽出〜escaped は維持）:
```swift
private static let blockableResourceTypes =
    ["image","style-sheet","script","font","raw","svg-document","media","popup"] // "document" 除外
// return:
ContentBlockerRule(
    trigger: .init(urlFilter: filter, resourceType: blockableResourceTypes, loadType: ["third-party"]),
    action: .init(type: "block"))
```
**`Shared/SelfReportedRulesStore.swift`**:
```swift
func rebuildMerged() throws {
    var seen = Set<ContentBlockerRule>()
    var union: [ContentBlockerRule] = []
    for rule in loadSelfRules() + loadGlobalRules() {
        guard !ReportedRuleSafety.isDocumentBlockingRisk(rule) else { continue }
        if seen.insert(rule).inserted { union.append(rule) }
    }
    try write(union, to: Self.mergedFilename)
}
@discardableResult
func sanitizeStoredSelfRules() throws -> Bool {
    let current = loadSelfRules()
    let safe = current.filter { !ReportedRuleSafety.isDocumentBlockingRisk($0) }
    let changed = safe.count != current.count
    if changed { try write(safe, to: Self.selfFilename) }
    try rebuildMerged()
    return changed
}
```
**`App/AdblockKeshiApp.swift`**（`import SafariServices` 追加・`.task{}` 内で呼ぶ・ネットワーク非依存）:
```swift
private func migrateReportedRulesIfNeeded() {
    guard let store = SelfReportedRulesStore() else { return }
    if (try? store.sanitizeStoredSelfRules()) == true {
        SFContentBlockerManager.reloadContentBlocker(
            withIdentifier: SFContentBlockerStateChecker.reportedID) { _ in }
    }
}
```
（`SFContentBlockerStateChecker.reportedID` は SelfReportApplier.swift で使用済＝実在）

**サーバ不変条件** `workers/tests/lib/l6-decision.test.ts` に追記: decideL6 の pass ケースが
`css-display-none` のみで `'block'` を絶対含まないこと。実行 `cd workers && npm test`。

## GREEN 後の検証（verification-before-completion）
- 全 Swift: `xcodebuild test ... -only-testing:AdblockKeshiTests CODE_SIGNING_ALLOWED=NO`（既存122＋新規・1既存skip）
- workers: `cd workers && npm test` / Node: `node --test PopupShieldExtension/Tests/*.test.js`（54）/ Py: `python3 -m pytest scripts/tests/test_build_popunder_rules.py -q`（14）
- `superpowers:code-reviewer` ＋ Codex（codex-default-review）
- **実機**（KPhone=iPhone 17 Pro 接続中・build/install/launch 自走可・Safari 有効化と目視は kureho）:
  ① 修正前に「自己学習 ON で streamtape 不能」を再現確認（端末 rules-self.json に streamtape ルールがある前提。無ければ報告フォームから streamtape URL を1回報告して再現を作る）
  ② 修正 build install → 起動（migration 発火）→ 4拡張全 ON で streamtape 3 cold load → ページ3/3・player3/3・media3/3・popup0・redirect0
- **PR #29 本文に追記**: 実根本原因（クライアント fast-lane・静的ソース空の実証）/ load-type third-party + document除外 / 起動時 migration / merged strip 防御多層 / サーバ不変条件 / 既存端末治癒方法 / 実機結果 / マージ可否。

## 検証 URL（規約: パス/ファイル名は成果物に書かない・`streamtape.com` のみ記録）
ハーネス `tasks/streamtape-hardening/harness/measure.js`（`TARGET_URL` env 渡し・ファイルに残さない）。

## 関連 memory
project_adblockkeshi / feedback_no_literal_tool_call_text / heavy-process-safety / feedback_simulator_first_verification / feedback_apple_submission_state_audit。
