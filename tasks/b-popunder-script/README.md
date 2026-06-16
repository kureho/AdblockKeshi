# B: 黒画面の「飛ばさせない化」（popunder/タップ乗っ取り対策）— 2026-06-16

> kureho 指示「A→B」: A=合成テストで(a)/(b)判別＋機構確認 → B=既知popunder網の script-block 実装。
> 提出済み v3.2.0 とは別の**将来版(v3.3.0想定)**の機能。v3.2.0 はブロックしない（既に審査中）。

## 結論（research-rigor 2026-06-16 + ローカル変換器実測）
「飛ばさせない化（黒画面も出さない）」は手口で割れる:
- **(a) 分離可能な第三者広告スクリプト** → ✓ 宣言型 `resource-type:["script"]` で読込阻止＝ハンドラ付かず遷移せず黒画面も消える
- **(b) インライン `window.open`** → ✗ 原理的に不可（JS実行に介入できない）
- **(c) ドメインローテーション**（ExoClick等3日毎新ドメインAPI）→ ✗ 追従不能
- 海賊/アダルト動画サイトの主因は (b)(c) 寄り。host-block（黒画面）が宣言型の現実的上限。

## A: 機構確認（完了）
- `$script` 修飾子 → Safari `resource-type:["script"]` block に正変換（`ConverterTool` で実測）。
- キュレーションリスト `popunder-script-networks.txt`（既知29網）→ **29ルール全て resource-type:[script]**（検証済み）。

### A の合成テスト手順（実機/シミュレータで (a)/(b) を体感判別）
`test-harness/` を任意のローカルサーバで配信して Safari で開く:
```
cd tasks/b-popunder-script/test-harness && python3 -m http.server 8000
# Safari で http://localhost:8000/external-hijack.html と inline-hijack.html を開く
```
1. **ブロックOFF**で両ページのサムネをタップ → どちらも `dest.html` に飛ぶ（乗っ取り発火）。
2. `test-block-rule.json`（`hijack.js` を resource-type:script でブロック）を Safari Content Blocker として有効化。
3. **再度タップ**:
   - `external-hijack.html`（(a)型）→ **飛ばない**（hijack.js がブロックされ addEventListener が実行されない）= 飛ばさせない化 成功
   - `inline-hijack.html`（(b)型）→ **やはり飛ぶ**（インライン JS は止められない）= (b)型は宣言型で不可の実証
- ※「対象の実サイトが (a)型か (b)(c)型か」は実機ネットワークログ採取が要る（kureho判断で後回し中）。本ハーネスは機構と限界の体感用。

## B: 実装（v3.3.0 想定・次の焦点作業）
`popunder-script-networks.txt`（=既知popunder網の `$script` ルール）を **新しい Content Blocker 拡張**に同梱する。

### なぜ新extensionか
標準フィルタは 149,997/150,000 で満杯。報告拡張は自己/グローバル学習用。**popunder-script は第3の拡張**に分ける（Safari は複数拡張を同時有効化可。AdGuard for Safari も分割方式）。

### v3.3.0 配線TODO（未着手・次セッションの焦点）
1. `project.yml` に新ターゲット `PopunderBlockerExtension`（app-extension・App Group `group.com.kureho.adblockkeshi.shared`・bundle id `com.kureho.adblockkeshi.popunderblocker`）
2. `convert.sh` 等で `popunder-script-networks.txt` → `popunder-rules.json` を生成し bundle 同梱（feedback_content_blocker_must_bundle_full_ruleset 遵守）
3. RequestHandler（標準側 `BlockerListResolver` 同型・App Group→bundle fallback）
4. アプリ設定でON/OFFトグル + Safari設定での有効化導線
5. （任意）公開リスト `uAssets badware.txt` の `$popup`/`$all` 抽出を標準側に追加で黒画面カバレッジ拡張
6. TDD + シミュレータで上記Aハーネス再現 → v3.3.0 として提出

### やらないと決めたこと
- **ReportedRuleBuilder の script-block 拡張は見送り**: iOS は devtools 無し＝ユーザーが横取り .js ドメインを観測できず、報告フローに材料が無い（律速）。
- **Web Extension化(v4)**: (b)を狙える唯一の道だが iOS で racy・全サイト権限・¥500買い切りと不整合。(a)-script-block の実機効果を測ってからの判断。

## 出典
research-rigor 調査（2026-06-16）+ WebKit content-blockers docs + AdGuard SafariConverterLib README + ExoClick 公式（ドメインローテAPI/inline推奨）+ EasyList adult popup 実測。
