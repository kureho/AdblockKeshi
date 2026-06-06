<!-- [paid-approved-by-kureho] spec doc 文書のみ、ASC API 呼び出しなし、課金影響なし -->
# 広告消し v3.0「学習する広告消し」設計 spec

**日付**: 2026-06-06
**status**: Draft (brainstorm 合意完了、spec review loop 前)
**対象アプリ**: 広告消し (com.kureho.adblockkeshi、App ID 6774906945)
**現配信中**: v2.1.1 (READY_FOR_SALE、2026-06-04 配信開始、2026-06-06 ASC API verify 済)
**提出予定**: v3.0.0 build 12
**関連 spec**:
- `~/claude/docs/superpowers/specs/2026-06-06-learning-adblock-design.md` (v0.3 Frozen) — 「広告消し 速報」別アプリ案、本案で本体統合に方針転換、副産物 (Cloudflare 0 円構成 / 8 層 safety gate / Privacy 設計) を本案で流用

---

## 0. 背景と意思決定の経緯

### kureho の moat 仮説 (GO 根拠)

- 「報告で学習する広告ブロック」を本体に統合 → kureho ゼロタッチで運用
- 仮説: **運用コスト 0 円 × データ蓄積で 1 強になれる**
- 凍結 spec の判断「10-14 週工数 vs 他 8 アプリ機会費用」を「moat 投資の正当性」で上書き

### 凍結 spec との関係

凍結 spec (`2026-06-06-learning-adblock-design.md` v0.3) は「広告消し 速報」= **別アプリ ¥1,500** 案。本案は **本体統合 v3.0 ¥700**。差分:

| 観点 | 凍結 spec (速報、別アプリ) | 本案 (v3.0、本体統合) |
|---|---|---|
| 提出 | 新規 bundle id | 既存 com.kureho.adblockkeshi 継続 |
| 4.3(b) Spam リスク | あり (別アプリ差別化必要) | なし (同一アプリ) |
| 1.2 UGC リスク | あり | あり (同等) |
| 価格 | ¥1,500 | ¥700 |
| 工数 | 10-14 週 | 10.5-14.5 週 (履歴 UI +1.5 週、スクショ -1 週) |
| 既存ユーザー | 関係なし | 影響あり (アップグレード経路設計必要) |

副産物として流用するもの: Cloudflare Workers + D1 + Turnstile 構成、8 層 safety gate、HMAC ephemeral token 設計、Privacy Policy 文案、Nutrition Label 設計。

### 残課題 (advisor からの flag、brainstorm 時に kureho に明示済)

- **chicken-and-egg**: moat 形成に初動ユーザー ≥ 数千が必要、レビュー 0 の現状から数千への橋渡しは ASO/PR 側で別途
- **凍結時 verify**: 「E 軸 (学ぶ/育つ) = 需要ゼロ」のため「学習する」を訴求の主軸にしない (B 軸=消えない広告を主軸、moat は実態として静かに効かせる)

---

## 1. アプリ identity

| 項目 | 内容 | 字数 |
|---|---|---|
| App Store name | `学習する広告消し - 消えない広告もブロック` | 22 字 |
| subtitle | `他で消えない広告も、報告で進化` | 15 字 |
| bundle id | `com.kureho.adblockkeshi` (継続) | - |
| Primary Category | UTILITIES (継続) | - |
| 価格 | ¥700 (¥500 → ¥700 即値上げ) | - |

### 訴求の三層構造

- **表 (ASO/store)**: B 軸「消えない広告も消える」が主、H 軸「学習する」が修飾
- **中 (description)**: B 軸 + H 軸 + F' 軸 (個人開発・買い切り) + 既存 v2.0 詐欺サイトブロック
- **裏 (moat 形成)**: 報告データ蓄積で競合との品質差広げる (訴求しない、実態で勝つ)

### 隠す/出さない訴求

- E 軸「みんなで育てる」「集合知」(凍結時 verify で需要ゼロ判定済)
- Apple 商標 (Safari/iPhone/iPad/iOS) は name/subtitle/keywords NG (5.2.5)

---

## 2. 報告タブ UX

### 全体構造変更

```
v2.x: 単一画面 (準備する → ON → 完了)
v3.0: TabView 2 タブ
  ├ Tab A: ブロッカー (既存画面そのまま)
  └ Tab B: 報告 (新規)
```

### Tab B の画面遷移

```
[エントリ] CTA
  ↓
[入力フォーム]
  ・URL (必須): クリップボード自動検出 + 貼り付けボタン
  ・メモ (任意、200字): 「動画上のオーバーレイ」等
  ↓ Turnstile + HMAC ephemeral token 取得
[送信完了] 「通常 7-14 日以内に反映を検討します」
  ↓
[報告履歴] v3.0 で実装
  ・ステータス: pending / validating / approved / rejected_no_ad_detected / rejected_safety_gate
  ・取得: GET /v1/reports/by-uuid-hash/{hash}
```

### 含めないもの (YAGNI、kureho 確認済)

- スクショ送信 (Playwright 自動検出で代替、Privacy 軽量化、UX 1 step 短縮)
- カテゴリ選択、重要度スライダー

### 入力 validation

| 項目 | ルール |
|---|---|
| URL | `https://` 必須、200 字以内 |
| メモ | 200 字以内、URL 含むと拒否 |
| Turnstile | 透明 challenge クリア |
| rate limit | 1 端末 5 件/日、30 件/月 |

### Privacy

| データ | 端末→サーバ送信 | 保存期間 |
|---|---|---|
| 報告 URL | ✅ | 14 日 (匿名化後継続) |
| メモ | ✅ | 同上 |
| 端末 UUID | ❌ (原本は Keychain のみ)、`SHA-256(uuid + server_salt)` のみ送信 | 90 日 |
| IP | Workers 受信時のみ、即ハッシュ化 | 14 日 |
| 閲覧履歴 | ❌ (iOS Content Blocker サンドボックスで技術的に取得不可) | - |

---

## 3. 報告受信 infra (Cloudflare 0 円構成)

### スタック

| サービス | 用途 | 無料枠 | 想定使用率 (10k ユーザー × 月 5 報告) |
|---|---|---|---|
| Cloudflare Workers | API endpoint | 100k req/day | 1.7% (1667/日) |
| Cloudflare D1 (APAC primary) | SQLite DB | 5GB / 5M reads / 100k writes per day | 1% |
| Cloudflare Turnstile | bot 防止 | 無制限、商用 OK | - |
| GitHub Actions (Linux runner) | 月次/週次/日次/時次タスク | public repo 無制限 | timeout 厳守 |

### Endpoint

| Method | Path | 用途 |
|---|---|---|
| POST | `/v1/reports/token` | Turnstile clear → HMAC ephemeral token (5分有効) |
| POST | `/v1/reports/submit` | 報告本体送信 (token + URL + memo) |
| GET | `/v1/reports/by-uuid-hash/{hash}` | 履歴取得 |
| GET | `/v1/health` | health check |

### D1 スキーマ

`reports` / `rule_candidates` / `abuse_log` / `bans` の 4 テーブル。詳細は brainstorm Section 3 参照、implementation plan で確定。

### Secrets (Wrangler secrets)

`HMAC_KEY`, `SERVER_SALT`, `TURNSTILE_SECRET`, `GH_DISPATCH_TOKEN`

### Rate limit

- per uuid_hash: 5/日, 30/月
- per ip_hash: 5/15min, 30/月
- per domain (全集計): 1000/日 (DDoS 対策)
- 全体 instance: **10000/日 hard cap** (free tier 防衛)

### 🚨 課金暴走防止 (memory `feedback_no_silent_paid_infra` 遵守)

- Cloudflare Workers Paid プラン無効化維持
- 無料枠超過時 = 自動 503 (有料化しない)
- 全体 hard cap 10000 req/日を Workers コードで enforce、超えたら 429
- 月初に kureho が dashboard で req 数確認

---

## 4. 自動承認パイプライン (8 層 safety gate + 2 extension)

### 8 層 safety gate

| 層 | 目的 | 実装場所 | 閾値 |
|---|---|---|---|
| L1 | Turnstile + rate limit | Workers | (Section 3 参照) |
| L2 | threshold 集計 | Actions (hourly) | 3 unique uuid_hash + 2 unique ip_hash + 14 日 sliding window |
| L3 | Tranco Top 1M + critical list | Actions (daily) | Top 1M = 自動 reject + kureho queue 隔離、critical 50 domain は絶対不可 |
| L4 | selector scope 制限 | Actions (daily) | URL 単位 no-rule、CSS selector は body/html/* 等の wide scope reject |
| L5 | 共通 CDN 保護 | Actions (daily) | Akamai/Cloudfront/Google APIs 等 30 件 list 照合 |
| L6 | Playwright validation | Actions (daily, Linux, 30 分) | DOM 走査 → 広告判定スコア ≥ 0.7 で pass |
| L7 | β tier 7 日待機 | Actions (weekly) | beta_started_at + 7 日 + 苦情なし → stable 昇格 |
| L8 | 苦情 auto-rollback | Workers + Actions | 同 selector 苦情 3 unique uuid_hash → 即時 stable→rejected、30 日 cooldown |

### 2 Content Blocker extension 構成

iOS Safari Content Blocker の単一 extension 上限 (公式未明示、実装的に 150k で動作) を超えるため、**2 extension 構成**で base 削減回避:

| extension | bundle id | display name | bundle 内容 | ルール上限 |
|---|---|---|---|---|
| ContentBlockerExtension | `com.kureho.adblockkeshi.blocker` | 広告消し 本体 | rules-base.json (15万、EasyList+AdGuard+URLhaus+Phishing.Database) | 既存上限内 |
| ReportedRulesExtension (新規) | `com.kureho.adblockkeshi.reportedblocker` | 広告消し 学習 | rules-reported.json (報告由来、初期 0、最大 5万) | 別 extension で確保 |

★ 実装段階で「単一 app の Content Blocker extension 数上限」を実機検証必要 (Apple 公式 docs 未明示)。失敗時 fallback は base ad-rules.json 内に reported merge (base 5k 削減)。

### 2 extension UX

- iOS Settings → Safari → 機能拡張で **2 個並ぶ**、ユーザーは両方 ON
- 既存ユーザー: WhatsNew + 継続バナーで「学習」を ON 誘導、強制せず (base のみ ON でも害なし)
- 状態検出: `SFContentBlockerManager.getStateOfContentBlocker(withIdentifier:)` 並行 fetch
- 4 パターン UX: 両方 ON (通常) / base のみ (黄バナー) / 学習のみ (赤バナー) / 両方 OFF (onboarding 戻し)
- 報告タブは状態と連動: 学習 OFF 時に警告表示
- 完了画面に moat 可視化「フィルタ最終更新 / 本体ルール 150,000 件 / 報告で追加 N 件 (先月 +M 件)」

### kureho ゼロタッチの境界線

- **介入ゼロ**: 一般サイトへの報告 → L2-L8 で全自動判定、苦情 rollback も全自動
- **介入必須 (= 例外)**: Tranco Top 1M ドメイン報告 → kureho queue に隔離 (moat 形成期はゼロ件想定)、critical list 50 domain は queue にも入らず即破棄

---

## 5. ルール反映フロー & 既存 workflow 統合

### Workflow 構成

| Workflow | 種別 | トリガー | timeout | 役割 |
|---|---|---|---|---|
| `monthly-filter-update.yml` | 既存 | 月次 + dispatch | 30 分 | rules-base.json 生成 → bundle 同期 → CDN push |
| `hourly-aggregation.yml` | 新規 | hourly | 5 分 | L2 threshold 集計 |
| `daily-validation.yml` | 新規 | daily 03:00 UTC | 30 分 | L3-L6 validation |
| `weekly-stable-promotion.yml` | 新規 | weekly 月 04:00 UTC | 10 分 | L7 β tier → stable 昇格 |
| `weekly-cdn-sync.yml` | 新規 | weekly 火 05:00 UTC | 20 分 | rules-reported.json 生成 → bundle 同期 → CDN push |
| `tranco-sync.yml` | 新規 | monthly | 30 分 | Tranco Top 1M sync |
| `complaint-monitor.yml` | 新規 | hourly | 5 分 | L8 苦情監視 → rollback trigger |

🚨 全 workflow に `timeout-minutes` 必須 (memory `workflow-timeout-guard` hook 遵守)、Linux runner のみ (macOS runner 禁止、$113 損失再発防止)。

### concurrency 制御

```yaml
concurrency:
  group: cdn-sync
  cancel-in-progress: false
```

### CDN 構造

```
docs/cdn/
  rules-base.json       monthly-filter-update が更新 → ContentBlockerExtension
  rules-reported.json   weekly-cdn-sync が更新 → ReportedRulesExtension (新規)
  version.json          generated_at + base.rule_count + reported.rule_count + added_last_month
```

### bundle 同梱 + CDN fallback (既存パターン継承)

| ファイル | bundle 同梱先 | CDN fallback |
|---|---|---|
| ad-rules.json | Extension/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/rules-base.json |
| reported-rules.json (新規) | ReportedRulesExtension/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/rules-reported.json |
| version.json | App/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/version.json |

### 反映タイムライン (ユーザー視点)

報告送信 → 集計 (+1h) → 検証 (+1d) → β tier 開始 (+1d) → stable 昇格 (+7d) → CDN 反映 (+1週) → 端末 DL (+24h) = **最悪 16 日**。報告タブで「通常 7-14 日以内」と告知済 (報告タブ Section 2 参照)。

---

## 6. Apple 審査対策

### 適用 Guideline と reject リスク

| Guideline | 該当性 | リスク |
|---|---|---|
| 1.2 (Safety - UGC) | ✅ | yellow |
| 5.2.5 (Intellectual Property) | ⚠️ 直前事故 | 要厳格対応 |
| 2.3.7 (Pricing metadata) | ⚠️ memory `feedback_pricing_metadata_strict` 4 回違反済 | 要厳格対応 |
| 5.1.1 / 5.1.2 (Privacy) | ✅ | medium |
| 4.3(b) (Spam) | ✅ 本体統合で **回避** | green |

### 1.2 UGC 5 要素対応 (凍結 spec から流用)

| 要素 | 公式要件 | 実装 |
|---|---|---|
| (a) フィルタリング | objectionable material filtering | URL validation + Tranco whitelist + 50 critical domain blocklist + selector scope |
| (b) 報告手段 | report mechanism | 報告タブ footer mailto: info@kureho.app |
| (c) abuse ブロック | block abusive users | uuid_hash + ip_hash rate limit + 30 日 cooldown ban |
| (d) 連絡先 | published contact | info@kureho.app + https://kureho.app/contact?product=adblockkeshi |
| (e) 対応時間 | timely response | Privacy Policy に 24h 以内対応明記 |

### Review Notes (英語、提出時)

英語 1 ページ。「No user-to-user content sharing」「8 層 safety gate」「No human (developer) intervention」を明示。demo steps で Send → 履歴で検証中を実演可能。詳細文面は brainstorm Section 6-3 参照、提出時 reviewNotes に確定転載。

### 5.2.5 / 2.3.7 対策

- Apple 商標 (Safari/iPhone/iPad/iOS/Apple/Siri/iMessage) は name/subtitle/promo/keywords/screenshots に **絶対含めない**
- 価格表記 (¥/Free/無料/割引) は description のみ可、その他 NG
- 提出前 metadata grep を CI hook に組み込み

### keywords 新案

```
広告,消す,ブロック,うざい,詐欺,フィッシング,セキュリティ,学習,報告,進化
```

現状 `Safari` 含むため要置換 (5.2.5 再発防止)。

### promotional_text 新案

```
他のブロックアプリで消えない広告を、報告で進化するフィルタが対応。
報告タブから URL を送ると、自動検証を経て広告ブロックリストへ追加。
買い切り、サブスクなし、閲覧履歴も送信しません。
```

### Privacy Policy 追記

kureho.app/apps/adblock-keshi/privacy に新規セクション追加 (brainstorm Section 6-5 参照):
- 報告データの取り扱い
- 24h 対応コミット
- 削除依頼窓口 (info@kureho.app)
- 保管インフラ (Cloudflare Workers/D1)

### Nutrition Label 更新

| Data Type | Linked? | Tracking? | Purpose |
|---|---|---|---|
| User Content > Other User Content (報告 URL/メモ) | ❌ Not Linked | ❌ | App Functionality |
| Identifiers > Other (UUID hash, IP hash) | ❌ Not Linked | ❌ | App Functionality |

### リスク × 対応マトリクス (brainstorm Section 6-8 改)

各リスクに予防/検知/対応/escalation を設計済 (4 リスク × 4 段階)。詳細は brainstorm 記録。共通原則:
- 24h ルール (reject 通知 → 24h 以内 Resolution Center reply)
- reply 先行 (cancel 前に reply 必須、memory `feedback_resolution_center_reply_before_cancel`)
- Apps Metrics Dashboard 連携 (hourly monitor)
- 段階退避 (feature flag で報告タブ OFF 可、v3.0 build に事前組み込み)

### feature flag による段階退避設計

```swift
struct FeatureFlags {
    static let reportTabEnabled: Bool = RemoteConfigStore.shared.boolValue(forKey: "report_tab_enabled", default: true)
}
```

`docs/cdn/feature-flags.json` を kureho が編集 → CDN deploy → 端末次回起動で OFF。新 build 提出不要で報告タブ非表示化可能。Apple へは「server-side toggleable」を review notes に明示。

---

## 7. 価格戦略 & version ロードマップ

### 価格

| Version | 価格 | 思想 |
|---|---|---|
| v2.1.x → v3.0 | ¥500 → **¥700** | 機能拡張に伴う適正価格化 (運営コスト、moat 投資)。値上げ自体が目的ではない |
| v3.1 / v3.2 | **¥700 維持を default** | 次の値上げは v4.0 メジャー拡張時のみ検討 |

### retreat 戦略

v3.0 リリース 4 週後 KPI 評価:
- 月次 DL が v2.1.x 比 50% 未満 → ¥600 retreat 検討 (binary 提出不要、Price Tier 変更で 24h 反映)
- 「高すぎる」苦情 > 30% → 同上

### metadata 価格表記の場所縛り (memory `feedback_pricing_metadata_strict` 厳守)

- description のみ「¥700」「値上げ」「買い切り」可
- subtitle / promotional_text / keywords / screenshots に **¥/Free/無料/割引** NG
- 「買い切り」「サブスクなし」のみ subtitle/promo/keywords でも OK

### version ロードマップ

| Version | 主要変更 | 価格 |
|---|---|---|
| v3.0.0 | 報告タブ + 2 extension + 8 層 safety gate + feature flag + ¥700 値上げ | ¥700 |
| v3.0.1 | reject 時 hotfix (metadata or feature flag OFF) | ¥700 |
| v3.1.0 | 履歴 UI 改善、月次 stats UI、運用安定化 | ¥700 維持 |
| v3.2.0 | 自動クロール (Tranco 全件 ML 検出) moat 強化 | 検討 |
| v4.0.0 | マルチブラウザ対応? | 未定 |

### 開発スケジュール (10.5-14.5 週、writing-plans で詳細化)

| Phase | 期間 | 主作業 |
|---|---|---|
| 1: Infra setup | Week 1-2 | Cloudflare Workers + D1 + Turnstile、project.yml 2 extension |
| 2: 報告タブ UI + API | Week 3-4 | SwiftUI Tab B、Workers handler |
| 3: 8 層 safety gate | Week 5-7 | L1-L8 各層、Tranco sync、Playwright validation |
| 4: workflow 統合 | Week 8-9 | Actions 7 個追加、CDN sync、concurrency |
| 5: UI 仕上げ + Privacy | Week 10-11 | 履歴 UI、moat 可視化、feature flag、Privacy Policy、Nutrition Label |
| 6: 検証 + 提出準備 | Week 12-13 | シミュレータ + 実機テスト、4 点監査、metadata 準備 |
| 7: 提出 + Apple 審査 | Week 14 | 提出、Resolution Center 監視 |
| 8: 配信後監視 | Week 15-22 | v3.1 開発並行、moat 観測 |

---

## 8. 既存配信中 build との衝突整理

### 配信状態 (2026-06-06 ASC API verify 済)

| Version | state |
|---|---|
| v2.1.1 | READY_FOR_SALE ✅ (最新) |
| v2.1.0 | READY_FOR_SALE |
| v2.0.0 | READY_FOR_SALE |
| v1.0 | READY_FOR_SALE |

v3.0 提出経路に blocking なし。

### branch / PR 戦略

```
main (v2.1.1 配信中、緊急 hotfix 余地確保)
  └── feature/v3.0-learning-adblock (長期 10-14 週)
        ├── feat/cloudflare-infra
        ├── feat/report-tab-ui
        ├── feat/safety-gate-l1-l4
        ├── feat/safety-gate-l5-l8
        ├── feat/github-actions-workflows
        └── feat/privacy-policy-update
```

### v3.0 提出時設定

- MARKETING_VERSION: 3.0.0
- CURRENT_PROJECT_VERSION: 12
- ASC: 新 AppStoreVersion + build 12 attach + metadata 更新 + Price Tier 変更 + App Privacy 更新 + Phased Release ON
- 4 点監査 (memory `feedback_apple_submission_state_audit`)

### 既存ユーザーへの影響

| 観点 | v2.1.1 → v3.0 アップデート |
|---|---|
| 価格 | 追加課金なし (買い切り) |
| 既存 extension | 継続、ON 状態維持 |
| 新 extension | 追加、初期 OFF (WhatsNew + バナーで誘導、強制せず) |
| 報告タブ | v3.0 から開始、空状態 |

### TestFlight 検証

- 開発中はシミュレータ + 実機優先 (memory `feedback_simulator_first_verification`)
- TestFlight は提出直前の最終回帰のみ (internal tester、external invite なし)

### rollback 経路

| シナリオ | rollback |
|---|---|
| Apple reject 1.2 UGC | feature flag `report_tab_enabled=false` → metadata-only 再提出 |
| 苦情 rollback 大量発生 | weekly-cdn-sync 停止、reported-rules.json 空上書き |
| API endpoint 障害 | 端末側リトライキューで吸収 |
| 重大バグ | v2.1.1 配信維持、ASC で「以前のバージョン」設定で 24h 巻き戻し可能 |

### v3.0 開発中の v2.1.x hotfix

- main から hotfix/v2.1.2-* ブランチ → main merge → tag → ASC 提出
- v3.0 ブランチに cherry-pick で同期 (extension 構成差分で conflict 注意)

### memory 更新責務 (brainstorm 完了後)

- `MEMORY.md` の「v2.1.1 WAITING_FOR_REVIEW」記述 → READY_FOR_SALE に更新
- `project_adblockkeshi.md` 同様
- 新規記録: v3.0 brainstorm spec 作成 (本ファイルへの link)

---

## 9. リスク総覧と対応マトリクス

| カテゴリ | リスク | 確率 | 影響 | 対応 |
|---|---|---|---|---|
| Apple 審査 | 1.2 UGC reject | 中 | release 1-2 週遅延 | review notes で safety gate 強調、即 re-submit |
| Apple 審査 | 5.2.5 metadata 残骸 | 低 | 同上 | 提出前 grep、CI hook |
| Apple 審査 | 5.1.1 Privacy 不整合 | 低 | 同上 | Privacy Policy + Nutrition Label 提出前完全一致 |
| Apple 審査 | 「完全自動」誤読 → moderation 質問 | 中 | release +3-5 日 | review notes に "No human intervention" 明示 |
| 価格 | 機能追加 + 値上げ同時で初動 DL 落ち | 中 | 売上減 | 4 週 KPI monitor、¥600 retreat 余地 |
| 既存ユーザー | 「いきなり値上げ」反発 | 低 | review 低下 | 買い切り影響なしを WhatsNew で説明 |
| 技術 | 2 extension 上限超え (Apple 公式未明示) | 低 | 設計やり直し | 実機検証で確認、fallback は base merge |
| 技術 | Cloudflare Workers DDoS で free tier 超過 | 低 | $5/M (有料化) | hard cap 10k/日、超過時 429 |
| moat | chicken-and-egg、初動ユーザー不足 | 中 | moat 形成停滞 | ASO/PR で別軸、新規 LP は app-support に |
| moat | E 軸 (学ぶ) 訴求が刺さらない | 中 | DL 変動 | name 主軸は B 軸、moat は実態で勝つ |

---

## 10. 工数見積サマリ

| Phase | 週数 | 主要 deliverable |
|---|---|---|
| Phase 1-2: Infra + UI 基礎 | 4 週 | Cloudflare 稼働、2 extension build、報告タブ画面 |
| Phase 3-4: safety gate + workflow | 5 週 | 8 層 全実装、Actions 7 個 deploy |
| Phase 5: UI 仕上げ + Privacy | 2 週 | 履歴 UI、moat 可視化、Policy 更新 |
| Phase 6: 検証 | 2 週 | シミュレータ + 実機テスト全網羅 |
| Phase 7: 提出 | 1 週 | 提出 + 4 点監査 |
| **合計** | **14 週** (最短 10.5 週、最長 14.5 週) | v3.0 リリース |

---

## 11. 確定済みの決定事項 (brainstorm 合意)

1. ✅ name: `学習する広告消し - 消えない広告もブロック` (22 字)
2. ✅ subtitle: `他で消えない広告も、報告で進化` (15 字)
3. ✅ 訴求軸: B 軸前面 (消えない広告) + H 軸修飾 (学習する) + moat 実態形成
4. ✅ 価格: v3.0 から ¥700 即値上げ (値上げ自体は目的ではない、適正価格化)
5. ✅ 完全自動 (kureho ゼロタッチ): T3 重量実装、8 層 safety gate 必須
6. ✅ 受信 infra: Cloudflare Workers + D1 + Turnstile (0 円 hard cap)
7. ✅ Content Blocker: 2 extension 構成 (本体 + 学習)、base 削減回避
8. ✅ 報告タブ: URL + メモのみ (スクショ省略)、履歴 UI を v3.0 で実装
9. ✅ 既存ユーザーへの強制誘導なし、base のみ ON でも害なし
10. ✅ feature flag で報告タブ OFF 可能 (段階退避)
11. ✅ v3.0 開発中 main は v2.1.x hotfix 余地維持
12. ✅ TestFlight は提出直前の最終回帰のみ、シミュレータ + 実機優先

---

## 12. 次のステップ

1. **spec review loop** (brainstorming skill の checklist)
2. spec-document-reviewer subagent dispatch
3. issue 解消 → 再 dispatch (max 5)
4. **kureho による spec レビュー** (本ファイル approval)
5. **writing-plans skill** で詳細実装プラン作成

---

## 付録 A: 凍結 spec からの流用と差分

### 流用 (副産物の引き継ぎ)

- Cloudflare Workers + D1 + Turnstile + R2 (R2 はスクショ省略で削除) 構成
- 8 層 safety gate アーキテクチャ (L1-L8)
- HMAC ephemeral token (5 分有効) 設計
- Privacy Policy 文案 (報告データ取り扱い、24h 対応)
- Nutrition Label 設計 (User Content + Identifiers、Not Linked)
- D1 スキーマ (reports / rule_candidates / abuse_log / bans)
- 1.2 UGC 5 要素対応マトリクス

### 差分 (本体統合化に伴う変更)

- 4.3(b) Spam 対策不要 (別アプリ問題消滅)
- 既存 AdblockKeshi リポジトリ・bundle id・GitHub Pages CDN 流用
- 既存 monthly-filter-update.yml と新規 workflow の concurrency 制御
- 既存ユーザー向けアップグレード UX (WhatsNew + バナー誘導)
- TestFlight ではなくシミュレータ + 実機優先
- 2 extension UI 制約 (Safari 設定で 2 個並ぶ)

---

## 付録 B: 未確認事項 (実装段階で verify 必須)

- iOS Safari Content Blocker の **1 app あたり extension 数上限** (Apple 公式 docs 数値未明示)
  - 実機検証で確認、失敗時 fallback は base merge (5k 削減)
- Apple Price Tier 構造の最新形 (Tier 5 = ¥500 → ¥700 は Tier 7 想定だが提出時確認)
- Cloudflare D1 APAC region primary の latency 実測 (日本ユーザー想定)
- Turnstile 透明 challenge の SwiftUI 統合方法 (WebView 経由 vs Safari)

---

**(end of spec)**
