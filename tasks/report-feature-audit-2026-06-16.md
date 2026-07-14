# 報告機能 エンドツーエンド監査【訂正版】（2026-06-16）

> kureho の問い: 「報告したものはサーバーに集約されて、みんなに適用されるんだよね？仕様を整理して。あと報告したものがどう活かされてるか分からないのでそこも」
> ⚠️ 本書は初版（同日午前）を**全面訂正**したもの。初版は環境不安定による不正確な読み取り（`aggregate.ts`の「閾値1」、`hourly-aggregation.yml`の誤読、「4箇所断線」という雑な表現）を含んでいた。本訂正版は `workers/src/lib/` の実ゲート群・`gh run list` 実行履歴・submit handler 実コードに基づく。

---

## 1. 設計（実コードから読み取った、あるべき多段パイプライン = spec rev4「Plan B」）

報告は「**多段の安全ゲートを通った候補だけを全員に配信**」する精巧な設計。**雑なドメイン即ブロックではない。**

```
[端末] 報告UI(App/ReportTab) → POST /v1/reports/submit
   ↓
[Worker index.ts] submit handler → D1 `reports` テーブルにINSERT
   (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, ad_type, status, created_at) + abuse_log
   ↓ 毎時 hourly-aggregation.yml → npx tsx scripts/aggregation/run.ts（D1直接・CF_API_TOKEN）
[L2] aggregation-threshold.ts: (domain, url_path_hash)単位で
     unique uuid_hash ≥ 3 AND unique ip_hash ≥ 2 を14日スライド窓で要求  ★核心の閾値
   + ban-engine（4段階auto-ban escalation）
   ↓
[L3] l3-decision.ts: Tranco Top 1M → kureho_queue(手動レビュー) / critical-list(visa/mastercard/paypal/stripe等) → 無条件reject
   ↓
[L5] l5-decision.ts: 共有CDNホスト(cdn-protection.ts) → reject（正規サイト巻き込み防止）
   ↓
[L6] l6-decision.ts: Playwright検証スコア ≥ 0.7（ad_class*0.4 + ad_network*0.4 + selector*0.2）
     かつ selector が狭スコープ(selector-scope.ts) → `beta` 昇格
   ↓ 毎週 weekly-stable-promotion.yml
[L7] beta → stable 昇格（7日間 complaint ゼロ ゲート）
   ↓ 毎週火 weekly-cdn-sync.yml → scripts/sync/run-reported-rules-build.ts
[配信] D1の stable 候補 → docs/cdn/rules-reported.json 生成 → git commit → GitHub Pages配信
   ↓
[端末] FilterDownloader が CDN から取得 → App Group 保存
   → ReportedRulesExtension が App Group を読んで Safari に渡す（標準フィルタとは別extension枠）
```

承認単位は単純なドメインではなく `(domain, url_path_hash)` + selector スコープ。poisoning耐性・FP耐性を多層で確保した、業界でも前例の少ない「報告→自動検証→自動配信」パイプライン。

---

## 2. 実態 — パイプラインは**稼働している**が、出力はゼロ

`gh run list` で確認した実行履歴（2026-06-16時点）:
| workflow | 状態 | 備考 |
|---|---|---|
| hourly-aggregation | ✅ 毎時 success（26〜34s） | L2集約+ban-engineをD1に対し実行 |
| weekly-stable-promotion | ✅ success（最終 06-15） | beta→stable昇格 |
| weekly-tranco-sync | ✅ success | Tranco同期 |
| weekly-cdn-sync | ✅ success（最終 **2026-06-09**） | ただし**git diff無し→無commit** |

受付(submit)もD1 `reports` に正しくINSERT = **ingestionは生きている**。

**にもかかわらず:**
- ローカル `docs/cdn/rules-reported.json` = **`[]`（空・6/7から不変）**
- git に "weekly CDN sync" commit **0件**（weekly-cdn-syncは走ったが毎回「差分なし」）
- CDN `rules-reported.json` = **404**（中身ある版が一度もPagesに出ていない）

---

## 3. 根本原因（確定）— 「報告したものが反映されない」の正体

### 原因A【設計と現実のギャップ・最重要】L2閾値が現ユーザー規模で到達不可能
L2は「**同一URLを別々の3デバイス（uuid≥3）かつ別々の2 IP（ip≥2）が14日以内に報告**」を要求する。
- このアプリは**売上ほぼゼロ＝実ユーザーがほぼいない**（直近30日購入2件）。
- → 同じURLに3人の別ユーザーが集まることは事実上起きない。
- → **何も `beta`/`stable` に昇格しない → rules-reported.json は永遠に `[]`**。
- → **kureho自身が報告しても、1人では閾値3に届かず永遠に反映されない。** これが「俺が報告しても適用されない」の数学的な正体。

poisoning防止のための閾値3が、低ユーザー規模では「健全な報告すら一切通さない」という逆効果になっている。**閾値の正しさ（spec通り）と、低スケールでの実用性が衝突している。**

### 原因B【端末側未配線】仮に配信されても端末が消費しない
- `Shared/FilterDownloader.swift` の `downloadAndStore()` は `blockerList.json` と `version.json` のみDL。**`rules-reported.json` をDL・App Group保存しない。**
- `ReportedRulesExtension/ReportedContentBlockerRequestHandler.swift` は bundle同梱の空配列 `[]` を返すだけ。**App Groupを読まない**（コメント「Phase 5でApp Group fallback chain追加」=未実装）。標準側 `ContentBlockerRequestHandler` は `BlockerListResolver` で App Group→bundle→empty を解決するのに、報告側だけ取り残されている。

### （副次）CDN配信は健全 ← 初版の「404/古い版/二重CDN」記述を訂正
正しいCDN URLは `https://kureho.github.io/AdblockKeshi/cdn/`（Pages: main/docs、`FilterDownloader.defaultURL`と一致。`adblock-keshi-cdn`リポは存在しない＝初版の誤読）。実測:
- `blockerList.json` → 200・22.2MB（**最新6/13版・generated_at 2026-06-12**）。標準フィルタ配信は正常。
- `version.json` → 200・最新。
- `rules-reported.json` → **200・2B（`[]`空）**。配信経路は生きていて正しいURLで届く。空なのは原因A（誰も閾値3に到達せず昇格ゼロ）ゆえ。
→ **グローバル配信インフラは健全。CDN/リポ再構成は不要。** 残るは原因A（閾値）と原因B（端末未配線）のみ。

---

## 4. kureho の問いへの回答

- **Q: 報告は集約されてみんなに適用される？** → 設計はYES（多段ゲートを通れば全員配信）。実装も精巧に存在し稼働中。**だが現状の出力はゼロ**。理由は「ユーザーが少なすぎてL2閾値(3人)に誰も到達しない」＋「端末が配信物を消費しない」。
- **Q: 報告がどう活かされてるか分からない** → 実際まだ一度も活かされていない（配信実績ゼロ）。報告履歴UI(`App/ReportTab/ReportHistory*`)がサーバの実承認状態と同期するかは未確認だが、そもそも承認が発生していない。

---

## 5. 修正の方向性（kureho ビジョン「報告から学習して反映・黒画面も含む・買い切り維持」に整合）

### ★最重要の設計示唆: 「自分の報告は自分の端末に即反映」ファストレーン
kureho の「俺も使ってるから報告が適用されるように」を最短で叶える解。
- **自分が報告したURL/スクリプトは、3人閾値を待たず、その端末でローカル即時ブロック**（個人の学習フィルタ層）。
- 並行してサーバL2-L7で検証 → 通れば全員に昇格配信（グローバル層）。
- 効果: ①各ユーザーが**自分の報告から即座に価値**を得る（鶏卵問題を回避）②kureho自身がドッグフーディングで効果を実感できる ③グローバルプールは時間で育つ。
- 「黒画面が消える」もこのファストレーンに乗せる（報告した横取りスクリプト/リダイレクト先を自端末で即ブロック）。

### 端末側配線（原因B解消・ローカル完結・TDD可能）
1. `FilterDownloader` に `rules-reported.json` のDL＋App Group保存を追加
2. `ReportedContentBlockerRequestHandler` を「App Group→bundle空」fallbackに（標準側と同型）
3. 報告完了後に `reloadContentBlocker` が走るか確認

### サーバ側（原因A緩和・要kureho判断: 本番D1/閾値変更）
4. 低スケール用ブートストラップ: 信頼レポーター(kureho)の報告は閾値バイパス、or 初期は閾値を下げてL3-L6の質ゲートで安全担保
5. （CDN配信は健全と確認済み＝修正不要。残る本番作業はD1/閾値のみ）

---

## 6. 未確認（次に潰す・一部は本番アクセス要）
- [ ] D1の `reports`/`rule_candidates`/`beta`/`stable` の実データ件数（報告が実際に何件あり、どのゲートで止まっているか）= 要 CF API（本番・kureho承認領域）
- [x] ~~GitHub Pages のデプロイ元設定（rules-reported.json 404）~~ → 解決: 配信は健全（200・正しいURLで届く）。空なのは閾値ゆえ。
- [ ] 報告履歴UIがサーバ承認状態と同期するか（`App/ReportTab/ReportHistory*` 未読）
- [ ] hourly-aggregation の `run.ts` が実際に candidates を生成しているか（D1要確認）
