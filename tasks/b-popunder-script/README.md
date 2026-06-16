# B: 黒画面の「飛ばさせない化」（popunder/タップ乗っ取り対策）— 2026-06-16

> kureho 指示「A→B」: A=合成テストで(a)/(b)判別＋機構確認 → B=既知popunder網の script-block 実装。
>
> **⚠️ 状態更新（2026-06-17）**: 下の「B: 実装（v3.3.0 想定・次の焦点作業）」は**陳腐化記述**。
> `PopunderBlockerExtension`（既知網29ルールの $script block）は **v3.2.0 build22 で出荷済み**（承認・配信中）。
> v3.3.0 は「ゼロから作る」ではなく**強化**として実装済み（feature ブランチ `feat/v33-popunder-aggressive`）:
> ① L1 安全網拡充（`jads.co`/`glssp.net` 追加）② L2 サイト別アグレッシブ（対象サイトで third-party script
> 全 block→allowlist を ignore-previous-rules・回転ドメイン込みで popunder 消滅をプレーヤー生存のまま実現）
> ③ 専用ジェネレータ `scripts/build_popunder_rules.py`（pytest 緑）④ CDN living list 配信
> （`PopunderGlobalSync` + `FilterDownloader.syncsVersion` opt-out・WebKit コンパイル受理を runtime テスト済）
> ⑤ 解析ツール `scripts/analyze-popunder.js`。設計は `docs/superpowers/specs/2026-06-17-adblockkeshi-v33-popunder-aggressive-design.md`、
> 手順は `docs/superpowers/plans/2026-06-17-v33-popunder-aggressive.md`。
>
> **dogfooding で新サイトを追加する手順**:
> 1. `NODE_PATH=<playwright-core path> node scripts/analyze-popunder.js <url>` で allowlist 候補と popunder 網を抽出
> 2. `tasks/b-popunder-script/popunder-aggressive-sites.json` に `{domain, allow}` を追記
> 3. push すると `popunder-rules-update.yml` が bundle+CDN を再生成（審査不要で端末反映）

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

## B: 実装（~~v3.3.0 想定・次の焦点作業~~ → **下記の通り出荷/実装済み**）
`popunder-script-networks.txt`（=既知popunder網の `$script` ルール）を **新しい Content Blocker 拡張**に同梱する。

### なぜ新extensionか
標準フィルタは 149,997/150,000 で満杯。報告拡張は自己/グローバル学習用。**popunder-script は第3の拡張**に分ける（Safari は複数拡張を同時有効化可。AdGuard for Safari も分割方式）。

### v3.3.0 配線TODO → **完了状況（2026-06-17 更新）**
1. ✅ `project.yml` の `PopunderBlockerExtension`（bundle id `com.kureho.adblockkeshi.popunderblocker`）= **build22 で出荷済み**
2. ✅ `popunder-script-networks.txt` → `popunder-rules.json` 生成 = **専用ジェネレータ `scripts/build_popunder_rules.py` で実装**（`convert.sh`=SafariConverterLib とは別物・手書き決定論・pytest 緑・bundle 同梱維持）
3. ✅ RequestHandler（`PopunderRulesResolver` → `BlockerListResolver` App Group→bundle fallback）= **出荷済み**
4. ✅ ON/OFFトグル + Safari有効化導線 = **build22 出荷済み**（OnboardingView 3つ目案内）
5. （任意・未）`uAssets badware.txt` の `$popup`/`$all` 抽出 = 将来のカバレッジ拡張候補
6. ✅ TDD = ジェネレータ pytest + FilterDownloader/WebKit コンパイル受理テスト（シミュレータ）緑。**提出は kureho 判断**（feature ブランチ未マージ）
7. 🆕 **v3.3.0 強化分**: L1 ギャップ補充（jads.co/glssp.net）+ L2 サイト別アグレッシブ（tokyomotion 実証）+ CDN living list（`PopunderGlobalSync`・`popunder-rules-update.yml`）

### やらないと決めたこと
- **ReportedRuleBuilder の script-block 拡張は見送り**: iOS は devtools 無し＝ユーザーが横取り .js ドメインを観測できず、報告フローに材料が無い（律速）。
- **Web Extension化(v4)**: (b)を狙える唯一の道だが iOS で racy・全サイト権限・¥500買い切りと不整合。(a)-script-block の実機効果を測ってからの判断。

## 実機相当 desktop 実測（2026-06-17・headless Chrome + iPhone Safari UA）

kureho が報告した **tokyomotion.net** を headless Chrome（iPhone UA）で読み込み、`window.open` 計装＋gesture event リスナー登録元の origin 解析＋「既知網 script 遮断」比較実験を実施（スクリプトは使い捨て・実行後削除）。

**結果（baseline vs 既知網遮断）**:
- `matchedPopunderNetworks`: **realsrv.com(ExoClick)・pemsrv.com(Adsterra)** を script として読込（=リスト収録の安定網は実在）。
- gesture listener 登録元: **firstPartyOrInline = 0**（インライン (b) ではない）。登録は全て第三者 script: `reservedghettocrimpycrimpy.com`(5)・`chaseherbalpasty.com`(1)・`poweredby.jads.co`(JuicyAds)・`glssp.net` 等。
- **決定実験**: `a.realsrv.com`（ExoClick 安定網・我々の $script リスト収録）を遮断しても、`reservedghettocrimpycrimpy.com` 等の**ランダム生成ドメインの gesture listener は消えず残存**＝ローテーション系は安定網と独立にロードされる。

**結論**: tokyomotion は「第三者 script 由来だが、毎回変わる gibberish ドメインで配信される＝実質 **(c) ドメインローテーション**」。静的 $script リストは安定網（realsrv/ExoClick・pemsrv/Adsterra・jads/JuicyAds）は捕捉できるが、回転ドメインは原理的に追えず、かつ安定網を止めても回避ドメインが独立稼働する。→ 上記 research-rigor 結論を実データで裏付け、(b) ではなく **(c)** と精密化。

**v3.3.0 への含意**: $script popunder-block 拡張は安定網には効くが、**adult/pirate 系（kureho の実報告対象）の主流である回転ドメイン popunder は止めきれない**。実効的な上限は依然 **host-block（黒画面）** か、回転ドメインを追う動的フィード（重い運用）か、Web Extension(v4・racy)。**買い切り¥500 の費用対効果としては v3.3.0 の $script 拡張は「部分的にしか効かない」と理解した上で着手判断すべき**。

**測定上の留保**: headless 検知で `window.open` 実発火は 0（gesture listener 登録から推定・下振れ方向の誤差）。単一サイト（tokyomotion）の結果。厳密確定には実機ネットワークログ（README 上部の Option 3）が必要だが、本実測で v3.3.0 の費用対効果判断には十分な解像度が得られた。

## 出典
research-rigor 調査（2026-06-16）+ WebKit content-blockers docs + AdGuard SafariConverterLib README + ExoClick 公式（ドメインローテAPI/inline推奨）+ EasyList adult popup 実測 + **desktop 実測（2026-06-17・本ファイル上記セクション）**。
