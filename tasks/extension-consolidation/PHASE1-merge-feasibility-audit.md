# Phase 1: Safari 拡張 4→2 統合可能性 監査（読み取り専用・実測）

実施日: 2026-06-23 / 対象 repo: AdblockKeshi / 状態: **PR #29 未完了のため実装は未着手**（本書は読み取り専用調査）
方式: research-rigor 7ステップ。load-bearing な数値は一次ソース（実 JSON・生成スクリプト・WebKit 公式）で実測。

## PICO / 決定
- **P**: AdblockKeshi は Safari に拡張4本（Content Blocker 3 + Web Extension 1）を表示。kureho は2本へ集約したい。
- **I**: Content Blocker 3本（標準/自己学習/popunder）を `ContentBlockerExtension` の最終 JSON に source-aware merge し、`PopupShieldExtension`（Web Extension）は残す。
- **C**: 4→2（全統合） vs 4→3（自己学習のみ統合・popunder 別） vs 4→4（現状）。
- **O**: 表示2本・サイト無破壊（特に Streamtape）・WebKit rule budget 内・決定論的で安全なマージ。
- **この調査が可能にする決定**: 安全に 4→2 できるか／3 で止めるべきか、と merge アーキテクチャ。

## 競合仮説（ACH・探索前に提示）
- **H1**: 全部を単一リストに単純連結すれば 4→2 は安全。
- **H2**: 4→3（自己学習統合）は安全。popunder（特に L2）は 4→2 で要注意。
- **H3**: 4→2 は rule budget（ad-only が上限ちょうど）と L2 の ipr 汚染で不可能 → 3 で止める（option C）。
- **H4**: 4→2 は「ad cap を下げて budget 確保」かつ「L2 を option A(廃止しPopupShieldで代替) or B(安全再設計)」できれば可能。実機検証が条件。

---

## 実測結果（kureho 指定11項目）

### 1. 標準ルール数（トグル別アクティブリスト）
`BlockerListResolver.filename(for:)` が2トグルで4 JSON を切替（App Group 優先 → bundle → empty fallback）:
| モード (ad, security) | ファイル | ルール数 | サイズ |
|---|---|---|---|
| (ON, ON) | merged-rules.json | **130,000** | 19.5MB |
| (ON, OFF) | ad-rules.json | **150,000** | 21.3MB |
| (OFF, ON) | security-rules.json | 30,000 | 3.5MB |
| (OFF, OFF) | empty-rules.json | 0 | 2B |

`build_merged_rules.py`: ad(150k)+security(30k) を JSON 完全一致 dedup → **limit=130000 で打切り**（意図的に上限下へ余裕）。

### 2. 自己学習ルール数
- bundle baseline (`rules-reported.json`) = **0**。runtime に App Group で成長（`rules-self.json` ∪ `rules-global.json` → `rules-reported.json`）。
- 端末ごとに可変・現状の実数は端末依存（未確認）。**budget 上限設計が必要**。
- PR #29 で安全形状を確立: 純粋 block・`load-type:["third-party"]`・document 除外・`ignore-previous-rules` 無し。

### 3. popunder L1 ルール数 = **31**
既知広告ネットワークの host 別 `script` block（popads/popcash/exoclick/propellerads/adsterratech…）。`if-domain` 無し・`ignore-previous-rules` 無し・狭い。→ **標準への統合は安全**。

### 4. popunder L2 ルール数 = **9**（2サイトに `if-domain` 限定）
- tokyomotion.net: 「全 third-party script を block」+ fluidplayer/googleapis/googletagmanager/gstatic/tokyo-motion を `ignore-previous-rules` 再許可（block 1 + ipr 4）
- streamtape.com: 「全 third-party script を block」+ gstatic/google を `ignore-previous-rules`（block 1 + ipr 2）
- 構造 = 「広く block → 必要 script を後続 ipr で許可」。**単純連結禁止の対象**。

### 5. 統合後の総ルール数（worst case）
- (ON,OFF) ad-only: 150,000 + L1(31) + reported(N) + L2(9) → **150,000 超過**（ad cap 不変なら必ず破綻）。
- (ON,ON) merged: 130,000 + 31 + N + 9 ≈ 130k+α → 上限内（~20,000 余白）。
- → **律速は ad-only モード**。ad-rules の build cap を下げて予約枠を作らないと、4→3 ですら ad-only で破綻。

### 6. 重複ルール数
- L1 vs ad-rules: **byte 完全一致 0/31**（既存 dedup では消えない＝+31）／**機能的重複 9/31**（domain が ad-rules に既出。domain 単位 dedup なら最大 −9）。
- reported safe rules: host ごとに url-filter ユニーク。PR #29 の `rebuildMerged` がルール内容で structural dedup 済み。

### 7. WebKit コンパイル可否
- **一次ソース確認**: content blocker は **1拡張あたり 150,000 ルール上限**（2022 に 50,000→150,000・WebKit `maxRuleCount`・`ContentExtensionError::JSONTooManyRules`・**拡張ごと**で全体合算ではない）。
- 現行 merged(130k)/ad(150k) は本番配信中＝コンパイル実績あり。統合後も ≤150,000 に収めればコンパイル可能（原理上）。
- **統合 artifact の実コンパイルは未確認**（WKContentRuleListStore は iOS 専用・実機/シミュレータ要・Phase 3 で検証）。

### 8. コンパイル時間
- **未確認**（実測ハーネス未構築＝実装に当たるため Phase 1 では作らない）。本番 130–150k リストは実機で数秒オーダー（既知の体感値）。Phase 3 で WKContentRuleListStore 実測。

### 9. JSON サイズ
- 統合後 ≈ merged(19.5MB) + popunder(8KB) + reported(小) ≈ **~19.5MB**（現行配信サイズと同等・問題なし）。

### 10. App Group 上の生成物構成
- `state.json`（トグル状態・StateStore）
- 標準: `{merged,ad,security,empty}-rules.json`（App Group 優先・無ければ bundle）
- 自己学習: `rules-self.json` / `rules-global.json` / `rules-reported.json`
- popunder: `popunder-rules.json`（App Group/CDN 版を `PopunderGlobalSync` が更新）
- **統合後の追加要件**: `combined-<state>.json`（standard + reported safe + popunder L1 を source-aware merge）を App Group に runtime 生成し、resolver の解決先を統合先1本へ向ける。

### 11. ignore-previous-rules の影響範囲
- 7件・`if-domain` で **tokyomotion.net / streamtape.com の2サイトに限定**。
- **一次ソース確認**: 「it is not possible to ignore the rules of an other extension. Each extension is isolated.」「actions are applied in order.」
- → 今は別拡張なので popunder L2 の ipr は標準/自己学習に**届かない**。**単一リストに統合すると、その2サイト上で先行する標準/自己学習/L1 の block まで ipr が解除し得る**。順序依存。**単純 JSON 結合は禁止**（kureho 指示・一次ソースで裏付け）。

#### 11b. 汚染が実際に噛むか（実測・advisor 指摘で追加）
ipr が「再許可」する6ドメインを標準フィルタが block しているか実測（block ルール実数・url-filter のドットをエスケープして照合）:
| ipr 再許可ドメイン | ad-rules の block 数 | security |
|---|---|---|
| google.com | **34** | 0 |
| googleapis.com | **31** | 0 |
| gstatic.com | **7** | 0 |
| googletagmanager.com（GTM トラッカー） | **3** | 0 |
| fluidplayer.com | 0 | 0 |
| tokyo-motion.net | 0 | 0 |
- **結論: 重複あり（6中4ドメイン）**。よって「L2 を末尾に置けば今と挙動同等」は**否定される**。
- 統合（L2 を末尾連結）すると、tokyomotion/streamtape の2サイト上で標準が持つ GTM/Google 系 block を ipr が**解除** → これらが**ロードされるようになる**。
- 影響の性質: **サイト破壊ではない**（許可が増える方向＝ページは壊れにくい）。実害は「GTM（トラッカー）+ Google CDN がその2サイトで漏れる軽微な blocking/privacy regression」。
- → option B（L2 を安全再設計せず末尾連結）は **no-op ではない**。挙動変化を伴うため、採るなら「この regression を許容する」明示判断 or 干渉しない再設計が要る。

---

## ACH 表（最少矛盾で生存判定）
| 証拠 | H1 単純連結で4→2 | H2 4→3安全 | H3 4→2不可・3で止 | H4 4→2条件付き可 |
|---|---|---|---|---|
| WebKit 150k/拡張(E1) | 矛盾(ad-only超過) | 整合(要ad cap減) | 整合 | 整合 |
| ad-only=150k(E2) | 矛盾 | 整合(要cap減) | 整合 | 整合 |
| ipr 拡張隔離・順序依存(E3) | 矛盾(汚染) | 整合 | 整合 | 整合 |
| L2構造=広block+ipr(E4) | 矛盾 | N/A | 整合 | 整合(L2要処理) |
| reported純block・ipr無(E5) | — | 整合 | — | 整合 |
| merged130k本番compile実績(E6) | — | 整合 | — | 整合 |
| PopupShieldのL2代替力(E7) | — | — | 未測定 | **未確認(要実機)** |

- **H1 棄却**（最多矛盾: budget 超過 + ipr 汚染）。
- **H3 は過剰**（L1 は安全に統合可・budget は ad cap 減で解ける＝「不可能」は言い過ぎ。ただし L2 が安全化できなければ option C の fallback として有効）。
- **生存 = H2 + H4**: 4→3 は安全（ただし ad cap 減が前提）。4→2 は ad cap 減 + L2 を option A/B で安全化でき、実機で PopupShield が L2 を代替できると確認できた時のみ。

## Devil's Advocate（生存仮説への自己攻撃）
「4→3 は安全」を攻撃する: **4→3 ですら無料ではない**。ad-only モードは現状 150,000＝上限ちょうど。自己学習ルールはトグルに関係なく適用すべき（ユーザー自身の広告報告）なので、ad-only 時に1件でも reported を足すと上限超過でコンパイル失敗＝**広告ブロックが丸ごと無効化**する重大退行になり得る。よって 4→3 を名乗るには **ad-rules の build cap を 150,000 から少し下げ reported/popunder L1 の予約枠を作る**ことが必須前提。

ただしトレードオフは小さい（advisor 指摘で補正）: 自己学習ルールはユーザー自身の広告報告で**現実には数十〜せいぜい数百件**規模。予約枠は小さく（例 1,000〜2,000）、ad cap を 150,000→148,000〜149,000 程度に下げれば足りる。落とすのは EasyList 末尾（最低優先）の僅かなルールで、広告カバレッジ低下はごく軽微。**過大に「数千件を捨てる」わけではない**。要点は「cap 削減という設計判断が 4→3 にも必須」であって、コストの大きさではない。→ 攻撃成立だがコストは小。結論を「4→3 は安全（**ただし小幅な rule budget 予約が Phase 2 の前提条件**）」に補正。これ以上は崩せない（budget さえ確保すれば reported は純 block・ipr 無で順序非依存・E5/E3 で安全）。

---

## 採用 / 除外
- 採用: 生存仮説 **H2（4→3 は安全・要 budget 再設計）+ H4（4→2 は条件付き可・実機ゲート）**。
- 除外: H1（単純連結／budget 超過 + ipr 汚染で最多矛盾）。H3 の「4→2 不可能」断定（L1 統合可・budget 可解のため過剰。ただし C＝3で止める判断は L2 安全化失敗時の正当な fallback として保持）。
- 除外理由: 一次ソース（WebKit 上限・ipr 隔離）と実測（ad-only=150k・L2=広block+ipr）に最も矛盾しないのは H2+H4。

## 未確認（要 Phase 2/3・実機）
- 統合 artifact の WKContentRuleListStore 実コンパイル可否と所要時間（iOS 専用・実機要）。
- **option A と option B で実機テストが別物**（advisor 指摘）:
  - **A テスト**: 「popunder OFF + PopupShield ON」で tokyomotion/streamtape の popunder が止まるか（= L2 廃止して PopupShield で代替できるか）。
  - **B テスト**: L2 を末尾連結した**統合 artifact 自体**が compile し、2サイトで GTM/Google 漏れ regression を許容範囲で動くか（11b の挙動変化を実機で確認）。
- 端末ごとの自己学習ルール実数分布（budget 予約枠の妥当値決定に必要・実測上は数十〜数百規模の見込み）。
- ad cap を 149,000 等へ下げた時の広告カバレッジ実影響（落とす末尾ルールは僅少の見込み）。

## 次に見れば確度が上がる問い
- popunder OFF + PopupShield ON で tokyomotion/streamtape を実機テスト → L2 廃止(option A)が安全か即判明。
- 統合 JSON を WKContentRuleListStore.compileContentRuleList に通すミニ実機ハーネス → compile 可否/時間/順序依存の実証。
- 自己学習 budget の予約枠 N を、信頼度・新しさ・利用実績で選別するロジック（PR #29 の安全形状を維持）。

## 出典（取得日 2026-06-23）
- WebKit content blocker rule 上限 150,000（per-extension・maxRuleCount）: https://webkit.org/blog/3476/content-blockers-first-look/ ／ AdGuard KB（rule limit）https://adguard.com/kb/adguard-for-safari/solving-problems/rule-limit/ ／ PoomSmart/BlockEmAll README https://github.com/PoomSmart/BlockEmAll
- ignore-previous-rules は拡張ごと隔離・順序依存・resource-type/load-type/if-domain 定義: https://webkit.org/blog/3476/content-blockers-first-look/
- 実測一次ソース（本 repo）: `Extension/Resources/{ad,security,merged,empty}-rules.json` / `PopunderBlockerExtension/Resources/popunder-rules.json` / `ReportedRulesExtension/Resources/rules-reported.json` / `scripts/build_merged_rules.py` / `Shared/BlockerListResolver.swift` / `Extension/ContentBlockerRequestHandler.swift`

---

## Phase 2/3 への含意（実装は PR #29 完了後・別ブランチ）
1. **Phase 2（4→3）**: 自己学習を `ContentBlockerExtension` の `combined-<state>.json` に source-aware merge（順序: standard → reported safe → 将来 popunder L1）。**前提=ad cap を下げ reported 予約枠を確保**。PR #29 の安全形状（third-party/document除外/isDocumentBlockingRisk/migration/merged strip）を全維持。`ReportedRulesExtension` 削除後も App Group 経由で反映継続。→ 表示3本（広告消し/ポップアップ広告対策/強力ポップアップ対策）。
2. **Phase 3（4→2 判断）**: popunder L1(31) は標準へ統合可（狭い host block・ipr 無）。**L2(9・ipr) は単純連結禁止**。11b の実測で「L2 末尾連結 = 今と挙動同等」は否定済み（2サイトで GTM/Google 系が漏れる挙動変化あり）。よって A/B/C を実機で選択:
   - **A（推し）**: L2 廃止し PopupShield(強力ポップアップ対策) で代替。A テスト（popunder OFF + PopupShield ON で2サイト）が通れば、L2 の挙動変化問題ごと消えて最もクリーンに 4→2。
   - **B**: L2 を「他ルール非干渉」に再設計 or 末尾連結（11b の GTM/Google 漏れ regression を許容判断＋B テスト）。
   - **C**: 2つ化を諦め3本維持（2サイトの現挙動を厳密保持できる唯一の選択・fallback）。
   - **「2つにする」より「サイトを壊さない」を優先**（kureho 指示）。A が実機で通らなければ C。
