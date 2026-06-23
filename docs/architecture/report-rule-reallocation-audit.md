# Phase 1 監査 + 設計: 報告ルールを「報告反映」へ再配置

実施日: 2026-06-23 / 起点 origin/main `52614a7` / read-only 監査 + 実装設計。
背景: ADR（`report-driven-protection-suite.md`）の名称統一で「報告反映」(PopunderBlockerExtension) を採用したが、**ユーザー報告ルール(self/global)は PR #30 で「基本保護」(標準 ContentBlocker) の combined に在る**乖離。名称を実態と一致させるため再配置する。

## gate 判定: **安全に再配置可能（reported を popunder L1+L2 の最後尾に置く）**

### WebKit semantics（一次ソース・推測なし）
webkit.org/blog/3476:
- **「All it does is ignore every rule before the current one if the trigger is activated.」** → `ignore-previous-rules` は**"前の"ルールのみ**無効化し、**"後ろ"のルールには影響しない**。
- 「the actions are applied in order」「it is not possible to ignore the rules of an other extension」。

### 共存設計（順序）
報告反映 Content Blocker の最終リスト順序を **[L1 → L2-block → L2-ipr → reported]** とする:
- reported は全 ipr の**後ろ**なので、L2 の ipr に無効化されず**常に適用**される。
- reported は `block`（ipr 無し・third-party 限定・document 除外）なので、L2 の block/allow を**解除できない**（ipr を持たない）。L2 のサイト保護を壊さない。
- 検証必須項目の結論:
  - reported を L2 **より前**: L2 ipr が同一 resource の reported を無効化し得る → 不採用。
  - reported を L2 **より後**: ipr の影響外 → **採用**。
  - 対象サイト上で reported が無効化されるか: 後ろ配置なら無効化されない。
  - reported が L2 解除範囲を意図せず上書きするか: reported に ipr が無いので L2 の ipr 解除を覆せない。唯一、reported が L2 許可ドメイン（gstatic/google/googleapis/googletagmanager/fluidplayer/tokyo-motion）を block すると、その2サイト上で再 block され得る（reported は ipr の後ろ）。
  - first/third-party・document 除外・popup resource-type: reported は PR #29 の安全形状（third-party 限定・document 除外）を維持 → top-level 非遮断。
  - 複数 ipr 間順序: site ごとの block→ipr 群を維持し、reported は全 site 群の後ろ。
  - WebKit compile: 既存 `PopunderRuleCompileTests` を L1+L2+reported の最小再現に拡張して検証（実装で追加）。

### エッジの安全弁（**必須**・advisor 指摘で格上げ）
reported が L2 許可ドメイン（gstatic/google/googleapis/googletagmanager/fluidplayer/tokyo-motion）を block すると、reported は ipr の後ろなので**その2サイトで再 block され、L2 が温存したプレーヤー(script)を壊す**（third-party かつ script・document 除外では救えない＝本スイートが防ぐべき破壊そのもの）。よって **報告反映リスト生成時に「いずれかの L2 ipr が allow するドメインに一致する reported rule を除外」を必須フィルタとして実装し、テストで固定する**（「L2 許可ドメイン向け reported は combined-popunder に出ない」）。任意の将来課題ではない。

→ **gate PASS。名称のために抑止性能・サイト非破壊を犠牲にしない条件を満たす。** 代替案（「報告反映」→「追加対策」改名 / 別リスト同一 target / 別責務配置）は不要（採用しない）。

## 現状監査（14項目・read-only）
1. **self report 保存**: `ReportFormViewModel`→`SelfReportApplier.apply`→`SelfReportedRulesStore.appendSelfRule`(`rules-self.json`)→`rebuildMerged`(`rules-reported.json`)→`CombinedRuleListCoordinator.scheduleRegenerate`。
2. **global report 保存**: `ReportedGlobalSync.sync`→`FilterDownloader`(`rules-global.json`)→`rebuildMerged`→`scheduleRegenerate`。
3. **combined 生成**: `CombinedRuleListBuilder.rebuildIfNeeded`→`combined-<state>.json`(App Group)。標準 variant + reported safe を budget マージ。
4. **基本保護(ContentBlockerExtension)が読む**: `BlockerListResolver.resolve(for:state)` → App Group `combined-<variant>` 優先 → bundle variant。**＝現状 reported を含む。**
5. **報告反映(PopunderBlockerExtension)が読む**: `PopunderRulesResolver.make()`→`popunder-rules.json`(App Group→bundle)。**静的 L1+L2 のみ・reported 無し。**
6. **App Group 構造**: `state.json` / `{merged,ad,security,empty}-rules.json` + `combined-*` + `combined-*.meta` / `rules-self.json` `rules-global.json` `rules-reported.json` / `popunder-rules.json`。
7. **reload 先**: 基本保護=`CombinedRuleListCoordinator`→`.blocker`。報告系も coordinator 経由で `.blocker`。popunder=`PopunderGlobalSync`→`.popunderblocker`。
8. **BackgroundTask**: 標準 download→`.blocker` reload→`ReportedGlobalSync.sync`(coordinator)→`PopunderGlobalSync.sync`。
9. **起動 migration**: `migrateReportedRulesIfNeeded`(sanitize purge + `scheduleRegenerate`)。
10. **last-known-good**: `CombinedRuleListBuilder`（compile-verify→atomic→失敗時旧維持）。
11. **compile verification**: `CombinedRuleListCoordinator.compileVerify`（WKContentRuleListStore・off-main・semaphore+timeout・検証後 remove）。
12. **rollback**: combined last-known-good + resolver の bundle fail-safe + atomic write。
13. **rule budget**: `ReportedRuleBudget`（totalCap 149,000 / reportedReserve 2,000 / standardFloor 147,000）。
14. **ignore-previous-rules**: 現状は popunder リスト内のみ（L2）。reported は別(combined)なので現状 ipr は reported に届かない。**再配置後は同一リストになるため上記順序設計が必須。**

## 実装設計（Phase 2-4・別 PR で実装）
- **新 `PopunderCombinedBuilder`（または既存 builder の再利用）**: bundle `popunder-rules.json`(L1+L2) + reported safe(self∪global) を **[popunder..., reported...]** 順でマージ → App Group `combined-popunder.json`。byte-splice（reported を popunder バイト列末尾へ）で大 decode 回避。compile-verify→atomic→last-known-good。
- **`PopunderRulesResolver`/handler**: App Group `combined-popunder.json` 優先 → bundle `popunder-rules.json` fail-safe。
- **基本保護は bundle へフォールバック（標準のみ combined を作らない）**: advisor 指摘で確定。標準のみ combined を書くと 19.5MB 複製が再発するため、coordinator は basic builder に **`reportedSafe=[]`** を渡し、既存の empty-skip ロジックで `combined-<state>` を**削除**→resolver が bundle variant へ自動フォールバック。基本保護は標準フル（147k floor truncation 不要）に戻る。basic 側に新規コードを足さず既存テスト済み経路を再利用。
- **behavior change（明記・ADR/PR 記載）**: 再配置後、ユーザー自身の self-report は「**報告反映 ON 時のみ**」効く（PR #30 では basic ON で効いた）。名称整合の本質であり「3つすべて ON 推奨」に整合するが、basic のみ ON のユーザーは自分の報告効果を失う（自己学習→basic 統合の鏡像）。意識的決定として記録。
- **byte-splice**: popunder は ~40件/8KB なので decode コストは無視可。ただし `CombinedRuleListBuilder` を `variantFilename="popunder-rules.json"` で**再利用**すれば splice 経路が無料で付くので、新規コードを足さず再利用する（mayTruncate=false）。
- **報告 reload 先**: self/global report → **`.popunderblocker`** を reload（`.blocker` は報告のたびに reload しない）。サーバ送信は従来維持。
- **rule budget（報告反映側）**: L1(31)+L2(9)+reported。popunder は元々小さい（40件）ので 150,000 上限に対し余裕大。reportedReserve 2,000 は据置で十分（実測: popunder 40 + reported 数十〜数百 ≪ 150,000）。基本保護側は reported 枠が消え標準を truncate 不要に→ただし ad-only 150,000 ちょうどは安全余白を再評価（149,000 等へ寄せるか検討）。
- **migration 順序（防御消失を防ぐ）**: ①self/global 読込 ②safety filter ③報告反映リスト生成 ④compile ⑤atomic install ⑥`.popunderblocker` reload 成功 ⑦基本保護 標準のみリスト生成・compile ⑧`.blocker` reload 成功 ⑨旧 combined cleanup。idempotent・途中失敗で旧構成維持。
- **テスト**: 上記順序・共存・ipr 後方配置・compile 拡張・budget・migration・report→`.popunderblocker` reload・基本保護に reported が入らない、を TDD。

## 制約
拡張数・Bundle ID・L2・ipr・PopupShield 介入・version 不変。名称変更(PR #31)とは別 PR。App Store 操作なし。
