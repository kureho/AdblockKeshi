# Phase 1 監査 + 設計: 報告ルールを「報告反映」へ再配置

実施日: 2026-06-23 / 起点 origin/main `52614a7` / read-only 監査 + 実装設計。
背景: ADR（`report-driven-protection-suite.md`）の名称統一で「報告反映」(PopunderBlockerExtension) を採用したが、**ユーザー報告ルール(self/global)は PR #30 で「基本保護」(標準 ContentBlocker) の combined に在る**乖離。名称を実態と一致させるため再配置する。

## 🚨 監査中の重大発見: PR #30 は reported 配信を regression させていた（empirical 確定）

App テストホスト（`.main`=app バンドル）で実測:
- `BlockerListResolver().standardRulesURL(for: merged/ad)` = **nil**
- `BlockerListResolver(filterFilename:"popunder-rules.json").resolve()` = **nil**
- `.main` に `merged-rules.json` / `popunder-rules.json` **無し**（rule JSON は各 appex バンドルのみ・App 本体バンドルには version.json だけ）

→ App で動く `CombinedRuleListCoordinator` は標準 variant を取得できず（App Group にも標準 variant を書く経路なし）、**`combined-<state>` を生成できない**。結果、標準 ContentBlocker 拡張は**自前バンドルの variant(130k)を読み**、**self/global reported は標準拡張に届かない**。一般広告ブロックは bundle variant fallback で生きているため device 上は正常に見えた（kureho の「combined へ反映」確認はこの理由で誤認・Settings UI から観測不能）。

- **PR #30 が導入した regression**（既存ではない）。PR #30 前は `ReportedRulesExtension` が App Group `rules-reported.json`（app が書く小ファイル）を直読みして機能していた。PR #30 が同拡張を削除し 22MB variant を要する標準 combined へ畳もうとして破綻。
- **CI が green だった理由（テストギャップ）**: `CombinedRuleListBuilder` テストは temp-dir URL を注入。coordinator が**実 app バンドルから rule source URL を取得できるか**は未テスト。修正には「app が `.main` から rule source を解決できる」regression テストを必須とする。
- **blast radius**: main のみ・**未提出**（live App Store は旧4拡張 v3.2.0 build22 / v3.3.0 build23 で reported は機能）＝**production 障害なし**。ただし consolidation を提出する前に必ず修正が要る。

### 再配置はこの問題を"解消"する（"継承"ではない）
- basic は reported を持たなくなり combined を作らない → **bundle variant へ戻る（22MB を app が読む必要が消える＝壊れた経路を削除）**。
- reported は base **8KB** の `combined-popunder` へ。**`popunder-rules.json` を App ターゲットにもバンドル**すれば coordinator は `.main` から読める（App Group コピー頼みは fresh install で nil＝同じバグ再発なので不可）。
- → **本再配置 PR は PR #30 の reported regression の修正も兼ねる**（scope: 責務整合 + reported 配信修正）。

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
- **【必須】App ターゲットに `popunder-rules.json`(8KB) をバンドル**: coordinator は App で動くため、combined-popunder の base を `.main` から読めるようにする。App Group コピー（PopunderGlobalSync）だけに頼ると fresh install で nil＝PR #30 と同じバグ再発。8KB なのでバンドル複製のコストは無視可（22MB 標準 variant とは違う）。
- **【必須】regression テスト**: 「App の `.main` から combined-popunder の base（popunder-rules.json）を解決できる」ことをテストで固定（temp URL 注入でなく実 `.main` 解決。PR #30 のテストギャップを塞ぐ）。
- **基本保護の bundle 復帰の検証**: basic に reportedSafe=[] を渡し combined-<state> を削除 → 標準拡張が bundle variant を読むことを確認（標準拡張内では `.main`=拡張バンドルで variant 有り＝正常。app 側は variant を読む必要が消える）。
- **報告 reload 先**: self/global report → **`.popunderblocker`** を reload（`.blocker` は報告のたびに reload しない）。サーバ送信は従来維持。
- **rule budget（報告反映側）**: L1(31)+L2(9)+reported。popunder は元々小さい（40件）ので 150,000 上限に対し余裕大。reportedReserve 2,000 は据置で十分（実測: popunder 40 + reported 数十〜数百 ≪ 150,000）。基本保護側は reported 枠が消え標準を truncate 不要に→ただし ad-only 150,000 ちょうどは安全余白を再評価（149,000 等へ寄せるか検討）。
- **migration 順序（防御消失を防ぐ）**: ①self/global 読込 ②safety filter ③報告反映リスト生成 ④compile ⑤atomic install ⑥`.popunderblocker` reload 成功 ⑦基本保護 標準のみリスト生成・compile ⑧`.blocker` reload 成功 ⑨旧 combined cleanup。idempotent・途中失敗で旧構成維持。
- **テスト**: 上記順序・共存・ipr 後方配置・compile 拡張・budget・migration・report→`.popunderblocker` reload・基本保護に reported が入らない、を TDD。

## self-report の効き方の限界（2026-06-23 実機検証で確認・PR #32 スコープ外・別途 product 検討）
実機で「報告したページで広告がブロックされない」を確認。**PR#29 安全設計の必然でありバグではない**:
- 報告フォームは**ユーザー手入力 URL**（実態はページ URL）を取り、`ReportedRuleBuilder` が `load-type:["third-party"]`+document 除外の host-block を生成（PR#29 で streamtape 誤ブロックを防ぐため必須）。
- ページ URL のホストは**そのページ上では first-party** → third-party 限定ルールは無効 → 報告元ページの広告は（再読込しても）消えない＝「報告元ページを壊さない」の裏返し。
- ページ URL 自己報告の価値は**サーバ解析→ルール昇格の遅延・全体モデル**（completion「7〜14日」）。instant-local fast-lane が局所的に効くのは ad-network ドメイン直入力時のみ。
- 「報告した広告がその場で消える」には**広告そのものの捕捉（Safari Web拡張の要素ピッカー＋サイト限定 cosmetic）**が要る＝別途 product 判断（kureho: PR #32 を先に仕上げ・本件は別途検討）。
- **本再配置はルールの"効き方"を変えない**（置き場所を報告反映へ正すだけ）ので、この限界は PR #32 のマージ可否に**直交**。

## 実機検証結果（kureho 目視・2026-06-23 PASS）
PR #32 版を既存アプリへ上書き install（削除なし）・3拡張すべて ON で確認:
- 拡張構成: Safari 機能拡張 **3つのまま**・全 ON（旧名: 標準フィルタ/ポップアップ広告対策/強力ポップアップ対策）
- **Streamtape**: ページ表示 OK・player 生存・media 再生 OK・意図しない popup 0・current-tab redirect 0・黒画面/操作不能なし
- **TokyoMotion**: ページ表示 OK・player/主要コンテンツ生存・media 再生 OK・popup 0・redirect 0・黒画面/操作不能なし
- 一般サイト: 表示崩れなし・通常の広告ブロック従来どおり・正常リンク操作 OK
- 再起動: アプリ/Safari/iPhone いずれも維持 OK

→ **reported を報告反映(popunder)末尾に統合しても L2 サイト(プレーヤー温存)を壊さず、一般ブロックも維持**を実機確認。kureho が PR #32 を merge 基準充足と判断（「報告→その場で広告ブロック」は merge 条件外＝別途 product 検討）。

## 制約
拡張数・Bundle ID・L2・ipr・PopupShield 介入・version 不変。名称変更(PR #31)とは別 PR。App Store 操作なし。
