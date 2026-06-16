# AdblockKeshi v3.3.0 設計: popunder ブロッカー強化（実効・CDN living list）

- 日付: 2026-06-17
- ステータス: Draft（spec レビュー前）
- 対象アプリ: 学習する広告消し（com.kureho.adblockkeshi・iOS Safari Content Blocker・買い切り ¥500）
- 関連: `tasks/b-popunder-script/README.md`（research-rigor 調査 + desktop 実測）

## 1. 背景と問題

### 1.1 現状（実コードで確認済み）
- v3.2.0 build22（**承認・配信中**）で第3の Content Blocker 拡張 **`PopunderBlockerExtension`** を出荷済み。
  - bundle id `com.kureho.adblockkeshi.popunderblocker`、App Group `group.com.kureho.adblockkeshi.shared`、表示名「ポップアップ広告対策」。
  - `PopunderBlockerExtension/Resources/popunder-rules.json` = **29 ルール**（既知 popunder 網の `resource-type:[script]` block）。
  - `Shared/PopunderRulesResolver.swift` → `BlockerListResolver(filterFilename: "popunder-rules.json")` で **App Group →（無ければ）bundle フォールバック**構造を既に持つ（コメントに「将来 CDN 更新で配信」と明記）。
- ⚠️ `tasks/b-popunder-script/README.md` の「v3.3.0 配線TODO（未着手）」は **build22 で実装済みなのに更新漏れの陳腐化記述**。本 spec 実装時に README を現状へ修正する。

### 1.2 問題（desktop 実測 2026-06-17 で確定）
kureho が実使用し報告した `tokyomotion.net` を headless Chrome（iPhone Safari UA）で解析:
- popunder のタップ用 gesture listener は **インライン由来ではない**（`firstPartyOrInline: 0`）。全て第三者スクリプトが登録。
- 登録元は **安定網**（realsrv.com=ExoClick / pemsrv.com=Adsterra / poweredby.jads.co=JuicyAds / glssp.net）＋ **回転ドメイン**（`reservedghettocrimpycrimpy.com`・`chaseherbalpasty.com` 等のランダム生成 gibberish）の混在。
- **決定実験 A**: 安定網 `a.realsrv.com`（リスト収録済み）を遮断しても、回転ドメインの gesture listener は消えず独立稼働 → 静的 $script リストは回転に追いつけない。
- **ギャップ確定**: 出荷済み 29 ルールは `realsrv/exoclick/pemsrv/popads` 等を捕捉するが、**`jads.co`（JuicyAds 実配信ドメイン・リストは `juicyads.com` 止まり）と `glssp.net` が未収録**。

→ 静的ネットワークリストだけでは「体感で popunder が減る」に届かない。回転ドメインが体感の主因。

### 1.3 突破口（desktop 実測 で実証）
**決定実験 B**: 対象サイトで「許可リスト以外の third-party script を全遮断」した場合の baseline 比較:

| | baseline | scoped-block |
|---|---|---|
| popunder gesture listener | pemsrv(4)・chaseherbalpasty(1)・jads.co(1)・reservedghettocrimpycrimpy 等 | **全消滅** |
| 残存 gesture listener | 上記＋プレーヤー | **fluidplayer(27)＋GTM(2) のみ** |
| 動画プレーヤー | 生存 | **生存（fluidPlayer global=true・video要素1）** |

**結論**: 「対象サイト限定で third-party script を許可リスト以外まとめて遮断」すれば、**静的リストで追えない回転ドメイン込みで popunder が消え、動画プレーヤーは生き残る**。これが v3.3.0 の核となる実証済み技術。
（許可リストには「インフラ(player/jquery/analytics)＋そのサイト自身の CDN」が必要。実測で `cdn.tokyo-motion.net`（サイト自身の別ドメイン CDN）も遮断対象に入ったため、allowlist 調整が運用上必須。）

## 2. ゴール / 非ゴール

### ゴール（brainstorming で kureho が選択した4判断）
1. **実効重視**: kureho が実使用するサイトで「タップしたら別タブが開く」を実際に減らす。手段は問わない。
2. **アグレッシブOK**: popunder 拡張は本体 ad-block とは別の独立トグル。多少サイトが壊れても本体は無傷（壊れたらユーザーが popunder トグルだけ OFF）。回転ドメインへのヒューリスティック遮断を許容。
3. **Approach C（ハイブリッド）**: グローバル安全網（L1）＋ サイト別アグレッシブ（L2）の二層。
4. **CDN 更新対応**: living list を App Review なしで更新できる配信に乗せる。

### 非ゴール
- 本体 ad-block（標準フィルタ）への変更。
- host-block（黒画面でサイト丸ごと潰す）— kureho が使うサイトを壊すため不採用。
- Web Extension 化（v4）— racy・全サイト権限・買い切り¥500 と不整合。今回は declarative Content Blocker の範囲に限定。
- per-site ホワイトリスト UI（既存方針「誤検知時はトグル全体 OFF」を維持）。

## 3. アーキテクチャ / コンポーネント

二層を1つの `popunder-rules.json` にコンパイルし、bundle 同梱＋CDN 配信する。

| 層 | ソース（kureho が編集） | 生成される Content Blocker ルール |
|---|---|---|
| **L1 安全網（全サイト）** | `tasks/b-popunder-script/popunder-script-networks.txt`（既存・拡充） | 各網ドメインの `block`（`resource-type:[script]`, `load-type:[third-party]`） |
| **L2 アグレッシブ（対象サイト）** | **新規** `tasks/b-popunder-script/popunder-aggressive-sites.json` = `[{ "domain": "...", "allow": ["...", ...] }]` | `if-domain` 限定で「third-party script 全 `block`」→ allowlist 各々を `ignore-previous-rules` で解除 |

### コンポーネント
- **convert（拡張）**: 既存 `scripts/convert.sh` / converter を拡張し、L1＋L2 ソースから `popunder-rules.json` を生成。生成先は (a) `PopunderBlockerExtension/Resources/popunder-rules.json`（bundle）と (b) `docs/cdn/popunder-rules.json`（CDN）の両方。
- **CDN 配信**: 本体フィルタが既に使う GitHub Pages CDN（`docs/cdn/`）に popunder-rules.json と version 情報を配置。`monthly-filter-update.yml`（または専用 dispatch workflow）で再生成・push。
- **downloader（拡張）**: `FilterDownloader` を拡張し、起動時に CDN の popunder-rules.json を App Group へ best-effort 保存（本体フィルタの DL と同型）。
- **resolver（既存・変更なし）**: `PopunderRulesResolver` → `BlockerListResolver` が App Group →（無ければ）bundle を解決。CDN 版が来ていれば優先、無ければ bundle 同梱版。

## 4. ルール生成の具体（WebKit Content Blocker JSON）

### L1（安定網・全サイト）
`||jads.co^$script` 形式のソース行 →
```json
{ "trigger": { "url-filter": "^[^:]+://+([^:/]+\\.)?jads\\.co[/:]", "resource-type": ["script"], "load-type": ["third-party"] },
  "action": { "type": "block" } }
```
実測ギャップの即補充: **`jads.co`・`glssp.net` を追加**。さらに主要 popunder 網（ExoClick/Adsterra/JuicyAds/PropellerAds/PopAds 等）の **実配信サブドメイン**を監査して補強。

### L2（アグレッシブ・対象サイト限定）
1サイトにつき以下を順序通り生成（**block の後に ignore-previous-rules**）:
```json
{ "trigger": { "url-filter": ".*", "resource-type": ["script"], "load-type": ["third-party"], "if-domain": ["*tokyomotion.net"] },
  "action": { "type": "block" } },
{ "trigger": { "url-filter": "...(fluidplayer|googleapis|tokyo-motion\\.net 等 allow)...", "if-domain": ["*tokyomotion.net"] },
  "action": { "type": "ignore-previous-rules" } }
```
- `if-domain` でサイトを限定するため、**他サイトには一切影響しない**（アグレッシブだがスコープ限定）。
- allowlist は domain 単位の url-filter で `ignore-previous-rules`。
- 初期収録は tokyomotion（実測の allow セット）。

### ルール数・順序
- L1 数百規模＋L2（約2〜6ルール×サイト数）。別拡張の上限（iOS の content blocker 上限・15万想定）に対し余裕。
- 生成時に「L1 ブロック群 → L2（各サイトの block → ignore）」の順で並べる。順序が崩れると ignore が効かないため、converter のテストで順序を固定検証する。

## 5. 配信 / 更新フロー（CDN・審査不要）

```
kureho が source 編集（networks.txt / aggressive-sites.json）
  → convert（L1+L2 → popunder-rules.json 生成）
  → bundle 同梱版 + docs/cdn/ 版 + version 更新を同時出力
  → CI（push もしくは workflow_dispatch）で GitHub Pages 反映
  → アプリ起動時 FilterDownloader が CDN から App Group へ DL
  → 数時間で端末に反映（App Review 不要）
CDN 不達時 → bundle 同梱版にフォールバック（resolver 既存挙動）
```
[[feedback_content_blocker_must_bundle_full_ruleset]] 遵守: bundle には常に「その時点の完全な popunder-rules.json」を同梱（初回 DL 前/CDN 不達でも機能する）。

## 6. メンテナンス（dogfooding）フロー
- kureho が新サイトで popunder を踏む → そのサイトを `popunder-aggressive-sites.json` に追加。
- **allowlist の決め方**: 2026-06-17 に作成した desktop 解析を **`scripts/analyze-popunder.js`（リポジトリ常設ツール）に昇格**。サイト URL を渡すと「遮断される third-party script ＋ 残すべき player/CDN（＝allowlist 候補）」を headless で出力 → `allow` に転記。
- 将来拡張（任意・本 spec の範囲外）: Phase 3（信頼レポーター閾値バイパス・2026-06-17 有効化済み）を使い、kureho の報告→aggressive-sites への半自動反映。iOS ユーザーは横取り .js を観測できないが、開発者の kureho は観測可能。

## 7. エラー処理 / 安全
- **別トグル**: 誤ブロックでも本体 ad-block 無傷。壊れたらユーザーが popunder トグルのみ OFF。
- **誤遮断の修復**: L2 で必要 script を切った場合、allowlist に追加 → CDN 更新で即修復（審査不要）。
- **CDN 不達**: bundle フォールバック（既存 resolver 挙動）。downloader の失敗は既存挙動を壊さない best-effort。
- **ルール budget**: 別拡張枠に余裕。converter が上限超過を検知したら build を fail させる（安全弁）。

## 8. テスト（TDD）
- **converter 単体**: `popunder-script-networks.txt` / `popunder-aggressive-sites.json` → 期待 Content Blocker JSON。検証点: (a) L1 の url-filter/resource-type/load-type、(b) L2 の `if-domain` 限定、(c) **block → ignore-previous-rules の順序**、(d) ルール数上限。
- **resolver**: 既存 `PopunderRulesResolverTests` 維持＋ App Group 優先 / bundle フォールバックの分岐。
- **downloader**: CDN DL → App Group 保存の best-effort。失敗時に既存挙動（bundle）を壊さない。
- **回帰検証（headless）**: `scripts/analyze-popunder.js` で対象サイトの「popunder gesture listener 消滅 ＋ player 生存」を確認（手動/任意の verification ツール。CI 必須化はしない＝外部サイト依存のため flaky）。

## 9. 決定ログ（brainstorming 2026-06-17）
1. ゴール = 実効重視（手段問わず体感で減らす）。
2. 強さ = アグレッシブOK（別トグルゆえ本体無傷・回転ヒューリスティック許容）。
3. Approach = C ハイブリッド（L1 全サイト安全網＋L2 対象サイトアグレッシブ）。
4. 配信 = CDN 更新対応（App Review 不要の living list・resolver は既に App Group 対応済）。

## 10. リスク / 未解決
- **headless 検知の限界**: desktop 実測は gesture listener 登録から推定（window.open 実発火は headless で 0）。厳密確定には実機ネットワークログ（README Option 3）が要るが、v3.3.0 の設計判断には十分な解像度。
- **回転の追従**: L2 が効くのは「収録済みサイト」のみ。未収録サイトは L1（部分的）のみ。dogfooding 運用の継続が前提（kureho が使う＝更新される、という構造で相殺）。
- **allowlist 不足での破損**: 新サイト追加直後は allowlist が不完全でサイトが壊れ得る。CDN 更新で即修復できる前提で許容。
- **iOS content blocker の `if-domain` / `load-type` 挙動**: 実装時に WebKit の正確な仕様（ワイルドカード `*tokyomotion.net` の解釈、`load-type:third-party` の判定基準）を converter テストで固定し、シミュレータで実挙動を確認する。
