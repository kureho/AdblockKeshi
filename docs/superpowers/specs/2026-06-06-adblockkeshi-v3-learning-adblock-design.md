<!-- [paid-approved-by-kureho] spec doc 文書のみ、ASC API 呼び出しなし、課金影響なし -->
# 広告消し v3.0「学習する広告消し」設計 spec

**日付**: 2026-06-06 (rev2 2026-06-07: spec review #1 反映 / rev3 2026-06-07: spec review #2 反映 / rev4 2026-06-07: spec review #3 反映)
**status**: Draft (spec review #3 反映済、#4 で approval 期待)
**対象アプリ**: 広告消し (com.kureho.adblockkeshi、App ID 6774906945)
**現配信中**: v2.1.1 (READY_FOR_SALE、2026-06-04 配信開始、ASC API verify 済)
**提出予定**: v3.0.0 build 12
**関連 spec**:
- `~/claude/docs/superpowers/specs/2026-06-06-learning-adblock-design.md` (v0.3 Frozen) — 別アプリ案、副産物を本案で流用

---

## 0. 背景と意思決定

### kureho の moat 仮説 (GO 根拠)

- 報告で学習する広告ブロックを本体に統合 → **完全ゼロタッチで運用**
- 仮説: 運用コスト 0 円 × データ蓄積で 1 強形成
- 凍結 spec 判断「10-14 週 vs 機会費用」を「moat 投資の正当性」で上書き

### 凍結 spec との差分

| 観点 | 凍結 spec (別アプリ) | 本案 (本体統合) |
|---|---|---|
| 提出 | 新規 bundle id | 既存継続 |
| 4.3(b) Spam リスク | あり | **回避** |
| 価格 | ¥1,500 | ¥700 |
| 工数 | 10-14 週 | **12-16.5 週** (rev2: abuse 自動化 +1-2 週、 PII filter +0.5 週) |
| 既存ユーザー | 関係なし | 影響あり |

### 残課題 (advisor flag、kureho 認識済)

- **chicken-and-egg**: moat 形成に初動ユーザー ≥ 数千、現状レビュー 0 から橋渡しは ASO/PR 側
- **E 軸需要ゼロ**: 「学習する」を主軸にしない、B 軸主軸 + moat 実態形成

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

- **表 (ASO/store)**: B 軸主、H 軸修飾
- **中 (description)**: B 軸 + H 軸 + F' 軸 + 既存 v2.0 詐欺機能
- **裏 (moat 形成)**: 報告データ蓄積で品質差 (訴求しない、実態で勝つ)

### 禁止訴求

- E 軸「みんなで育てる」(需要ゼロ判定済)
- Apple 商標 (Safari/iPhone/iPad/iOS/Apple/Siri) は name/subtitle/promo/keywords NG (5.2.5)
- 価格表現 (¥/Free/無料/割引) は description のみ可 (2.3.7)

---

## 2. 報告タブ UX

### 全体構造

```
v2.x: 単一画面
v3.0: TabView 2 タブ
  ├ Tab A: ブロッカー (既存画面そのまま)
  └ Tab B: 報告 (新規)
```

### Tab B 画面遷移

```
[エントリ] CTA
  ↓
[入力フォーム]
  ・URL (必須): クリップボード自動検出 + 貼り付け
  ・メモ (任意、200字): 「動画上のオーバーレイ」等
  ↓ Turnstile + HMAC ephemeral token 取得
[送信完了] 「通常 7-14 日以内に反映を検討します」
  ↓
[報告履歴] v3.0 で実装
  ・ステータス: pending / validating / approved / rejected_no_ad_detected / rejected_safety_gate
  ・取得: POST /v1/reports/history + HMAC token (IDOR 防止)
  ・memo 表示: D1 保存値 (PII redact 済) を返す。redact 発火項目には「個人情報を含む可能性があるため一部を伏せて保存しました」の注記バッジを表示 (rev4: UI 透明性確保)
```

### 含めないもの (YAGNI)

- スクショ送信 (Playwright 検出で代替)
- カテゴリ選択、重要度スライダー

### 入力 validation (端末 + サーバ 2 段)

| 項目 | 端末側 | サーバ側 |
|---|---|---|
| URL | `https://` 必須、200 字以内 | + URL 構文検証 + Tranco Top 1M 即時拒否 |
| メモ | 200 字以内、URL 含むと拒否 | + **PII regex redact** (rev3 改訂、後述) |
| Turnstile | 透明 challenge | サーバ検証 |
| rate limit | 端末側 UI で抑止 | サーバ側 D1 で hard enforce |

### 🆕 memo PII filter (rev3 全面改訂: redact 方式)

**rev2 の reject 方式は廃止** (「0120-XXX-XXXX」「03-XXXX-XXXX」等が正当な広告報告 context で誤 reject される実害大、reviewer 指摘)。

rev3 方式: **サーバ側で mask/redact してから保存**、ユーザーには成功 response 返す。

| 検出パターン | regex 例 | 受信時挙動 |
|---|---|---|
| 電話番号 (日本) | `0\d{1,4}-?\d{1,4}-?\d{4}` | `***-****-****` に置換、memo 自体は保存 |
| 電話番号 (国際) | `\+\d{1,3}[\s-]?\d+` | `+**-***-****` に置換 |
| メールアドレス | `[\w._%+-]+@[\w.-]+\.\w+` | `***@***.***` に置換 |
| クレジットカード番号 | `\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}` (Luhn 検証で精度上げ) | `****-****-****-****` に置換 |
| ~~マイナンバー (12 桁)~~ | ~~`\d{12}`~~ | **削除** (誤検出率高すぎ、タイムスタンプ・URL ID と区別不能) |

- 検出時は **redact 済 memo で D1 INSERT**、`abuse_log` に `reason='pii_redacted'` で記録 (informational)
- **ban 加算には使わない** (誤検出の善意ユーザーを誤 ban 防止)
- ユーザーには HTTP 200 + 「報告を受け付けました」を返す (silent redact)
- ★ rev3 設計思想: 「PII を含む正当な広告報告は阻害せず、保存時に匿名化のみする」

### Privacy

| データ | 端末→サーバ送信 | 保存期間 |
|---|---|---|
| 報告 URL | ✅ | 14 日 (匿名化後 90 日継続) |
| メモ (PII filter 通過後) | ✅ | 同上 |
| 端末 UUID | ❌ (Keychain のみ)、`SHA-256(uuid+server_salt)` のみ送信 | 90 日 |
| IP | Workers 受信時、即ハッシュ化 | 14 日 |
| 閲覧履歴 | ❌ (技術的に取得不可) | - |

---

## 3. 報告受信 infra (Cloudflare 0 円構成)

### スタック

| サービス | 用途 | 無料枠 | 想定使用率 (10k ユーザー × 月 5 報告) |
|---|---|---|---|
| Cloudflare Workers | API endpoint | 100k req/day | 1.7% (1667/日) |
| Cloudflare D1 (APAC primary) | SQLite DB | 5GB / 5M reads / 100k writes per day | 1% |
| Cloudflare Turnstile | bot 防止 | 無制限、商用 OK | - |
| GitHub Actions (Linux runner) | 月次/週次/日次/時次タスク | public repo 無制限 | timeout 厳守 |

### Endpoint (rev2: IDOR 対策で POST 化)

| Method | Path | 認証 | 用途 |
|---|---|---|---|
| POST | `/v1/reports/token` | Turnstile | ephemeral HMAC token (5分有効、payload: `{subject: uuid_hash, expires, scope: "submit|history|delete"}`、rev3 明示) |
| POST | `/v1/reports/submit` | token | 報告本体 (URL + memo) |
| POST | `/v1/reports/history` | token | **🆕 自分の履歴取得 (rev2: GET から POST + token に変更)** |
| POST | `/v1/reports/delete` | token | **🆕 自分のデータ削除依頼 (rev2: 24h 内自動削除)** |
| GET | `/v1/health` | none | health check |

履歴取得 IDOR 防止: `POST /v1/reports/history` body に `{uuid_hash, hmac_token}` を含め、Workers が token 検証後 `uuid_hash` を D1 SELECT key にする。GET でクエリパラメータ漏洩を避ける。

### D1 スキーマ (rev2: 全列確定)

```sql
-- reports: 個別報告
CREATE TABLE reports (
  id TEXT PRIMARY KEY,                          -- UUID v4
  uuid_hash TEXT NOT NULL,                      -- SHA-256(端末UUID + server_salt)
  ip_hash TEXT NOT NULL,                        -- SHA-256(IP + server_salt)
  domain TEXT NOT NULL,                         -- example.com
  url TEXT NOT NULL,                            -- 完全 URL
  url_path_hash TEXT NOT NULL,                  -- SHA-256(URL) 重複検出
  memo TEXT,                                    -- 200字以内、PII filter 通過後
  status TEXT NOT NULL DEFAULT 'pending',       -- pending/validating/approved/rejected_*
  created_at INTEGER NOT NULL,                  -- Unix sec
  validated_at INTEGER,
  beta_started_at INTEGER,                      -- L7 β tier 開始
  applied_at INTEGER,                           -- stable 昇格
  detected_selector TEXT,                       -- Playwright 検出結果
  rejection_reason TEXT                         -- reject 理由 (status='rejected_*' 時)
);
CREATE INDEX idx_reports_status_created ON reports(status, created_at);
CREATE INDEX idx_reports_uuid_hash ON reports(uuid_hash, created_at DESC);
CREATE INDEX idx_reports_domain_url_path ON reports(domain, url_path_hash);
CREATE INDEX idx_reports_beta_started ON reports(beta_started_at) WHERE status='beta';

-- rule_candidates: 集計済みルール候補
CREATE TABLE rule_candidates (
  id TEXT PRIMARY KEY,
  domain TEXT NOT NULL,
  selector TEXT,                                -- CSS selector or NULL
  rule_text TEXT NOT NULL,                      -- Content Blocker JSON 形式
  unique_uuid_count INTEGER NOT NULL,
  unique_ip_count INTEGER NOT NULL,
  first_reported_at INTEGER NOT NULL,
  last_reported_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'aggregating',   -- aggregating/validating/beta/stable/rejected/rejected_rollback
  beta_started_at INTEGER,
  stable_started_at INTEGER,
  complaint_count INTEGER NOT NULL DEFAULT 0,
  cooldown_until INTEGER,                       -- rollback 後 30 日
  validation_score REAL,                        -- L6 Playwright スコア (0-1)
  l3_check TEXT,                                -- pass/fail (Tranco)
  l4_check TEXT,                                -- pass/fail (selector scope)
  l5_check TEXT                                 -- pass/fail (CDN protection)
);
CREATE INDEX idx_rc_status ON rule_candidates(status);
CREATE INDEX idx_rc_cooldown ON rule_candidates(cooldown_until);

-- abuse_log: 不正報告記録
CREATE TABLE abuse_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  identifier_hash TEXT NOT NULL,                -- uuid_hash or ip_hash
  identifier_type TEXT NOT NULL,                -- 'uuid' or 'ip'
  reason TEXT NOT NULL,                         -- 'rate_limit'/'invalid_url'/'spam_memo'/'pii_detected'/'critical_domain'
  url TEXT,                                     -- 該当 URL (検証用)
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_abuse_identifier ON abuse_log(identifier_hash, created_at);

-- bans: 自動 ban (rev2: 自動判定強化)
CREATE TABLE bans (
  identifier_hash TEXT PRIMARY KEY,
  identifier_type TEXT NOT NULL,                -- 'uuid' or 'ip'
  reason TEXT NOT NULL,
  abuse_count INTEGER NOT NULL DEFAULT 0,
  ban_level INTEGER NOT NULL DEFAULT 1,         -- 1=24h/2=7d/3=30d/4=permanent
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  notes TEXT                                    -- 自動判定根拠
);
CREATE INDEX idx_bans_expires ON bans(expires_at);

-- 🆕 deletion_requests: ユーザーからのデータ削除依頼 (rev2 追加、24h 自動処理)
CREATE TABLE deletion_requests (
  id TEXT PRIMARY KEY,
  uuid_hash TEXT NOT NULL,
  url_path_hash TEXT,                           -- 特定 URL の削除指定 (任意)
  requested_at INTEGER NOT NULL,
  processed_at INTEGER,
  status TEXT NOT NULL DEFAULT 'pending'        -- pending/completed
);
```

### Secrets (Wrangler secrets、絶対 commit 禁止)

| Secret | 用途 |
|---|---|
| `HMAC_KEY` | ephemeral token 署名 |
| `SERVER_SALT` | UUID/IP hash の reversibility 防止 |
| `TURNSTILE_SECRET` | Turnstile 検証 |
| `GH_DISPATCH_TOKEN` | 月次/週次 workflow trigger |

### Rate limit (rev2: hard cap 緩和)

| Scope | Limit |
|---|---|
| per uuid_hash | 5/日、30/月 |
| per ip_hash | 5/15min、30/月 |
| per domain (全集計) | 1000/日 (DDoS 対策) |
| **全体 instance hard cap** | **80,000/日** (Workers free 80%、rev2: 10k→80k 緩和) |
| **tripwire** | **70,000/日 で warn (log + 通知)、95,000 で 503** (rev2 追加) |

### 🚨 課金暴走防止 (memory `feedback_no_silent_paid_infra` 遵守)

- Cloudflare Workers Paid プラン無効化維持
- 無料枠超過時 = 自動 503 (有料化しない)
- 全体 hard cap 80,000 req/日を Workers コードで enforce、超えたら 429
- tripwire 70,000 で kureho に notification (Apps Metrics Dashboard 経由)

---

## 4. 自動承認パイプライン (8 層 safety gate + 2 extension)

### 8 層 safety gate (rev2: L2/L8 閾値の race 解消)

| 層 | 目的 | 実装場所 | 閾値 |
|---|---|---|---|
| L1 | Turnstile + rate limit + **PII filter (rev2)** | Workers | (Section 2 §PII + Section 3 §Rate limit 参照) |
| L2 | threshold 集計 (承認方向) | Actions (hourly) | **3 unique uuid_hash + 2 unique ip_hash + 14 日 sliding window** |
| L3 | Tranco Top 1M + critical list | Actions (daily) | Top 1M = 自動 reject + queue 隔離、critical 50 domain は queue にも入れず即破棄 |
| L4 | selector scope 制限 | Actions (daily) | URL 単位 no-rule、`body/html/*` 等の wide scope reject |
| L5 | 共通 CDN 保護 | Actions (daily) | Akamai/Cloudfront/Google APIs 等 30 件 list 照合 |
| L6 | Playwright validation | Actions (daily, Linux, 30 分) | DOM 走査 → 広告判定スコア ≥ 0.7 で pass |
| L7 | β tier 7 日待機 | Actions (weekly) | beta_started_at + 7 日 + **L8 苦情なし** → stable 昇格 |
| **L8 (rev2 段階閾値)** | 苦情 auto-rollback | Workers + Actions | **β tier 中: 2 unique uuid_hash で即 rollback (厳しめ) / stable 後: 3 unique uuid_hash で rollback** |

★ rev2: L2 = 3 票で承認、L8 = β 中 2 票で reject = race 解消 (β 中は reject 寄り、stable 化後は対称)

### 2 Content Blocker extension 構成

iOS Safari Content Blocker の単一 extension 上限 (公式未明示、実装的に 150k 動作) を超えるため、**2 extension 構成**で base 削減回避:

| extension | bundle id | display name | bundle 内容 | ルール上限 |
|---|---|---|---|---|
| ContentBlockerExtension | `com.kureho.adblockkeshi.blocker` | 広告消し 本体 | rules-base.json (15万) | 既存上限内 |
| ReportedRulesExtension (新規) | `com.kureho.adblockkeshi.reportedblocker` | 広告消し 学習 | rules-reported.json (報告由来、最大 5万) | 別 extension で確保 |

### 🆕 Extension 上限 fallback 階層 (rev2: 強化)

実装段階で 2 extension が動かない場合の fallback を **4 段階**で spec:

| Path | 構成 | base への影響 | 報告ルール上限 | 採用条件 |
|---|---|---|---|---|
| **Path 1 (主)** | 2 extension (本体 15万 + 学習 5万) | ゼロ | 5万 | 実機検証で 2 extension 動作確認 |
| Path 2 (fallback A) | 単一 extension で `ad-rules.json` 内に reported merge | base 5k 削減 | 5k 程度 | Path 1 失敗、reported < 5k 想定なら許容 |
| Path 3 (fallback B、🆕) | base を **130k に圧縮** (EasyList syntax 最適化 + 重複除去 + 低頻度ルール削除)、reported 20k 確保 | 削減なし (圧縮効果) | 2万 | Path 1 失敗、reported 5k〜20k 想定 |
| Path 4 (最悪、🆕) | reported を **Top N FIFO/LRU で 5k 上限維持** | ゼロ | 5k (循環) | Path 1-3 全失敗 |

実装初週で実機 PoC、結果に応じて Path 確定。Path 3-4 は 5k 超え時の長期対応案。

### 2 extension UX

- iOS Settings → Safari → 機能拡張で **2 個並ぶ**、ユーザーは両方 ON
- 既存ユーザー: WhatsNew + 継続バナーで「学習」ON 誘導、強制せず
- 状態検出: `SFContentBlockerManager.getStateOfContentBlocker(withIdentifier:)` 並行 fetch
- 4 パターン UX: 両方 ON (通常) / base のみ (黄バナー) / 学習のみ (赤バナー) / 両方 OFF (onboarding 戻し)
- 報告タブは状態と連動: 学習 OFF 時に警告表示
- 完了画面に moat 可視化「フィルタ最終更新 / 本体 150,000 / 報告で追加 N 件 (先月 +M 件)」

### 🆕 kureho ゼロタッチの境界線 (rev2 明確化)

| 動作 | 自動 | kureho 人手 |
|---|---|---|
| ルール採用判断 (L1-L8) | ✅ 自動 | ❌ |
| abuse 判定 (rate limit, ban, PII detect) | ✅ 自動 | ❌ |
| **データ削除依頼処理 (1.2 UGC 24h コミット)** | ✅ **自動 (rev2 新規)** | ❌ |
| **abuse_log 集計と自動 ban level up** | ✅ **自動 (rev2 新規)** | ❌ |
| Tranco Top 1M queue 隔離後の対応 | ❌ (queue は moat 形成期 empty 想定、放置可) | 例外時のみ手動 |
| Resolution Center reply (Apple 審査関連) | ❌ (Apple との直接対話、自動化不可) | ✅ 24h 以内に kureho |

### 🆕 abuse 自動判定ロジック (rev2 追加、kureho 判断反映)

完全ゼロタッチを貫くため、abuse 対応も Workers で自動化:

#### Workers 内 abuse 判定 (報告送信時)

```
1. PII filter (Section 2 §PII)
2. rate limit hit → abuse_log INSERT (reason='rate_limit')
3. URL が critical list / Tranco Top 1M → abuse_log INSERT (reason='critical_domain')
4. memo に spam pattern (重複 URL, 既知 spam keyword) → abuse_log INSERT (reason='spam_memo')
```

#### GitHub Actions (`hourly-aggregation.yml`) 内 ban level 自動 up (rev3: 種別重み付け)

```
過去 24h で abuse_log を「ban 加算対象 reason」のみ集計:
  ban 加算対象: rate_limit / invalid_url / spam_memo / critical_domain (重み 0)
  ban 加算非対象 (informational のみ): pii_redacted
  
加算 abuse_count:
  ≥ 3   → ban level 1 (24h)
  ≥ 10  → ban level 2 (7d)
  ≥ 30  → ban level 3 (30d)
  ≥ 100 → ban level 4 (permanent)

bans table を upsert、expires_at 更新
```

★ rev3: 善意ユーザーの PII redact 発火を ban 加算から除外。閾値 3/10/30/100 は **初期値、配信後 abuse_log 実データで調整** (付録 B 参照)。

#### deletion_requests 自動処理 (`hourly-deletion-processor.yml`、🆕 workflow 追加)

```
1 時間ごと:
  status='pending' の deletion_requests を取得
  対応する reports / rule_candidates の uuid_hash 一致行を DELETE
  status='completed' + processed_at = now()
  
SLA: 受信から最大 1 時間以内に削除完了 (24h コミットに余裕で間に合う)
```

これで 1.2 UGC (c) 「abuse block」 + (e) 「timely response」を **100% 自動化**。Resolution Center を除き kureho 介入ゼロ。

---

## 5. ルール反映フロー & 既存 workflow 統合

### Workflow 構成 (rev2: 1 個追加で計 8 個)

| Workflow | 種別 | トリガー | timeout | 役割 |
|---|---|---|---|---|
| `monthly-filter-update.yml` | 既存 | 月次 + dispatch | 30 分 | rules-base.json 生成 → bundle 同期 → CDN push |
| `hourly-aggregation.yml` | 新規 | hourly | 5 分 | L2 集計 + abuse ban 自動 level up |
| `daily-validation.yml` | 新規 | daily 03:00 UTC | 30 分 | L3-L6 validation |
| `weekly-stable-promotion.yml` | 新規 | weekly 月 04:00 UTC | 10 分 | L7 β tier → stable 昇格 (L8 苦情なし条件) |
| `weekly-cdn-sync.yml` | 新規 | weekly 火 05:00 UTC | 20 分 | rules-reported.json 生成 → bundle 同期 → CDN push |
| `weekly-tranco-sync.yml` | 新規 (rev3: 月次→週次) | weekly 日 02:00 UTC | 30 分 | Tranco Top 1M sync (週次で鮮度確保) |
| `complaint-monitor.yml` | 新規 | hourly | 5 分 | L8 苦情監視 → rollback trigger |
| **`hourly-deletion-processor.yml`** | **新規 (rev2)** | hourly | 5 分 | データ削除依頼自動処理 (1.2 UGC 24h コミット) |

🚨 全 workflow に `timeout-minutes` 必須、Linux runner のみ ($113 損失再発防止)。

### concurrency 制御 (rev3: トリガ時刻分散で queue 競合回避)

```yaml
# rules-base / rules-reported の CDN push 排他
concurrency:
  group: cdn-sync
  cancel-in-progress: false
# monthly-filter-update.yml と weekly-cdn-sync.yml が共有
```

```yaml
# D1 write 排他 (hourly-aggregation / complaint-monitor / hourly-deletion-processor)
concurrency:
  group: d1-write
  cancel-in-progress: false
```

```yaml
# D1 read-heavy (daily-validation / weekly-tranco-sync)
concurrency:
  group: d1-read-heavy
  cancel-in-progress: false
```

### 🆕 hourly workflow トリガ時刻分散 (rev3 追加)

3 つの d1-write hourly workflow が同 `:00` トリガで queue 順非決定になる問題を回避:

| Workflow | trigger 時刻 |
|---|---|
| `hourly-aggregation.yml` | `0 * * * *` (毎時 :00) |
| `complaint-monitor.yml` | `15 * * * *` (毎時 :15) |
| `hourly-deletion-processor.yml` | `30 * * * *` (毎時 :30) |

各 5 分 timeout、間に 10 分の buffer。直列化されても 1 時間内に必ず完走する保証。

- L2 (承認方向、hourly-aggregation) と L8 (rollback 方向、complaint-monitor) は同 `d1-write` group で **必ず直列実行** → race 解消
- tranco-sync は読み主体だが daily-validation と D1 同時読みすると性能影響、別 group で直列化

### CDN 構造

```
docs/cdn/
  rules-base.json       monthly-filter-update が更新 → ContentBlockerExtension
  rules-reported.json   weekly-cdn-sync が更新 → ReportedRulesExtension
  version.json          generated_at + base.rule_count + reported.rule_count + added_last_month
  feature-flags.json    🆕 RemoteConfigStore 用 (Section 6 §feature flag 参照)
```

### bundle 同梱 + CDN fallback

| ファイル | bundle 同梱先 | CDN fallback |
|---|---|---|
| ad-rules.json | Extension/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/rules-base.json |
| reported-rules.json (新規、初期空) | ReportedRulesExtension/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/rules-reported.json |
| version.json | App/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/version.json |
| feature-flags.json (新規、初期 all-true) | App/Resources/ | https://kureho.github.io/AdblockKeshi/cdn/feature-flags.json |

### 🆕 反映タイムライン詳細 (rev2: 内訳明示)

| 段階 | 待ち時間 | 累積 | 詳細 |
|---|---|---|---|
| 報告送信 → D1 INSERT | 即時 | 0h | Workers 直接 |
| L2 hourly-aggregation 集計 | +最大 1h | 1h | hourly cron |
| L3-L6 daily-validation | +最大 24h | 25h | daily 03:00 UTC |
| β tier 開始 (validation 通過時) | 即時 | 25h | validation 完了直後 |
| L7 β tier 7 日待機 | **+7d** | 25h + 168h = 193h | beta_started_at + 7 日経過確認 |
| L8 苦情なし確認 (weekly-stable-promotion) | 即時 (上記と同 workflow) | 193h | β 7 日経過後の weekly cron で stable 昇格 |
| weekly-cdn-sync で rules-reported.json 生成 | **+最大 7d (火曜まで)** | 193h + 168h = 361h | weekly 火 05:00 UTC |
| 端末 BGTaskScheduler DL | +最大 24h | 361h + 24h = **385h ≒ 16 日** | bg fetch task |

★ **最悪 16 日 (約 385 時間)**、最短約 8 日。**端末 BGTaskScheduler は実機状態で数日遅延あり** (rev3: 楽観値修正) → 報告タブの告知は **「通常 7-14 日以内、最悪 30 日」** に正直化。将来 v3.1 で短縮検討。

---

## 6. Apple 審査対策

### 適用 Guideline と reject リスク

| Guideline | 該当性 | リスク |
|---|---|---|
| 1.2 (Safety - UGC) | ✅ | yellow (rev3 再評価: 「完全自動 = 無人 moderation」は Apple が暗黙に嫌う可能性、トーンダウン推奨) |
| 5.2.5 (Intellectual Property) | ⚠️ 直前事故 | 要厳格対応 |
| 2.3.7 (Pricing metadata) | ⚠️ 4 回違反済 | 要厳格対応 |
| 5.1.1 / 5.1.2 (Privacy) | ✅ | medium |
| 4.3(b) (Spam) | ✅ 本体統合で **回避** | green |

### 1.2 UGC 5 要素対応 (rev2: 全自動化)

| 要素 | 公式要件 | 実装 | 自動化レベル |
|---|---|---|---|
| (a) フィルタリング | objectionable material filtering | URL validation + Tranco + critical list + selector scope + **memo PII regex filter (rev2)** | 100% 自動 |
| (b) 報告手段 | report mechanism | 報告タブ footer mailto: info@kureho.app + 「不適切な報告」link | 自動 (受付) |
| (c) abuse ブロック | block abusive users | uuid_hash + ip_hash rate limit + **4 段階 ban (24h/7d/30d/permanent) 自動 level up** | **100% 自動 (rev2)** |
| (d) 連絡先 | published contact | info@kureho.app + https://kureho.app/contact?product=adblockkeshi | 静的 |
| (e) 対応時間 | timely response | **データ削除依頼 = hourly-deletion-processor で 1 時間以内自動処理 (24h SLA 余裕クリア)**、Resolution Center reply のみ kureho 24h | **削除は 100% 自動 (rev2)** |

### Review Notes (英語、提出時、rev3: Apple 1.2 トーンダウン)

```
=== App Review Notes (v3.0 build 12) ===

NEW FEATURE in v3.0: Report Tab (Tab B)
Users can submit URLs where ads were not blocked. These submissions are NOT 
user-to-user content sharing — they are inputs for our automated backend
filter rule generation pipeline, with developer escalation path via the
Resolution Center for any issues that automation cannot handle.

GUIDELINE 1.2 COMPLIANCE (all 5 elements addressed):
(a) Filtering: URL validated against Tranco Top 1M whitelist + 50-domain critical
    blocklist (apple.com, google.com etc.) + memo PII redaction at ingress
    (phone/email/credit card patterns auto-masked) + CSS selector scope
    restriction (no full-page blocking).
(b) Reporting: In-app "Report inappropriate submissions" mailto: link in Tab B
    footer → info@kureho.app. Developer monitors and responds within 24 hours.
(c) Abuse blocking: Per-device UUID-hash + IP-hash rate limiting + 4-tier
    automatic ban escalation (24h/7d/30d/permanent) based on weighted abuse_log
    aggregation. Developer can manually override bans via support email.
(d) Contact: info@kureho.app + https://kureho.app/contact?product=adblockkeshi
    published in Privacy Policy and App Store listing. Corporate phone in
    Review Information (corporate info only, per Apple policy).
(e) Response time: User data deletion requests processed automatically within
    1 hour by hourly-deletion-processor workflow (within the 24h commitment in
    Privacy Policy). Developer responds to all other reports within 24 hours
    via email or Resolution Center.

AUTOMATIC RULE APPLICATION SAFETY (8-layer pipeline):
L1 Turnstile + rate limit + PII filter
L2 Threshold aggregation (3 unique UUIDs + 2 unique IPs in 14-day window)
L3 Tranco Top 1M + critical domain protection
L4 Selector scope restriction
L5 Common CDN protection (Akamai, Cloudfront, Google APIs etc.)
L6 Playwright auto-validation (ad-presence score ≥ 0.7)
L7 7-day beta tier observation
L8 Complaint auto-rollback (β: 2 votes / stable: 3 votes, 30-day cooldown)

EXTENSIONS:
This app bundles TWO Content Blocker extensions:
- "広告消し 本体" (com.kureho.adblockkeshi.blocker): existing 150k base ruleset
- "広告消し 学習" (com.kureho.adblockkeshi.reportedblocker): up to 50k report-derived rules
Users must enable BOTH in Settings → Safari → Extensions for full functionality.

PRIVACY:
- Device UUID stored only in Keychain (App Group), never sent.
- SHA-256(UUID + server_salt) sent for duplicate detection.
- IP hashed at Workers ingress, retained 14 days for rate limit, then deleted.
- Browsing history technically inaccessible (iOS Content Blocker sandbox).
- Backend: Cloudflare Workers + D1 + Turnstile (APAC region).
- User-initiated data deletion endpoint with 1-hour SLA.

FEATURE FLAG (server-side toggleable):
The Report Tab can be disabled via CDN-hosted feature-flags.json without app
re-submission. URL: https://kureho.github.io/AdblockKeshi/cdn/feature-flags.json

DEMO STEPS:
1. Launch the app
2. Settings → Safari → Extensions → enable both "広告消し 本体" and "広告消し 学習"
3. Tab B → enter https://example.com → tap Send → "Sent" confirmation
4. Tab B → Show history → status shows "検証中"

CONTACT:
Demo account: not required (no login)
Reviewer questions: info@kureho.app, +81 75 313 3700
```

### 5.2.5 / 2.3.7 対策

- Apple 商標 (Safari/iPhone/iPad/iOS/Apple/Siri/iMessage) は name/subtitle/promo/keywords/screenshots に **絶対含めない**
- 価格表記 (¥/Free/無料/割引) は description のみ可、その他 NG
- 提出前 metadata grep を CI hook に組み込み (PR 時自動 fail)

### keywords 新案

```
広告,消す,ブロック,うざい,詐欺,フィッシング,セキュリティ,学習,報告,進化
```

### promotional_text 新案

```
他のブロックアプリで消えない広告を、報告で進化するフィルタが対応。
報告タブから URL を送ると、自動検証を経て広告ブロックリストへ追加。
買い切り、サブスクなし、閲覧履歴も送信しません。
```

### Privacy Policy 追記 (kureho.app/apps/adblock-keshi/privacy)

新規セクション:
- 報告データの取り扱い (収集項目 / 利用目的 / 保持期間 / 第三者提供なし)
- **データ削除依頼: 24 時間以内に自動処理** (実態は 1 時間以内、SLA は 24 時間)
- 削除依頼窓口 (info@kureho.app または in-app `/v1/reports/delete`)
- abuse 対応: 自動 ban システム (4 段階)
- 保管インフラ (Cloudflare Workers/D1 APAC)

### Nutrition Label (rev3: 安全側で Linked 判定)

| Data Type | Linked? | Tracking? | Purpose |
|---|---|---|---|
| **User Content** > Other User Content (報告 URL/メモ) | ✅ **Linked (rev3: 安全側)** | ❌ | App Functionality |
| **Identifiers** > Device ID (UUID hash) | ✅ **Linked (rev3)** | ❌ | App Functionality |
| **Identifiers** > Device ID (IP hash) | ✅ **Linked (rev3)** | ❌ | App Functionality (rate limit) |

★ rev3: `uuid_hash + ip_hash` 複合キーで同一ユーザー追跡が可能なスキーマのため、Apple "Not Linked" の判定 (個別ユーザーへ traceback できない) を厳密に解釈すると **Linked** が安全。Tracking なし + Purpose を App Functionality 限定で「データ収集はあるが個人特定不可、解析用ではない」を明示。Privacy Policy にも同様の正直な記述を追記する。

### 🆕 RemoteConfigStore 仕様 (rev2 追加)

feature flag による段階退避を機能させるため、`RemoteConfigStore` の boundaries を spec で fix:

```swift
final class RemoteConfigStore {
    static let shared = RemoteConfigStore()
    
    private let url = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/feature-flags.json")!
    private let cacheKey = "remote_config_cache"
    private let cacheTTL: TimeInterval = 3600 // 60 分
    
    func fetchAndUpdate() async {
        // 起動時 + 60 分ごとに UserDefaults に永続キャッシュ
    }
    
    func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        // 1. UserDefaults キャッシュを読む
        // 2. キャッシュ TTL 切れなら fetchAndUpdate (async、戻り値には影響せず)
        // 3. キャッシュなしの初回 = default を返す (network 失敗時 fail-open)
        // 4. キャッシュあり = キャッシュ値を返す
    }
}
```

| 観点 | 仕様 |
|---|---|
| fetch interval | 起動時 + 60 分ごと |
| cache TTL | 60 分 |
| 永続キャッシュ | UserDefaults (App Group) |
| network 失敗時 (初回、通常 flag) | `default=true` (機能 ON 維持、fail-open) |
| **emergency_kill_switch (rev3 追加、Apple 緊急 OFF 用)** | **fail-CLOSED**: 初回 network 失敗時 = `true` 扱い (機能 OFF)、CDN reachable で `false` を確認するまで報告タブ非表示 |
| network 失敗時 (2 回目以降) | 直近成功値を使用 (永続キャッシュ) |
| feature-flags.json 構造 (rev3 拡張) | `{ "report_tab_enabled": true, "emergency_kill_switch": false, "version": "v2" }` |
| **🆕 evaluation order (rev4)** | **`emergency_kill_switch=true` は無条件で Tab B 非表示** (`report_tab_enabled` の値に関わらず優先)。初回 no-network 時は `emergency_kill_switch=true 扱い` を最終的に優先し Tab B 非表示。すなわち kill_switch > report_tab_enabled |

★ kureho が CDN で `report_tab_enabled=false` に編集 → 端末次回起動 (or 60 分以内) で OFF 反映。新 build 提出不要。Apple へは「server-side toggleable」を review notes に明示済。

### リスク × 対応マトリクス

各リスクに予防/検知/対応/escalation を設計済 (4 リスク × 4 段階)。共通原則:
- 24h ルール (reject 通知 → 24h 以内 Resolution Center reply)
- reply 先行 (cancel 前に reply 必須、memory `feedback_resolution_center_reply_before_cancel`)
- Apps Metrics Dashboard 連携 (hourly monitor)
- 段階退避 (feature flag で報告タブ OFF 可、v3.0 build に事前組み込み)

---

## 7. 価格戦略 & version ロードマップ

### 価格

| Version | 価格 | 思想 |
|---|---|---|
| v2.1.x → v3.0 | ¥500 → **¥700** | 機能拡張に伴う適正価格化。値上げ自体は目的ではない |
| v3.1 / v3.2 | **¥700 維持を default** | 次の値上げは v4.0 メジャー拡張時のみ検討 |

### 🆕 retreat 戦略 (rev2: Price Tier vs description 経路分離)

v3.0 リリース 4 週後 KPI 評価:
- 月次 DL が v2.1.x 比 50% 未満 → ¥600 retreat 検討
- 「高すぎる」苦情 > 30% → 同上

**retreat 経路の現実 (rev2 修正)**:
- **Price Tier 変更 (¥700→¥600)**: ASC Price Schedule 編集で **24h 反映、binary/metadata 提出不要**
- **description の「¥700」記述変更**: ASC AppStoreVersion 作成 + metadata-only review 必要 (最短 1-3 日審査)
- → retreat 実行時は **Price Tier 変更を即座に + description は次回 binary update 時にまとめて修正** が現実解

### metadata 価格表記の場所縛り (memory `feedback_pricing_metadata_strict` 厳守)

- description のみ「¥700」「値上げ」「買い切り」可
- subtitle / promotional_text / keywords / screenshots に **¥/Free/無料/割引** NG
- 「買い切り」「サブスクなし」のみ subtitle/promo/keywords でも OK

### 🆕 description の価格表記方針 (rev3)

retreat 時の手間 (binary submit 必要) を排除するため、**description にも価格数字「¥700」を書かない**方針を推奨:

- 値上げ説明文面は「**買い切り価格を改定しました**」のみ (具体的金額を書かない)
- 価格は App Store の Price 表示でユーザーが確認、本文では言及しない
- これで Price Tier 変更だけで retreat 完結、description 修正の binary submit 不要

### version ロードマップ

| Version | 主要変更 | 価格 |
|---|---|---|
| v3.0.0 | 報告タブ + 2 extension + 8 層 safety gate + feature flag + **abuse 自動化** + **PII filter** + ¥700 値上げ | ¥700 |
| v3.0.1 | reject 時 hotfix (metadata or feature flag OFF) | ¥700 |
| v3.1.0 | 履歴 UI 改善、月次 stats UI、運用安定化、反映タイムライン短縮検討 | ¥700 維持 |
| v3.2.0 | 自動クロール (Tranco 全件 ML 検出) moat 強化 | 検討 |
| v4.0.0 | マルチブラウザ対応? | 未定 |

### 🆕 Phase 別 DoD (Definition of Done) (rev2 追加)

| Phase | DoD |
|---|---|
| Phase 1-2: Infra | Cloudflare Workers `health` endpoint で 200 OK、D1 全テーブル作成、Turnstile site key 発行、project.yml に 2 extension target 追加、xcodegen ビルド成功、**🆕 rev3: 2 extension がシミュレータで両方 ON 状態で実動作する screencast 必須提出** (extension 数上限 verify) |
| Phase 3-4: safety gate | 8 層各層の unit test pass (L1-L8 別々の test、Workers Vitest)、Actions 8 workflow が workflow_dispatch で手動成功実行 |
| Phase 5: UI 仕上げ | UI test 全 4 パターン (両 ON/base ON/学習 ON/両 OFF) pass、履歴 UI スナップショットテスト pass、feature flag による Tab B 非表示確認 |
| Phase 6: 検証 | シミュレータで 5 シナリオ pass (新規 onboarding / v2→v3 アップグレード / 報告送信 / 履歴確認 / feature flag OFF)、実機で同 5 シナリオ pass、Privacy Policy public 確認、4 点監査 ALL PASS |
| Phase 7: 提出 | reviewSubmission 投入、4 点監査再実行、Phased Release ON 確認 |

### 開発スケジュール (rev2: 工数増)

| Phase | 期間 | 主作業 |
|---|---|---|
| 1: Infra setup | Week 1-2 | Cloudflare Workers + D1 + Turnstile、project.yml 2 extension、実機 PoC (extension 上限確認) |
| 2: 報告タブ UI + API | Week 3-4 | SwiftUI Tab B、Workers handler、**PII filter (rev2)** |
| 3: 8 層 safety gate | Week 5-7 | L1-L8 各層、Tranco sync、Playwright validation |
| 4: workflow 統合 | Week 8-9 | Actions 8 個追加 (deletion-processor 含む、rev2)、CDN sync、concurrency |
| **5: abuse 自動化 + UI 仕上げ + Privacy** | **Week 10-12 (rev2 +1週)** | 履歴 UI、moat 可視化、feature flag、Privacy Policy、Nutrition Label、**abuse ban 自動 level up (rev2)** |
| 6: 検証 + 提出準備 | Week 13-14 | シミュレータ + 実機テスト、4 点監査、metadata 準備 |
| 7: 提出 + Apple 審査 | Week 15 | 提出、Resolution Center 監視 |
| 8: 配信後監視 | Week 16-23 | v3.1 開発並行、moat 観測 |

合計: **12-16.5 週** (元 10.5-14.5 週 + abuse 自動化 +1-2 週 + PII filter +0.5 週)

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
  └── feature/v3.0-learning-adblock (長期 12-16.5 週)
        ├── feat/cloudflare-infra
        ├── feat/report-tab-ui
        ├── feat/pii-filter (rev2)
        ├── feat/safety-gate-l1-l4
        ├── feat/safety-gate-l5-l8
        ├── feat/abuse-automation (rev2)
        ├── feat/github-actions-workflows
        ├── feat/deletion-processor (rev2)
        ├── feat/remote-config-store (rev2)
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
| 🆕 値上げ告知 (rev3) | WhatsNew に「**既にご購入のお客様は v3.0 を追加料金なしで受け取れます**」を強調表示、レビュー★低下リスク軽減 |

### TestFlight 検証

- 開発中はシミュレータ + 実機優先 (memory `feedback_simulator_first_verification`)
- TestFlight は提出直前の最終回帰のみ (internal tester、external invite なし)

### 🆕 rollback 経路 (rev2: 誤記訂正)

| シナリオ | rollback 経路 |
|---|---|
| Apple reject 1.2 UGC | feature flag `report_tab_enabled=false` を CDN push → 端末次回起動で報告タブ非表示 → metadata-only 再提出 |
| 苦情 rollback 大量発生 | weekly-cdn-sync 停止、reported-rules.json 空配列上書き → 端末次回 DL で報告由来ルール全削除 |
| API endpoint 障害 (Workers down) | 端末側リトライキューで吸収、kureho 介入不要 |
| **重大バグ (v3.0)** | **v2.1.1 と同じ build を v2.1.2 として再 submit** (Apple に「以前のバージョンに自動 rollback」する仕組みは無いため、新規 binary を作って上書き)。または **v3.0 で Phased Release を pause** + ASC で remove from sale で新規 DL 停止 |

### v3.0 開発中の v2.1.x hotfix

- main から `hotfix/v2.1.2-*` ブランチ → main merge → tag → ASC 提出
- v3.0 ブランチに cherry-pick で同期 (extension 構成差分で conflict 注意)

### memory 更新責務 (brainstorm 完了後)

- `MEMORY.md` の「v2.1.1 WAITING_FOR_REVIEW」記述 → READY_FOR_SALE に更新
- `project_adblockkeshi.md` 同様
- 新規記録: v3.0 brainstorm spec (本ファイルへの link)

---

## 9. リスク総覧と対応マトリクス

| カテゴリ | リスク | 確率 | 影響 | 対応 |
|---|---|---|---|---|
| Apple 審査 | 1.2 UGC reject | **中 (rev3: Apple は人手 moderation を暗黙に期待する文化、過度な「全自動」訴求は逆効果)** | release 1-2 週遅延 | review notes でトーンダウン (automated + escalation via Resolution Center)、kureho が abuse 報告に 24h で人手対応する点も明示 |
| Apple 審査 | 5.2.5 metadata 残骸 | 低 | 同上 | 提出前 grep、CI hook |
| Apple 審査 | 5.1.1 Privacy 不整合 | 低 | 同上 | Privacy Policy + Nutrition Label 提出前完全一致 |
| Apple 審査 | 「完全自動」誤読 → moderation 質問 | 低 | release +3-5 日 | review notes に "automated pipeline with developer escalation via Resolution Center for issues automation cannot handle" 明示、kureho が abuse 報告に 24h 人手対応する点も明記 (rev4: §6 本文と整合) |
| 価格 | 機能追加 + 値上げ同時で初動 DL 落ち | 中 | 売上減 | 4 週 KPI monitor、¥600 retreat 余地 |
| 既存ユーザー | 「いきなり値上げ」反発 | 低 | review 低下 | 買い切り影響なしを WhatsNew で説明 |
| 技術 | 2 extension 上限超え | 低 | 設計やり直し | **4 段階 fallback Path 1-4 (rev2 強化)** |
| 技術 | Cloudflare Workers DDoS で free tier 超過 | 低 | $5/M (有料化) | **hard cap 80k/日 + tripwire 70k で warn (rev2)** |
| 技術 | abuse 自動判定の誤 ban | 中 | 善意ユーザー巻き込み | 4 段階 ban (24h から徐々に長期化)、kureho の Resolution Center 経由で手動解除可 |
| moat | chicken-and-egg、初動ユーザー不足 | 中 | moat 形成停滞 | ASO/PR で別軸、新規 LP は app-support に |
| moat | E 軸 (学ぶ) 訴求が刺さらない | 中 | DL 変動 | name 主軸は B 軸、moat は実態で勝つ |

---

## 10. 工数見積サマリ (rev2 更新)

| Phase | 週数 | 主要 deliverable |
|---|---|---|
| Phase 1-2: Infra + UI 基礎 | 4 週 | Cloudflare 稼働、2 extension build、報告タブ画面、PII filter |
| Phase 3-4: safety gate + workflow | 5 週 | 8 層実装、Actions 8 個 (deletion-processor 含む) |
| Phase 5: abuse 自動化 + UI 仕上げ + Privacy | **3 週 (rev2 +1)** | 履歴 UI、moat 可視化、ban 自動 level up、Policy 更新 |
| Phase 6: 検証 | 2 週 | シミュレータ + 実機テスト全網羅、4 点監査 |
| Phase 7: 提出 | 1 週 | 提出 + 4 点監査 |
| **合計** | **15 週 (最短 12 週、最長 16.5 週)** | v3.0 リリース |

---

## 11. 確定済みの決定事項 (brainstorm 合意)

### 11-A. brainstorm 初版 (rev1) で合意

1. ✅ name: `学習する広告消し - 消えない広告もブロック`
2. ✅ subtitle: `他で消えない広告も、報告で進化`
3. ✅ 訴求軸: B 軸前面 + H 軸修飾 + moat 実態形成
4. ✅ 価格: v3.0 ¥700 即値上げ
5. ✅ 完全自動: T3 重量実装、8 層 safety gate
6. ✅ 受信 infra: Cloudflare Workers + D1 + Turnstile (0 円 hard cap)
7. ✅ Content Blocker: 2 extension 構成
8. ✅ 報告タブ: URL + memo、履歴 UI 含む
9. ✅ 既存ユーザーへの強制誘導なし
10. ✅ feature flag で段階退避
11. ✅ v3.0 開発中 main は v2.1.x hotfix 余地維持
12. ✅ TestFlight は提出直前の最終回帰のみ

### 11-B. spec review #1 (rev2) で追加

13. ✅ データ削除依頼は自動処理 (hourly-deletion-processor、1h SLA)
14. ✅ L2/L8 段階閾値 (β 中 L8=2、stable 後 L8=3)
15. ✅ rate limit hard cap 80k/日 + tripwire 70k で warn
16. ✅ abuse 自動化 (4 段階 ban level up)
17. ✅ Extension Path 1-4 fallback
18. ✅ D1 全列確定 + deletion_requests テーブル追加
19. ✅ rollback 経路訂正 (「以前バージョン rollback」誤記削除)
20. ✅ retreat Price Tier 24h vs description 別経路明示
21. ✅ 反映タイムライン 385h 内訳明示

### 11-C. spec review #2 (rev3) で追加

22. ✅ PII redact 方式 (reject ではなく mask、ban 加算しない)
23. ✅ abuse reason 種別ごとの ban 加算重み付け
24. ✅ hourly workflow トリガ時刻分散 :00/:15/:30
25. ✅ Apple 1.2 トーンダウン (review notes "automated with escalation")
26. ✅ HMAC token payload 明示 (subject/expires/scope)
27. ✅ RemoteConfigStore emergency_kill_switch fail-closed
28. ✅ Nutrition Label 安全側で Linked declare
29. ✅ Phase 1 DoD に screencast 必須化
30. ✅ BGTaskScheduler 楽観値修正 (通常 7-14 日、最悪 30 日)
31. ✅ description 価格表記なし (retreat 軽量化)
32. ✅ Tranco sync 月次→週次 (鮮度)
33. ✅ WhatsNew で既存ユーザー無料受領強調

### 11-D. spec review #3 (rev4) で追加

34. ✅ §9 リスク表 review notes 表現を本文 (§6) と整合 (トーンダウン版に統一)
35. ✅ feature flag evaluation order: `emergency_kill_switch > report_tab_enabled`
36. ✅ PII redact 後の履歴 memo 表示仕様 (redact 済を返す + 注記バッジ)
37. ✅ 付録 B 「未確認事項」に各調整トリガ指標を追加

---

## 12. 次のステップ

1. **spec review loop #2** (本 rev2 で再 dispatch)
2. issue 解消継続 (max 5 iter)
3. **kureho による spec レビュー** (本ファイル approval)
4. **writing-plans skill** で詳細実装プラン作成

---

## 付録 A: 凍結 spec からの流用と差分

### 流用
- Cloudflare Workers + D1 + Turnstile 構成
- 8 層 safety gate アーキテクチャ
- HMAC ephemeral token (5 分有効) 設計
- Privacy Policy 文案 (24h 対応、rev2 で自動化に進化)
- Nutrition Label 設計 (rev2 で IP hash declare 追加)
- D1 スキーマ (reports / rule_candidates / abuse_log / bans、rev2 で全列確定 + deletion_requests 追加)
- 1.2 UGC 5 要素対応マトリクス (rev2 で全自動化)

### 差分
- 4.3(b) Spam 対策不要 (本体統合で消滅)
- 既存リポジトリ・bundle id・CDN 流用
- 既存 monthly-filter-update.yml と新規 workflow の concurrency 制御
- 既存ユーザー向けアップグレード UX
- TestFlight ではなくシミュレータ + 実機優先
- 2 extension UI 制約

---

## 付録 B: 未確認事項 (実装段階で verify 必須)

- iOS Safari Content Blocker の **1 app あたり extension 数上限** (Apple 公式 docs 数値未明示)
  - Phase 1 で実機 PoC、結果に応じて Path 1-4 確定
- Apple Price Tier 構造の最新形 (¥500/¥700 の Tier 番号は提出時 verify)
- Cloudflare D1 APAC region primary の latency 実測
- Turnstile 透明 challenge の SwiftUI 統合方法 (WebView 経由 vs Safari)
- **abuse 自動判定の閾値チューニング (3/10/30/100)** — 配信後実データで調整必要、初期値で開始
  - 調整トリガ指標: 1 ヶ月の善意ユーザー誤 ban 苦情 ≥ 3 件 → 閾値緩和 (5/15/50/150)
- **PII redact regex の誤検出率** — rev3 で redact 化したので誤 ban は発生しないが、redact 過多 (memo が空に近くなる) なら正規表現緩和、配信後 abuse_log で確認
  - 調整トリガ指標: 全報告の memo に占める `pii_redacted` 発火率 ≥ 30% → 正規表現緩和
- **L8 cooldown 30 日の妥当性** — 攻撃者が 30 日後に同一 URL 再 ban 試行する経路あり、配信後 complaint_count 実データで調整 (60 日 / 90 日への延長検討)
  - 調整トリガ指標: 同一 selector の再 rollback 発生率 ≥ 5% → cooldown 60 日に延長
- **BGTaskScheduler 実測値** — Phase 1 PoC で実機実観測値 (中央値 / p95 / p99 遅延) を取得、v3.1 で告知文言 (現「通常 7-14 日、最悪 30 日」) を再調整 (rev4 advisory)

---

**(end of spec, rev2 — 2026-06-07)**
