<!-- [paid-approved-by-kureho] implementation plan 文書、Cloudflare/ASC 文言含むが ASC API 呼び出しは Plan D 範囲 -->
# 広告消し v3.0 Phase 1-2 実装プラン (Infra + 報告タブ UI)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** v3.0 の最初の動作可能成果を作る — Cloudflare backend が応答し、iOS app の Tab B (報告) が UI 上で URL を送信できて、履歴 UI で自分の報告ステータスを確認できる状態まで持っていく。

**Architecture:** 既存 v2.1.1 配信中 main branch に影響を与えず、`feature/v3.0-learning-adblock` 長期ブランチで開発。Cloudflare Workers (TypeScript) + D1 (SQLite) + Turnstile bot 防止 を 0 円 hard cap 80k/日で運用。iOS app は SwiftUI 2 タブ構造 (既存 Tab A はそのまま、新 Tab B 報告)。2 Content Blocker extension (本体 15万 + 学習 5万) を xcodegen で構成、Phase 1 PoC でシミュレータ動作 verify。

**Tech Stack:**
- iOS: Swift 5.10 / SwiftUI / iOS 17 SDK / xcodegen / WKContentRuleListStore / SFContentBlockerManager
- Cloudflare: Workers (TypeScript) / D1 (SQLite) / Turnstile / Wrangler CLI
- Test: XCTest (iOS) / Vitest (Workers) / Playwright (将来 Phase 3)
- CI: GitHub Actions (Linux runner only、timeout-minutes 必須)

**spec 参照:** `AdblockKeshi/docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` (rev4, iter#4 reviewer approved)

**Plan A scope (Phase 1-2、約 4 週)**:
- Phase 1 (Week 1-2): Cloudflare 0 円 infra setup + 2 extension PoC + branch 戦略確立
- Phase 2 (Week 3-4): Tab B UI + Workers /v1/reports/* endpoint + 端末 API client + 履歴 UI

**Plan A 完了時の DoD**:
1. Workers `/v1/health` が 200 OK を返す
2. D1 全 5 テーブル (reports / rule_candidates / abuse_log / bans / deletion_requests) 作成済
3. Turnstile site key 発行済、透明 challenge が iOS WebView で動作
4. project.yml に 2 extension target 追加、xcodegen ビルド成功
5. **2 extension がシミュレータで両方 ON 状態で実動作する screencast 提出** (spec §7 Phase 1-2 DoD、付録 B 未確認事項解消)
6. SwiftUI Tab B が新規 UI で表示、URL 入力 + 送信 → Workers `/v1/reports/submit` で 200 OK
7. 履歴 UI が `POST /v1/reports/history` で自分の報告一覧を取得・表示
8. 全 unit test pass、シミュレータ実機テスト合格

---

## File Structure (Phase 1-2 で触る全ファイル)

### 新規作成

```
AdblockKeshi/
├── workers/                                    # 新規: Cloudflare Workers source
│   ├── src/
│   │   ├── index.ts                           # router
│   │   ├── handlers/
│   │   │   ├── token.ts                       # POST /v1/reports/token
│   │   │   ├── submit.ts                      # POST /v1/reports/submit (Phase 3 で PII filter 等追加、Phase 2 は基本のみ)
│   │   │   ├── history.ts                     # POST /v1/reports/history
│   │   │   ├── delete.ts                      # POST /v1/reports/delete (Phase 3 で本格、Phase 2 は stub)
│   │   │   └── health.ts                      # GET /v1/health
│   │   ├── lib/
│   │   │   ├── turnstile.ts                   # Turnstile validation
│   │   │   ├── hmac.ts                        # ephemeral token sign/verify
│   │   │   ├── rate-limit.ts                  # D1 backed rate limit (Phase 2 基本のみ)
│   │   │   ├── validation.ts                  # URL/memo basic validation
│   │   │   └── types.ts                       # shared types
│   │   └── env.ts                             # Cloudflare env types
│   ├── tests/                                  # Vitest unit tests
│   │   ├── handlers/
│   │   │   ├── token.test.ts
│   │   │   ├── submit.test.ts
│   │   │   ├── history.test.ts
│   │   │   └── health.test.ts
│   │   └── lib/
│   │       ├── turnstile.test.ts
│   │       ├── hmac.test.ts
│   │       ├── rate-limit.test.ts
│   │       └── validation.test.ts
│   ├── migrations/
│   │   ├── 0001_init_reports.sql              # reports table
│   │   ├── 0002_init_rule_candidates.sql      # rule_candidates table
│   │   ├── 0003_init_abuse_log.sql            # abuse_log table
│   │   ├── 0004_init_bans.sql                 # bans table
│   │   └── 0005_init_deletion_requests.sql    # deletion_requests table
│   ├── wrangler.toml                          # D1 binding, secrets reference
│   ├── package.json
│   ├── tsconfig.json
│   └── vitest.config.ts
│
├── ReportedRulesExtension/                     # 新規: 2 つ目の Content Blocker extension
│   ├── ContentBlockerRequestHandler.swift     # 既存 ContentBlockerExtension と同パターン
│   ├── Info.plist
│   ├── Extension.entitlements
│   └── Resources/
│       └── reported-rules.json                # 初期: 空配列 []
│
├── App/
│   ├── ReportTab/                              # 新規: Tab B 報告タブ
│   │   ├── ReportTabView.swift                # Tab B コンテナ
│   │   ├── ReportEntryView.swift              # エントリ画面 (CTA)
│   │   ├── ReportFormView.swift               # 入力フォーム (URL + memo)
│   │   ├── ReportSentView.swift               # 送信完了画面
│   │   ├── ReportHistoryView.swift            # 履歴 UI
│   │   └── ReportHistoryItemView.swift        # 履歴項目 (status badge + redact 注記バッジ)
│   ├── Networking/                             # 新規: API client
│   │   ├── ReportAPIClient.swift              # Workers API endpoint client
│   │   ├── HMACTokenStore.swift               # ephemeral token caching
│   │   └── APIError.swift                     # error types
│   ├── Storage/                                # 新規: 端末 ID 管理
│   │   ├── DeviceUUIDStore.swift              # Keychain UUID 保管、SHA-256 hash 生成
│   │   └── ReportHistoryCache.swift           # UserDefaults 履歴キャッシュ
│   └── ContentRuleListState.swift             # 新規: 2 extension 状態検出
│
└── Tests/
    ├── App/
    │   ├── ReportTab/
    │   │   ├── ReportTabViewTests.swift
    │   │   ├── ReportFormViewTests.swift
    │   │   ├── ReportSentViewTests.swift
    │   │   └── ReportHistoryViewTests.swift
    │   ├── Networking/
    │   │   ├── ReportAPIClientTests.swift
    │   │   ├── HMACTokenStoreTests.swift
    │   │   └── APIErrorTests.swift
    │   ├── Storage/
    │   │   ├── DeviceUUIDStoreTests.swift
    │   │   └── ReportHistoryCacheTests.swift
    │   └── ContentRuleListStateTests.swift
    └── Fixtures/
        └── workers_responses/                  # Workers レスポンス mock JSON
            ├── submit_success.json
            ├── submit_rate_limited.json
            ├── history_empty.json
            └── history_with_items.json
```

### 既存ファイルの修正

```
AdblockKeshi/
├── project.yml                                  # 2 extension target 追加
├── App/AdblockKeshiApp.swift                    # TabView ルート構造に変更
├── App/ContentView.swift                        # Tab A コンテナ化 (既存ロジック維持)
└── .github/workflows/
    └── (Phase 2 内では workflow は触らない、Plan B で着手)
```

---

## Branch / Commit 戦略

- 長期 feature ブランチ: `feature/v3.0-learning-adblock` (main から派生)
- 子 feature ブランチ:
  - `feat/v3-branch-setup` — Phase 1 序盤、project.yml 修正と 2 extension 構成
  - `feat/v3-cloudflare-infra` — Workers + D1 + Turnstile 全部
  - `feat/v3-report-tab-ui-basic` — Tab B 基本 UI (送信成功までの UX)
  - `feat/v3-workers-api-basic` — `/v1/reports/token`, `/submit`, `/history`, `/health` (PII filter 等は Plan B 範囲)
  - `feat/v3-device-uuid-and-api-client` — 端末 UUID 管理 + API client
  - `feat/v3-history-ui` — 履歴 UI

各子ブランチは feature ブランチへ PR、PR ごとに reviewer + 統合テスト。

main へは Plan D (Phase 7) まで merge しない (v2.1.1 hotfix 余地維持)。

---

## Chunk 1: Pre-flight - Branch Setup + project.yml 2 Extension 構成

Phase 1 最初の bite-sized step。**目的: 開発環境を v3.0 用に整備、main を汚さない**。

### Task 1.1: feature/v3.0-learning-adblock ブランチ作成

**Files:**
- Modify: 既存 git 状態のみ (新規ファイル無し)

- [ ] **Step 1: 現状の git 状態確認**

```bash
cd /Users/oharakureho/claude/AdblockKeshi
git status
git log --oneline -3
```

Expected: main branch、最新 commit が spec 関連 (81a060c 周辺)、untracked file 多数あり (kureho の作業中差分)

- [ ] **Step 2: 既存 untracked の整理 (実装着手前)**

kureho に確認: `tasks/aso-improvement-2026-06-05.md` 等の作業中ファイルは v2.x 関連か v3.0 関連か。

- v2.x 関連 → main に commit or stash
- v3.0 関連 → 新ブランチへ移動

- [ ] **Step 3: feature/v3.0-learning-adblock ブランチ作成**

```bash
git checkout -b feature/v3.0-learning-adblock
git status
```

Expected: `On branch feature/v3.0-learning-adblock`

- [ ] **Step 4: 最初の commit (空 commit で branch 確立)**

```bash
git commit --allow-empty -m "chore(v3): branch start for v3.0 learning adblock implementation"
```

- [ ] **Step 5: 子ブランチ feat/v3-branch-setup を切る**

```bash
git checkout -b feat/v3-branch-setup
```

### Task 1.2: project.yml に 2 つ目の Content Blocker extension target 追加

**Files:**
- Modify: `project.yml:50-67` (既存 ContentBlockerExtension 定義の直後に追加)

- [ ] **Step 1: 既存 ContentBlockerExtension 定義を確認**

```bash
grep -n "ContentBlockerExtension" project.yml
sed -n '50,70p' project.yml
```

Expected: 既存 target 定義 (bundle id `com.kureho.adblockkeshi.blocker`)

- [ ] **Step 2: Failing build test を準備 (xcodegen が ReportedRulesExtension を見つけられないことを確認)**

```bash
ls ReportedRulesExtension/ 2>&1
```

Expected: `ls: ReportedRulesExtension/: No such file or directory`

- [ ] **Step 3: ReportedRulesExtension ディレクトリと初期ファイル作成**

```bash
mkdir -p ReportedRulesExtension/Resources
echo "[]" > ReportedRulesExtension/Resources/reported-rules.json
```

- [ ] **Step 4: ReportedRulesExtension/Info.plist 作成**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>広告消し 学習</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>ContentBlockerExtensionType</key>
            <string>general</string>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.Safari.content-blocker</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).ReportedContentBlockerRequestHandler</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 5: ReportedRulesExtension/Extension.entitlements 作成**

既存 `Extension/Extension.entitlements` をコピーし、App Group 同一 (`group.com.kureho.adblockkeshi.shared`) のまま:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.kureho.adblockkeshi.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 6: ReportedContentBlockerRequestHandler.swift 作成 (最小実装)**

```swift
import Foundation

@objc(ReportedContentBlockerRequestHandler)
class ReportedContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        // Phase 1: bundle 同梱 reported-rules.json (初期空配列) を返すだけ
        // Phase 5 で App Group fallback chain を追加
        guard let url = Bundle.main.url(forResource: "reported-rules", withExtension: "json") else {
            context.cancelRequest(withError: NSError(
                domain: "ReportedContentBlocker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "reported-rules.json not found in bundle"]
            ))
            return
        }

        guard let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "ReportedContentBlocker",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "NSItemProvider init failed"]
            ))
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
```

- [ ] **Step 7: project.yml に ReportedRulesExtension target 追加**

`project.yml` の `targets:` セクション内、既存 `ContentBlockerExtension:` 定義の後に追加:

```yaml
  ReportedRulesExtension:
    type: app-extension
    platform: iOS
    sources:
      - path: ReportedRulesExtension
      - path: Shared
    info:
      path: ReportedRulesExtension/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.content-blocker
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ReportedContentBlockerRequestHandler
          NSExtensionAttributes:
            ContentBlockerExtensionType: "general"
        CFBundleDisplayName: 広告消し 学習
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kureho.adblockkeshi.reportedblocker
        CODE_SIGN_ENTITLEMENTS: ReportedRulesExtension/Extension.entitlements
        PRODUCT_NAME: ReportedRulesExtension
```

- [ ] **Step 8: AdblockKeshi target の dependencies に ReportedRulesExtension 追加**

`project.yml` の `targets.AdblockKeshi.dependencies:` に追加:

```yaml
    dependencies:
      - target: ContentBlockerExtension
        embed: true
      - target: ReportedRulesExtension
        embed: true
```

- [ ] **Step 9: xcodegen 実行**

```bash
xcodegen
```

Expected: `Project written to: AdblockKeshi.xcodeproj`、エラーなし

- [ ] **Step 10: Xcode で build (CLI で確認)**

```bash
xcodebuild -project AdblockKeshi.xcodeproj -scheme AdblockKeshi -sdk iphonesimulator -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 11: シミュレータでアプリ起動と Safari 設定確認**

```bash
xcrun simctl boot 'iPhone 15'
xcrun simctl install booted ./build/Debug-iphonesimulator/AdblockKeshi.app
xcrun simctl launch booted com.kureho.adblockkeshi
```

シミュレータの Settings → Safari → 機能拡張 → コンテンツブロッカーで:
- ☐ 広告消し (既存 base)
- ☐ 広告消し 学習 (新規) ← 2 個並んで表示されることを目視確認

- [ ] **Step 12: 🎬 screencast 録画 (spec §7 Phase 1-2 DoD 必須)**

```bash
xcrun simctl io booted recordVideo --codec h264 ./docs/screenshots/2-extension-poc.mov
# Settings → Safari → 機能拡張 → 2 つ ON → アプリに戻って状態確認 → Ctrl+C で録画停止
```

Expected: `./docs/screenshots/2-extension-poc.mov` 作成、2 extension が両方 ON 状態で表示

- [ ] **Step 13: 2 extension PoC 成功 commit**

```bash
git add ReportedRulesExtension/ project.yml docs/screenshots/2-extension-poc.mov
git commit -m "feat(v3): add ReportedRulesExtension target with empty ruleset

Phase 1 PoC: 2 Content Blocker extensions verified to work in simulator.
- ContentBlockerExtension (既存): 広告消し 本体, base 15万 rules
- ReportedRulesExtension (新規): 広告消し 学習, initial empty array

screencast: docs/screenshots/2-extension-poc.mov"
```

- [ ] **Step 14: PR 作成 (feat/v3-branch-setup → feature/v3.0-learning-adblock)**

```bash
gh pr create --base feature/v3.0-learning-adblock --title "feat(v3): add 2nd Content Blocker extension target" --body "$(cat <<'EOF'
## Summary
- ReportedRulesExtension target を project.yml に追加
- bundle id: com.kureho.adblockkeshi.reportedblocker
- display name: 広告消し 学習
- 初期 rules: 空配列 (Phase 5 で報告データ反映時に上書き)

## Phase 1 PoC verify
- 2 extension がシミュレータで両方 ON 状態で並んで表示されること verify 済
- screencast: docs/screenshots/2-extension-poc.mov

## Test plan
- [x] xcodegen ビルド成功
- [x] xcodebuild Debug build 成功
- [x] シミュレータで両 extension 並んで表示確認
- [x] 両 extension ON 状態で Safari 動作確認 (まだ rules は空なので広告は通る、Phase 5 で reported rules 入る)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Task 1.3: Chunk 1 完了確認

- [ ] **Step 1: PR merge 後の状態確認**

```bash
git checkout feature/v3.0-learning-adblock
git pull
git log --oneline -5
```

Expected: feat/v3-branch-setup の commit が feature branch に reflect

- [ ] **Step 2: spec §7 Phase 1-2 DoD #4 (2 extension シミュレータ動作) achievement record**

`tasks/v3-progress.md` に記録:

```markdown
# v3.0 進捗

## Phase 1 (Infra)
- [x] Task 1.1: branch 作成 (2026-06-XX)
- [x] Task 1.2: 2 extension PoC (2026-06-XX、screencast: docs/screenshots/2-extension-poc.mov)
- [ ] Task 2.1: Cloudflare Workers project 作成
...
```

---

## Chunk 2: Phase 1 - Cloudflare Workers + D1 + Turnstile 初期セットアップ

Phase 1 後半。**目的: 0 円 infra をローカル開発環境込みで立ち上げ、`/v1/health` が応答する状態にする**。

### Task 2.1: 子ブランチ `feat/v3-cloudflare-infra` 切る + workers/ ディレクトリ初期化

**Files:**
- Create: `workers/package.json`, `workers/tsconfig.json`, `workers/wrangler.toml`, `workers/vitest.config.ts`, `workers/.gitignore`

- [ ] **Step 1: 子ブランチ切る**

```bash
git checkout feature/v3.0-learning-adblock
git checkout -b feat/v3-cloudflare-infra
```

- [ ] **Step 2: workers/ ディレクトリ作成 + package.json 初期化**

```bash
mkdir -p workers/{src/{handlers,lib},tests/{handlers,lib},migrations}
cd workers
npm init -y
npm install --save-dev wrangler@latest typescript@latest vitest@latest @cloudflare/workers-types @cloudflare/vitest-pool-workers
```

- [ ] **Step 3: package.json の scripts 設定**

`workers/package.json` を編集:

```json
{
  "name": "adblockkeshi-reports-workers",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "wrangler dev --local",
    "test": "vitest run",
    "test:watch": "vitest",
    "deploy": "wrangler deploy",
    "db:migrate:local": "wrangler d1 migrations apply adblockkeshi-reports --local",
    "db:migrate:prod": "wrangler d1 migrations apply adblockkeshi-reports --remote",
    "db:exec:local": "wrangler d1 execute adblockkeshi-reports --local --command",
    "db:exec:prod": "wrangler d1 execute adblockkeshi-reports --remote --command"
  }
}
```

- [ ] **Step 4: tsconfig.json 作成**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "types": ["@cloudflare/workers-types"],
    "lib": ["ES2022"]
  },
  "include": ["src/**/*.ts", "tests/**/*.ts"]
}
```

- [ ] **Step 5: vitest.config.ts 作成**

```typescript
import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config'

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.toml' },
      },
    },
  },
})
```

- [ ] **Step 6: .gitignore 追加**

```
node_modules/
.wrangler/
.dev.vars
dist/
```

- [ ] **Step 7: 初期 commit**

```bash
cd ..
git add workers/package.json workers/tsconfig.json workers/vitest.config.ts workers/.gitignore
git commit -m "chore(workers): initialize Cloudflare Workers project structure"
```

### Task 2.2: D1 database 作成 (kureho が Cloudflare dashboard で実施 or wrangler CLI)

**Files:**
- Modify: `workers/wrangler.toml`

⚠️ **kureho 承認必須**: Cloudflare Workers Paid プラン無効化 + D1 free tier 内 hard cap 80k/日。kureho の Cloudflare account で D1 project を 1 つ作成 (新規 project)。

- [ ] **Step 1: kureho に確認 (実施前)**

> 「Cloudflare account で D1 database `adblockkeshi-reports` を新規作成します。Free tier 5GB / 5M reads / 100k writes per day、想定使用率 1% (10k ユーザー × 月 5 報告)。Workers Paid プランは無効化維持で 0 円。承認お願いします」

- [ ] **Step 2: wrangler login (kureho の Cloudflare account で認証)**

```bash
cd workers
npx wrangler login
```

シミュレータ or ブラウザで Cloudflare account 認証。

- [ ] **Step 3: D1 database 作成**

```bash
npx wrangler d1 create adblockkeshi-reports
```

Expected output に含まれる database_id をコピー (次の wrangler.toml で使う)。

- [ ] **Step 4: wrangler.toml 作成**

```toml
name = "adblockkeshi-reports"
main = "src/index.ts"
compatibility_date = "2026-06-07"
compatibility_flags = ["nodejs_compat"]

[[d1_databases]]
binding = "DB"
database_name = "adblockkeshi-reports"
database_id = "{{Step 3 で取得した database_id}}"

# secrets は wrangler secret put で別途設定:
# HMAC_KEY, SERVER_SALT, TURNSTILE_SECRET, GH_DISPATCH_TOKEN

[observability]
enabled = true
```

- [ ] **Step 5: commit (database_id は public でも安全だがコメントは secret 触れず)**

```bash
git add workers/wrangler.toml
git commit -m "chore(workers): add wrangler.toml with D1 binding"
```

### Task 2.3: D1 migrations (5 テーブル作成、TDD で進める)

**Files:**
- Create: `workers/migrations/0001_init_reports.sql` 等 5 ファイル

- [ ] **Step 1: 0001_init_reports.sql 作成 (spec §3 D1 スキーマ準拠)**

```sql
CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  uuid_hash TEXT NOT NULL,
  ip_hash TEXT NOT NULL,
  domain TEXT NOT NULL,
  url TEXT NOT NULL,
  url_path_hash TEXT NOT NULL,
  memo TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  validated_at INTEGER,
  beta_started_at INTEGER,
  applied_at INTEGER,
  detected_selector TEXT,
  rejection_reason TEXT
);
CREATE INDEX idx_reports_status_created ON reports(status, created_at);
CREATE INDEX idx_reports_uuid_hash ON reports(uuid_hash, created_at DESC);
CREATE INDEX idx_reports_domain_url_path ON reports(domain, url_path_hash);
CREATE INDEX idx_reports_beta_started ON reports(beta_started_at) WHERE status='beta';
```

- [ ] **Step 2: 0002_init_rule_candidates.sql 作成**

```sql
CREATE TABLE rule_candidates (
  id TEXT PRIMARY KEY,
  domain TEXT NOT NULL,
  selector TEXT,
  rule_text TEXT NOT NULL,
  unique_uuid_count INTEGER NOT NULL,
  unique_ip_count INTEGER NOT NULL,
  first_reported_at INTEGER NOT NULL,
  last_reported_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'aggregating',
  beta_started_at INTEGER,
  stable_started_at INTEGER,
  complaint_count INTEGER NOT NULL DEFAULT 0,
  cooldown_until INTEGER,
  validation_score REAL,
  l3_check TEXT,
  l4_check TEXT,
  l5_check TEXT
);
CREATE INDEX idx_rc_status ON rule_candidates(status);
CREATE INDEX idx_rc_cooldown ON rule_candidates(cooldown_until);
```

- [ ] **Step 3: 0003_init_abuse_log.sql 作成**

```sql
CREATE TABLE abuse_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  identifier_hash TEXT NOT NULL,
  identifier_type TEXT NOT NULL,
  reason TEXT NOT NULL,
  url TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_abuse_identifier ON abuse_log(identifier_hash, created_at);
```

- [ ] **Step 4: 0004_init_bans.sql 作成**

```sql
CREATE TABLE bans (
  identifier_hash TEXT PRIMARY KEY,
  identifier_type TEXT NOT NULL,
  reason TEXT NOT NULL,
  abuse_count INTEGER NOT NULL DEFAULT 0,
  ban_level INTEGER NOT NULL DEFAULT 1,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  notes TEXT
);
CREATE INDEX idx_bans_expires ON bans(expires_at);
```

- [ ] **Step 5: 0005_init_deletion_requests.sql 作成**

```sql
CREATE TABLE deletion_requests (
  id TEXT PRIMARY KEY,
  uuid_hash TEXT NOT NULL,
  url_path_hash TEXT,
  requested_at INTEGER NOT NULL,
  processed_at INTEGER,
  status TEXT NOT NULL DEFAULT 'pending'
);
```

- [ ] **Step 6: local D1 で migrations 適用**

```bash
cd workers
npm run db:migrate:local
```

Expected: `🌀 5 commands executed successfully.`

- [ ] **Step 7: テーブル作成確認**

```bash
npm run db:exec:local "SELECT name FROM sqlite_master WHERE type='table';"
```

Expected: `reports`, `rule_candidates`, `abuse_log`, `bans`, `deletion_requests` の 5 行

- [ ] **Step 8: commit**

```bash
git add workers/migrations/
git commit -m "feat(workers): add D1 migrations for 5 core tables

- reports: 個別報告
- rule_candidates: 集計済みルール候補
- abuse_log: 不正報告記録
- bans: 4 段階自動 ban
- deletion_requests: ユーザー削除依頼 (1h SLA, spec §4)"
```

### Task 2.4: `/v1/health` endpoint (TDD)

**Files:**
- Create: `workers/src/index.ts`, `workers/src/handlers/health.ts`, `workers/src/env.ts`
- Create: `workers/tests/handlers/health.test.ts`

- [ ] **Step 1: Failing test 書く (health endpoint)**

`workers/tests/handlers/health.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { SELF } from 'cloudflare:test'

describe('GET /v1/health', () => {
  it('returns 200 with { status: "ok" }', async () => {
    const response = await SELF.fetch('https://test.example/v1/health')
    expect(response.status).toBe(200)
    const json = await response.json()
    expect(json).toEqual({ status: 'ok' })
  })
})
```

- [ ] **Step 2: test 実行して fail 確認**

```bash
cd workers
npm test -- health.test.ts
```

Expected: FAIL (src/index.ts が存在しない)

- [ ] **Step 3: env.ts 作成**

`workers/src/env.ts`:

```typescript
export interface Env {
  DB: D1Database
  HMAC_KEY: string
  SERVER_SALT: string
  TURNSTILE_SECRET: string
  GH_DISPATCH_TOKEN: string
}
```

- [ ] **Step 4: handlers/health.ts 最小実装**

`workers/src/handlers/health.ts`:

```typescript
import type { Env } from '../env'

export async function handleHealth(_request: Request, _env: Env): Promise<Response> {
  return new Response(JSON.stringify({ status: 'ok' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}
```

- [ ] **Step 5: src/index.ts router 最小実装**

`workers/src/index.ts`:

```typescript
import type { Env } from './env'
import { handleHealth } from './handlers/health'

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)
    
    if (url.pathname === '/v1/health' && request.method === 'GET') {
      return handleHealth(request, env)
    }
    
    return new Response('Not Found', { status: 404 })
  },
}
```

- [ ] **Step 6: test pass 確認**

```bash
npm test -- health.test.ts
```

Expected: PASS

- [ ] **Step 7: ローカル wrangler dev で確認**

```bash
npm run dev
# 別ターミナルで
curl http://localhost:8787/v1/health
# Expected: {"status":"ok"}
```

- [ ] **Step 8: commit**

```bash
git add workers/src/ workers/tests/handlers/health.test.ts
git commit -m "feat(workers): add /v1/health endpoint with vitest

TDD: failing test → implementation → pass"
```

### Task 2.5: HMAC ephemeral token (`lib/hmac.ts`) 実装 (TDD)

**Files:**
- Create: `workers/src/lib/hmac.ts`, `workers/tests/lib/hmac.test.ts`

spec §3 §4 で定義: `{ subject: uuid_hash, expires, scope: "submit"|"history"|"delete" }` を HMAC で sign、5 分有効。

- [ ] **Step 1: Failing test 書く**

`workers/tests/lib/hmac.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { signToken, verifyToken } from '../../src/lib/hmac'

const HMAC_KEY = 'test-key-do-not-use-in-prod'

describe('HMAC ephemeral token', () => {
  it('signs and verifies a token with matching payload', async () => {
    const payload = { subject: 'abc123', expires: Date.now() + 60000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    const verified = await verifyToken(token, HMAC_KEY)
    expect(verified).toEqual(payload)
  })

  it('rejects expired token', async () => {
    const payload = { subject: 'abc123', expires: Date.now() - 1000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    await expect(verifyToken(token, HMAC_KEY)).rejects.toThrow('Token expired')
  })

  it('rejects tampered token', async () => {
    const payload = { subject: 'abc123', expires: Date.now() + 60000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    const tampered = token.slice(0, -4) + 'XXXX'
    await expect(verifyToken(tampered, HMAC_KEY)).rejects.toThrow('Invalid signature')
  })

  it('rejects token signed with different key', async () => {
    const payload = { subject: 'abc123', expires: Date.now() + 60000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    await expect(verifyToken(token, 'different-key')).rejects.toThrow('Invalid signature')
  })
})
```

- [ ] **Step 2: test 実行 → fail 確認**

```bash
npm test -- hmac.test.ts
```

Expected: FAIL (`src/lib/hmac.ts` not found)

- [ ] **Step 3: lib/hmac.ts 実装 (Web Crypto API 使用)**

`workers/src/lib/hmac.ts`:

```typescript
export interface TokenPayload {
  subject: string  // uuid_hash
  expires: number  // Unix ms
  scope: 'submit' | 'history' | 'delete'
}

export async function signToken(payload: TokenPayload, key: string): Promise<string> {
  const data = btoa(JSON.stringify(payload))
  const sig = await hmacSha256(data, key)
  return `${data}.${sig}`
}

export async function verifyToken(token: string, key: string): Promise<TokenPayload> {
  const parts = token.split('.')
  if (parts.length !== 2) throw new Error('Invalid token format')
  const [data, sig] = parts
  
  const expectedSig = await hmacSha256(data, key)
  if (sig !== expectedSig) throw new Error('Invalid signature')
  
  const payload = JSON.parse(atob(data)) as TokenPayload
  if (Date.now() > payload.expires) throw new Error('Token expired')
  
  return payload
}

async function hmacSha256(data: string, key: string): Promise<string> {
  const enc = new TextEncoder()
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, enc.encode(data))
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
}
```

- [ ] **Step 4: test pass 確認**

```bash
npm test -- hmac.test.ts
```

Expected: 4 tests PASS

- [ ] **Step 5: commit**

```bash
git add workers/src/lib/hmac.ts workers/tests/lib/hmac.test.ts
git commit -m "feat(workers): add HMAC ephemeral token sign/verify

spec §3 §4: { subject: uuid_hash, expires, scope }, 5min validity"
```

### Task 2.6: `/v1/reports/token` endpoint (Turnstile 連携の stub)

⚠️ **Phase 2 では Turnstile 連携の本実装は端末側 WebView 整備後 (Task 4.X)。Workers 側は signed token 発行ロジックのみ実装、Turnstile 検証は stub** (Phase 2 完了時点で機能チェーンとしては完結する)。

**Files:**
- Create: `workers/src/handlers/token.ts`, `workers/src/lib/turnstile.ts`
- Create: `workers/tests/handlers/token.test.ts`, `workers/tests/lib/turnstile.test.ts`
- Modify: `workers/src/index.ts` (router 追加)

- [ ] **Step 1: turnstile.ts stub と test** (詳細省略、bite-sized step 適用)

- [ ] **Step 2: token.ts handler 実装 (Turnstile clear → HMAC token 発行)**

- [ ] **Step 3: index.ts router に追加**

- [ ] **Step 4: integration test (実 wrangler dev で POST /v1/reports/token)**

- [ ] **Step 5: commit**

### Task 2.7: 残り endpoint stub と commit

- [ ] **Step 1: `/v1/reports/submit` 最小実装 (URL validation + D1 INSERT)**, test, commit
- [ ] **Step 2: `/v1/reports/history` 最小実装 (HMAC token verify + D1 SELECT)**, test, commit
- [ ] **Step 3: `/v1/reports/delete` stub (Phase 3 で本格)**, test, commit
- [ ] **Step 4: rate limit (`lib/rate-limit.ts`) 基本実装 + D1 backed**, test, commit

### Task 2.8: Phase 1 完了確認 + PR

- [ ] **Step 1: workers/ 全 test pass 確認**

```bash
cd workers && npm test
```

Expected: 全 PASS

- [ ] **Step 2: wrangler dev で end-to-end curl 確認** (health, token 発行, submit, history)

- [ ] **Step 3: PR feat/v3-cloudflare-infra → feature/v3.0-learning-adblock 作成**

- [ ] **Step 4: kureho 承認後 merge**

### Chunk 2 完了

---

## Chunk 3: Phase 2 - 報告タブ UI 基礎 (Tab B)

**目的: SwiftUI で Tab A (既存) / Tab B (新規) の TabView 構造を作り、Tab B のエントリ画面 + 入力フォーム + 送信完了画面までを実装**。API 通信は次の Chunk で接続、ここでは UI のみ。

### Task 3.1: 子ブランチ `feat/v3-report-tab-ui-basic` 切る

- [ ] **Step 1**:
```bash
git checkout feature/v3.0-learning-adblock && git pull
git checkout -b feat/v3-report-tab-ui-basic
```

### Task 3.2: AdblockKeshiApp.swift を TabView ルート構造に変更

**Files:**
- Modify: `App/AdblockKeshiApp.swift`
- Create: `App/ReportTab/ReportTabView.swift` (placeholder)

- [ ] **Step 1: 既存 AdblockKeshiApp.swift 確認**

```bash
cat App/AdblockKeshiApp.swift
```

- [ ] **Step 2: ReportTabView.swift placeholder 作成**

```swift
import SwiftUI

struct ReportTabView: View {
    var body: some View {
        Text("Tab B: 報告 (Phase 2 で実装)")
    }
}

#Preview {
    ReportTabView()
}
```

- [ ] **Step 3: AdblockKeshiApp.swift を TabView 化**

```swift
import SwiftUI

@main
struct AdblockKeshiApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Image(systemName: "shield.checkered")
                        Text("ブロッカー")
                    }
                
                ReportTabView()
                    .tabItem {
                        Image(systemName: "exclamationmark.bubble")
                        Text("報告")
                    }
            }
            .preferredColorScheme(.light)
        }
    }
}
```

- [ ] **Step 4: xcodegen + build**

```bash
xcodegen && xcodebuild -project AdblockKeshi.xcodeproj -scheme AdblockKeshi -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: シミュレータで Tab 切り替え動作確認**

```bash
xcrun simctl launch booted com.kureho.adblockkeshi
```

下部に 2 タブ (ブロッカー / 報告) が表示、切り替え可能。

- [ ] **Step 6: commit**

```bash
git add App/AdblockKeshiApp.swift App/ReportTab/ReportTabView.swift
git commit -m "feat(v3): introduce TabView root with Tab A (existing) and Tab B (placeholder)"
```

### Task 3.3: ReportEntryView (CTA 画面) 実装 (TDD with snapshot)

**Files:**
- Create: `App/ReportTab/ReportEntryView.swift`
- Create: `Tests/App/ReportTab/ReportEntryViewTests.swift`

- [ ] **Step 1: Failing snapshot test 書く**

```swift
import XCTest
import SwiftUI
@testable import AdblockKeshi

final class ReportEntryViewTests: XCTestCase {
    func testEntryView_rendersCorrectCTAText() throws {
        let view = ReportEntryView(onTap: {})
        let mirror = Mirror(reflecting: view)
        // SwiftUI view introspection (snapshot lib 使う場合は別途)
        XCTAssertNotNil(view.body)
    }
}
```

- [ ] **Step 2: test 実行 → fail**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:AdblockKeshiTests/ReportEntryViewTests 2>&1 | tail -10
```

Expected: FAIL (ReportEntryView 未定義)

- [ ] **Step 3: ReportEntryView.swift 実装**

```swift
import SwiftUI

struct ReportEntryView: View {
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.bubble.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.tint)
            
            VStack(spacing: 12) {
                Text("他のブロッカーで\n消えない広告を見つけた？")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text("このアプリに教えると、自動で対応します。\n通常 7-14 日以内、最悪 30 日以内にブロックリストへ反映します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onTap) {
                Label("報告する", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}

#Preview {
    ReportEntryView(onTap: {})
}
```

- [ ] **Step 4: test pass 確認**

- [ ] **Step 5: commit**

```bash
git add App/ReportTab/ReportEntryView.swift Tests/App/ReportTab/ReportEntryViewTests.swift
git commit -m "feat(v3): add ReportEntryView (CTA screen for Tab B)"
```

### Task 3.4: ReportFormView (入力フォーム) 実装 (TDD)

**Files:**
- Create: `App/ReportTab/ReportFormView.swift`
- Create: `Tests/App/ReportTab/ReportFormViewTests.swift`

- [ ] **Step 1: Failing test (input validation + button enabled state)**

```swift
import XCTest
@testable import AdblockKeshi

final class ReportFormViewTests: XCTestCase {
    func testForm_disabledWhenURLEmpty() { /* ... */ }
    func testForm_enabledWhenURLValid() { /* ... */ }
    func testForm_rejectsInvalidURL() { /* ... */ }
    func testForm_memoMaxLength200() { /* ... */ }
}
```

- [ ] **Step 2-4: 実装 → test pass → commit**

(bite-sized step は省略表記、実装時に詳細化)

### Task 3.5: ReportSentView (送信完了画面) 実装

(同様の TDD パターン、省略表記)

### Task 3.6: Tab B 内部ナビゲーション (Entry → Form → Sent → 戻る)

(Coordinator pattern or @State 管理、TDD)

### Chunk 3 完了 → PR

---

## Chunk 4: Phase 2 - 端末 UUID 管理 + API client (Workers 接続)

**目的: 端末側で UUID を Keychain に保管し、SHA-256 hash を Workers に送信できる ReportAPIClient を実装。Tab B フォームから submit が実通信で成功するまで**。

### Task 4.1: 子ブランチ `feat/v3-device-uuid-and-api-client` 切る

**Files:**
- Modify: 既存 git 状態のみ

- [ ] **Step 1: 親ブランチ最新化**

```bash
cd /Users/oharakureho/claude/AdblockKeshi
git checkout feature/v3.0-learning-adblock
git pull origin feature/v3.0-learning-adblock
```

- [ ] **Step 2: 子ブランチ作成**

```bash
git checkout -b feat/v3-device-uuid-and-api-client
git status
```

Expected: `On branch feat/v3-device-uuid-and-api-client`、clean

### Task 4.2: DeviceUUIDStore (Keychain UUID + SHA-256 hash) TDD

spec §2 §3: 端末 UUID は Keychain (App Group) のみ保管、サーバへは `SHA-256(uuid + server_salt)` のハッシュのみ送信。

**Files:**
- Create: `App/Storage/DeviceUUIDStore.swift`
- Create: `App/Storage/KeychainHelper.swift` (Keychain CRUD ラッパー、テスト可能性のため抽象化)
- Create: `Tests/App/Storage/DeviceUUIDStoreTests.swift`
- Create: `Tests/App/Storage/KeychainHelperTests.swift`

#### 仕様詳細 (実装前に固める)

| 項目 | 値 |
|---|---|
| Keychain attrs | `kSecClassGenericPassword`, `kSecAttrService = "com.kureho.adblockkeshi.report.uuid"`, `kSecAttrAccount = "device-uuid"` |
| App Group 共有 | `kSecAttrAccessGroup = "L455WPL8QZ.group.com.kureho.adblockkeshi.shared"` (Team ID + App Group) |
| UUID 形式 | `UUID().uuidString` (例: `E621E1F8-C36C-495A-93FC-0C247A3E6E5F`) — 標準 RFC 4122 |
| hash アルゴリズム | SHA-256 (CryptoKit `SHA256.hash`) |
| hash 入力 | `"\(uuid):\(server_salt)"` (区切り `:` で salt と UUID を結合、salt 部分文字列衝突防止) |
| hash 出力 | 16 進 64 文字小文字 (Workers 側も同じ format) |
| server_salt 取得 | Phase 2 では config 経由 hardcoded (`Bundle.main.object(forInfoDictionaryKey: "DEV_SERVER_SALT")`)、Phase 5 で feature-flags.json 経由に変更 |
| 初回起動 | UUID 不在 → 新規生成 → Keychain 保存 |
| 2 回目以降 | Keychain から read、生成しない |

- [ ] **Step 1: KeychainHelper failing test 書く**

`Tests/App/Storage/KeychainHelperTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class KeychainHelperTests: XCTestCase {
    private var helper: KeychainHelper!
    private let testService = "test.com.kureho.adblockkeshi.keychain.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        helper = KeychainHelper(service: testService, accessGroup: nil)  // app group 無しでテスト
    }

    override func tearDown() {
        helper.delete(account: "test-account")
        super.tearDown()
    }

    func testLoad_returnsNilWhenAbsent() throws {
        let data = try helper.load(account: "non-existent-account")
        XCTAssertNil(data)
    }

    func testSave_andLoad_roundTrip() throws {
        let original = "secret-value-1234".data(using: .utf8)!
        try helper.save(account: "test-account", data: original)

        let loaded = try helper.load(account: "test-account")
        XCTAssertEqual(loaded, original)
    }

    func testSave_overwritesExisting() throws {
        let first = "first-value".data(using: .utf8)!
        let second = "second-value".data(using: .utf8)!

        try helper.save(account: "test-account", data: first)
        try helper.save(account: "test-account", data: second)

        let loaded = try helper.load(account: "test-account")
        XCTAssertEqual(loaded, second)
    }

    func testDelete_removesData() throws {
        try helper.save(account: "test-account", data: "x".data(using: .utf8)!)
        try helper.delete(account: "test-account")
        let loaded = try helper.load(account: "test-account")
        XCTAssertNil(loaded)
    }

    func testDelete_nonExistentDoesNotThrow() throws {
        XCTAssertNoThrow(try helper.delete(account: "non-existent"))
    }
}
```

- [ ] **Step 2: test 実行 → fail 確認**

Expected: FAIL (KeychainHelper 未定義)

- [ ] **Step 3: KeychainHelper.swift 実装**

`App/Storage/KeychainHelper.swift`:

```swift
import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
}

struct KeychainHelper {
    let service: String
    let accessGroup: String?

    init(service: String = "com.kureho.adblockkeshi.report.uuid",
         accessGroup: String? = "L455WPL8QZ.group.com.kureho.adblockkeshi.shared") {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group = accessGroup {
            q[kSecAttrAccessGroup as String] = group
        }
        return q
    }

    func save(account: String, data: Data) throws {
        // upsert: 既存があれば update、無ければ add
        var query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)

        switch status {
        case errSecSuccess:
            return ref as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

- [ ] **Step 4: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/KeychainHelperTests
```

Expected: 5 tests passed

- [ ] **Step 5: DeviceUUIDStore failing test 書く**

`Tests/App/Storage/DeviceUUIDStoreTests.swift`:

```swift
import XCTest
import CryptoKit
@testable import AdblockKeshi

final class DeviceUUIDStoreTests: XCTestCase {
    private var helper: KeychainHelper!
    private var store: DeviceUUIDStore!

    override func setUp() {
        super.setUp()
        let service = "test.uuid.\(UUID().uuidString)"
        helper = KeychainHelper(service: service, accessGroup: nil)
        store = DeviceUUIDStore(keychain: helper, serverSalt: "test-salt-XYZ")
    }

    override func tearDown() {
        try? helper.delete(account: DeviceUUIDStore.account)
        super.tearDown()
    }

    func testGetUUID_firstCall_generatesNewUUID() throws {
        let uuid = try store.getUUID()
        XCTAssertNotNil(UUID(uuidString: uuid))
    }

    func testGetUUID_secondCall_returnsSameUUID() throws {
        let first = try store.getUUID()
        let second = try store.getUUID()
        XCTAssertEqual(first, second)
    }

    func testGetUUID_persistsAcrossInstances() throws {
        let first = try store.getUUID()
        let newStore = DeviceUUIDStore(keychain: helper, serverSalt: "test-salt-XYZ")
        let second = try newStore.getUUID()
        XCTAssertEqual(first, second)
    }

    func testGetUUIDHash_returns64HexChars() throws {
        let hash = try store.getUUIDHash()
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testGetUUIDHash_deterministic_sameSalt() throws {
        let h1 = try store.getUUIDHash()
        let h2 = try store.getUUIDHash()
        XCTAssertEqual(h1, h2)
    }

    func testGetUUIDHash_differentSalt_differentHash() throws {
        let store2 = DeviceUUIDStore(keychain: helper, serverSalt: "different-salt")
        let h1 = try store.getUUIDHash()
        let h2 = try store2.getUUIDHash()
        XCTAssertNotEqual(h1, h2)
    }

    func testGetUUIDHash_matchesManualSHA256() throws {
        let uuid = try store.getUUID()
        let expected = sha256Hex("\(uuid):test-salt-XYZ")
        let actual = try store.getUUIDHash()
        XCTAssertEqual(actual, expected)
    }

    func testReset_generatesNewUUIDOnNextCall() throws {
        let first = try store.getUUID()
        try store.reset()
        let second = try store.getUUID()
        XCTAssertNotEqual(first, second)
    }

    private func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Character {
    var isHexDigit: Bool {
        return isHexDigit  // SwiftStdlib provides this
    }
}
```

- [ ] **Step 6: test 実行 → fail 確認**

Expected: FAIL (DeviceUUIDStore 未定義)

- [ ] **Step 7: DeviceUUIDStore.swift 実装**

`App/Storage/DeviceUUIDStore.swift`:

```swift
import Foundation
import CryptoKit

struct DeviceUUIDStore {
    static let account = "device-uuid"

    private let keychain: KeychainHelper
    private let serverSalt: String

    init(keychain: KeychainHelper = KeychainHelper(),
         serverSalt: String) {
        self.keychain = keychain
        self.serverSalt = serverSalt
    }

    /// Phase 2 で読み込む server_salt の取得経路。Phase 5 で feature-flags.json 経由に変更。
    static func loadServerSaltFromBundle() -> String {
        guard let salt = Bundle.main.object(forInfoDictionaryKey: "DEV_SERVER_SALT") as? String,
              !salt.isEmpty else {
            assertionFailure("DEV_SERVER_SALT not set in Info.plist (Phase 2 only)")
            return "placeholder-salt-phase2"
        }
        return salt
    }

    /// 既存 UUID を読み込み、なければ生成して Keychain に保存。
    func getUUID() throws -> String {
        if let data = try keychain.load(account: Self.account),
           let uuid = String(data: data, encoding: .utf8) {
            return uuid
        }
        let newUUID = UUID().uuidString
        try keychain.save(account: Self.account, data: newUUID.data(using: .utf8)!)
        return newUUID
    }

    /// `SHA-256("\(uuid):\(serverSalt)")` の hex (64 文字小文字)
    func getUUIDHash() throws -> String {
        let uuid = try getUUID()
        let input = "\(uuid):\(serverSalt)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// テスト用 or kureho 経由のリセット (再現問題報告時)
    func reset() throws {
        try keychain.delete(account: Self.account)
    }
}
```

- [ ] **Step 8: project.yml の `Info.plist properties` に `DEV_SERVER_SALT` を追加** (debug 用)

```yaml
  AdblockKeshi:
    ...
    info:
      properties:
        ...
        DEV_SERVER_SALT: "phase2-dev-salt-do-not-use-in-prod"
```

xcodegen 再実行。

- [ ] **Step 9: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/DeviceUUIDStoreTests
```

Expected: 7 tests passed (testGetUUIDHash_matchesManualSHA256 も含む)

- [ ] **Step 10: commit**

```bash
git add App/Storage/KeychainHelper.swift App/Storage/DeviceUUIDStore.swift \
        Tests/App/Storage/KeychainHelperTests.swift Tests/App/Storage/DeviceUUIDStoreTests.swift \
        project.yml
git commit -m "feat(v3): add DeviceUUIDStore + KeychainHelper for app-group-shared device UUID

spec §2 §3: UUID Keychain-only, SHA-256(uuid:salt) sent to server.
- KeychainHelper: upsert/load/delete CRUD with app group accessGroup
- DeviceUUIDStore: lazy UUID generation, hex-encoded SHA-256 hash
- Phase 2: salt from Info.plist (DEV_SERVER_SALT), Phase 5 switches to feature-flags.json"
```

### Task 4.3: HMACTokenStore (token caching, thread-safe) TDD

ephemeral HMAC token は 5 分有効。連続報告時に毎回 `/v1/reports/token` を叩くと帯域・rate limit 損失。scope ごとにキャッシュ。

**Files:**
- Create: `App/Networking/HMACTokenStore.swift`
- Create: `Tests/App/Networking/HMACTokenStoreTests.swift`

#### 仕様詳細

| 項目 | 値 |
|---|---|
| 保存先 | in-memory (起動間で持ち越さず、毎セッション再取得) |
| キー | `TokenScope` enum (`.submit`, `.history`, `.delete`) |
| 有効性判定 | `expiresAt > Date() + 30秒` (clock skew 余裕 30 秒) |
| thread safety | `actor HMACTokenStore` で隔離 |
| 失敗時の状態 | キャッシュ無し、次回 API 取得 |

- [ ] **Step 1: TokenScope と HMACToken 型定義 (まず型から)**

`App/Networking/HMACTokenStore.swift` の先頭部分:

```swift
import Foundation

enum TokenScope: String, Codable, CaseIterable {
    case submit
    case history
    case delete
}

struct HMACToken: Equatable, Codable {
    let value: String                  // signed token string
    let scope: TokenScope
    let expiresAt: Date

    func isValid(now: Date = Date(), skew: TimeInterval = 30) -> Bool {
        return expiresAt > now.addingTimeInterval(skew)
    }
}
```

- [ ] **Step 2: Failing test**

`Tests/App/Networking/HMACTokenStoreTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class HMACTokenStoreTests: XCTestCase {
    func testStore_initiallyEmpty() async {
        let store = HMACTokenStore()
        let token = await store.get(scope: .submit)
        XCTAssertNil(token)
    }

    func testStore_saveAndGet() async {
        let store = HMACTokenStore()
        let token = HMACToken(
            value: "abc.def",
            scope: .submit,
            expiresAt: Date().addingTimeInterval(300)
        )
        await store.set(token)
        let loaded = await store.get(scope: .submit)
        XCTAssertEqual(loaded, token)
    }

    func testStore_returnsNilForExpiredToken() async {
        let store = HMACTokenStore()
        let expiredToken = HMACToken(
            value: "old.token",
            scope: .submit,
            expiresAt: Date().addingTimeInterval(-60)
        )
        await store.set(expiredToken)
        let loaded = await store.get(scope: .submit)
        XCTAssertNil(loaded, "Expired token should not be returned")
    }

    func testStore_returnsNilForNearExpiryToken_skewBuffer() async {
        let store = HMACTokenStore()
        // 残り 20 秒 = skew 30 秒以下 → 無効扱い
        let token = HMACToken(
            value: "near-expiry",
            scope: .submit,
            expiresAt: Date().addingTimeInterval(20)
        )
        await store.set(token)
        let loaded = await store.get(scope: .submit)
        XCTAssertNil(loaded, "Token within skew buffer should be invalid")
    }

    func testStore_scopeKeyed() async {
        let store = HMACTokenStore()
        let submitToken = HMACToken(value: "s.token", scope: .submit, expiresAt: Date().addingTimeInterval(300))
        let historyToken = HMACToken(value: "h.token", scope: .history, expiresAt: Date().addingTimeInterval(300))

        await store.set(submitToken)
        await store.set(historyToken)

        let s = await store.get(scope: .submit)
        let h = await store.get(scope: .history)
        let d = await store.get(scope: .delete)

        XCTAssertEqual(s, submitToken)
        XCTAssertEqual(h, historyToken)
        XCTAssertNil(d)
    }

    func testStore_invalidateRemovesToken() async {
        let store = HMACTokenStore()
        let token = HMACToken(value: "abc", scope: .submit, expiresAt: Date().addingTimeInterval(300))
        await store.set(token)
        await store.invalidate(scope: .submit)
        let loaded = await store.get(scope: .submit)
        XCTAssertNil(loaded)
    }

    func testStore_concurrentReadsAreThreadSafe() async {
        let store = HMACTokenStore()
        let token = HMACToken(value: "concurrent", scope: .submit, expiresAt: Date().addingTimeInterval(300))
        await store.set(token)

        await withTaskGroup(of: HMACToken?.self) { group in
            for _ in 0..<50 {
                group.addTask { await store.get(scope: .submit) }
            }
            var results: [HMACToken?] = []
            for await result in group { results.append(result) }
            XCTAssertEqual(results.compactMap { $0 }.count, 50)
        }
    }
}
```

- [ ] **Step 3: test 実行 → fail 確認**

Expected: FAIL (HMACTokenStore actor 未定義)

- [ ] **Step 4: HMACTokenStore actor 実装**

`App/Networking/HMACTokenStore.swift` に追加:

```swift
actor HMACTokenStore {
    private var tokens: [TokenScope: HMACToken] = [:]

    func get(scope: TokenScope) -> HMACToken? {
        guard let token = tokens[scope], token.isValid() else {
            tokens.removeValue(forKey: scope)
            return nil
        }
        return token
    }

    func set(_ token: HMACToken) {
        tokens[token.scope] = token
    }

    func invalidate(scope: TokenScope) {
        tokens.removeValue(forKey: scope)
    }

    func invalidateAll() {
        tokens.removeAll()
    }
}
```

- [ ] **Step 5: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/HMACTokenStoreTests
```

Expected: 7 tests passed (concurrent も)

- [ ] **Step 6: commit**

```bash
git add App/Networking/HMACTokenStore.swift Tests/App/Networking/HMACTokenStoreTests.swift
git commit -m "feat(v3): add HMACTokenStore (actor) with scope-keyed cache + 30s skew

- ephemeral 5min tokens, in-memory only, per-scope
- skew buffer for near-expiry rejection
- thread-safe via actor isolation"
```

### Task 4.4: APIError + Workers レスポンス型定義 (TDD)

API 通信の error 型と Workers レスポンス DTO を独立 module に。

**Files:**
- Create: `App/Networking/APIError.swift`
- Create: `App/Networking/WorkersResponseDTO.swift`
- Create: `Tests/App/Networking/APIErrorTests.swift`
- Create: `Tests/App/Networking/WorkersResponseDTOTests.swift`
- Create: `Tests/Fixtures/workers_responses/submit_success.json`
- Create: `Tests/Fixtures/workers_responses/submit_rate_limited.json`
- Create: `Tests/Fixtures/workers_responses/token_response.json`

- [ ] **Step 1: Fixture 作成**

`Tests/Fixtures/workers_responses/submit_success.json`:

```json
{
  "id": "01HYZ1234567890ABCDEFGHIJK",
  "status": "pending",
  "received_at": 1718000000,
  "memo_redacted": false
}
```

`Tests/Fixtures/workers_responses/submit_rate_limited.json`:

```json
{
  "error": "rate_limit_exceeded",
  "message": "1日5件の上限に達しました。明日また送信できます。",
  "retry_after": 86400
}
```

`Tests/Fixtures/workers_responses/token_response.json`:

```json
{
  "token": "eyJzdWJqZWN0IjoiYWJjMTIzIiwiZXhwaXJlcyI6MTcxODAwMDMwMDAwMCwic2NvcGUiOiJzdWJtaXQifQ==.signature_base64",
  "expires_at": 1718000300,
  "server_salt": "phase2-server-salt-value"
}
```

- [ ] **Step 2: APIError test**

`Tests/App/Networking/APIErrorTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class APIErrorTests: XCTestCase {
    func testNetworkUnavailable_localizedDescription() {
        let err = APIError.networkUnavailable
        XCTAssertTrue(err.localizedDescription.contains("インターネット") || err.localizedDescription.contains("接続"))
    }

    func testRateLimitExceeded_includesRetryAfter() {
        let err = APIError.rateLimitExceeded(retryAfter: 86400)
        XCTAssertTrue(err.localizedDescription.contains("上限") || err.localizedDescription.contains("明日"))
    }

    func testValidationFailed_includesField() {
        let err = APIError.validationFailed(field: "url", reason: "invalid_format")
        XCTAssertTrue(err.localizedDescription.contains("url") || err.localizedDescription.contains("URL"))
    }

    func testServerError_5xxIsRetryable() {
        XCTAssertTrue(APIError.serverError(statusCode: 500, body: nil).isRetryable)
        XCTAssertTrue(APIError.serverError(statusCode: 503, body: nil).isRetryable)
    }

    func testServerError_4xxIsNotRetryable() {
        XCTAssertFalse(APIError.serverError(statusCode: 400, body: nil).isRetryable)
        XCTAssertFalse(APIError.serverError(statusCode: 404, body: nil).isRetryable)
    }

    func testRateLimitIsNotRetryable_inShortTerm() {
        XCTAssertFalse(APIError.rateLimitExceeded(retryAfter: 86400).isRetryable)
    }

    func testNetworkErrorIsRetryable() {
        XCTAssertTrue(APIError.networkUnavailable.isRetryable)
    }
}
```

- [ ] **Step 3: APIError 実装**

`App/Networking/APIError.swift`:

```swift
import Foundation

enum APIError: LocalizedError {
    case networkUnavailable
    case rateLimitExceeded(retryAfter: TimeInterval)
    case validationFailed(field: String, reason: String)
    case turnstileVerificationFailed
    case unauthorized                      // token verify failed
    case banned(level: Int, expiresAt: Date)
    case serverError(statusCode: Int, body: Data?)
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "インターネット接続を確認してください"
        case .rateLimitExceeded(let after):
            let hours = Int(after / 3600)
            if hours >= 24 {
                return "1 日の上限に達しました。明日また送信できます"
            } else if hours >= 1 {
                return "送信間隔の上限に達しました。\(hours) 時間後にお試しください"
            } else {
                return "送信間隔が短すぎます。少し時間を空けてください"
            }
        case .validationFailed(let field, let reason):
            return "入力エラー (\(field)): \(reason)"
        case .turnstileVerificationFailed:
            return "確認に失敗しました。もう一度お試しください"
        case .unauthorized:
            return "認証エラーです。アプリを再起動してください"
        case .banned(let level, _):
            return "報告機能が一時的に制限されています (level \(level))"
        case .serverError(let code, _):
            return "サーバエラー (HTTP \(code))。少し時間を空けて再試行してください"
        case .decodingFailed:
            return "サーバの応答を解釈できませんでした"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .serverError(let code, _) where (500...599).contains(code):
            return true
        case .serverError:
            return false
        case .rateLimitExceeded, .validationFailed, .turnstileVerificationFailed,
             .unauthorized, .banned, .decodingFailed:
            return false
        }
    }
}
```

- [ ] **Step 4: WorkersResponseDTO test と実装**

`Tests/App/Networking/WorkersResponseDTOTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class WorkersResponseDTOTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle(for: type(of: self)).url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures/workers_responses"
        ) else { throw XCTSkip("missing fixture") }
        return try Data(contentsOf: url)
    }

    func testTokenResponse_decode() throws {
        let data = try loadFixture("token_response")
        let dto = try JSONDecoder().decode(TokenResponseDTO.self, from: data)
        XCTAssertFalse(dto.token.isEmpty)
        XCTAssertEqual(dto.expiresAt, Date(timeIntervalSince1970: 1718000300))
        XCTAssertEqual(dto.serverSalt, "phase2-server-salt-value")
    }

    func testSubmitSuccessResponse_decode() throws {
        let data = try loadFixture("submit_success")
        let dto = try JSONDecoder().decode(SubmitResponseDTO.self, from: data)
        XCTAssertEqual(dto.id, "01HYZ1234567890ABCDEFGHIJK")
        XCTAssertEqual(dto.status, "pending")
        XCTAssertFalse(dto.memoRedacted)
    }

    func testRateLimitErrorResponse_decode() throws {
        let data = try loadFixture("submit_rate_limited")
        let dto = try JSONDecoder().decode(APIErrorResponseDTO.self, from: data)
        XCTAssertEqual(dto.error, "rate_limit_exceeded")
        XCTAssertNotNil(dto.retryAfter)
        XCTAssertEqual(dto.retryAfter, 86400)
    }
}
```

`App/Networking/WorkersResponseDTO.swift`:

```swift
import Foundation

// MARK: - Request DTOs

struct TokenRequestDTO: Encodable {
    let turnstileResponse: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case turnstileResponse = "turnstile_response"
        case scope
    }
}

struct SubmitRequestDTO: Encodable {
    let token: String
    let uuidHash: String
    let url: String
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
        case url, memo
    }
}

struct HistoryRequestDTO: Encodable {
    let token: String
    let uuidHash: String

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
    }
}

struct DeletionRequestDTO: Encodable {
    let token: String
    let uuidHash: String
    let urlPathHash: String?

    enum CodingKeys: String, CodingKey {
        case token
        case uuidHash = "uuid_hash"
        case urlPathHash = "url_path_hash"
    }
}

// MARK: - Response DTOs

struct TokenResponseDTO: Decodable {
    let token: String
    let expiresAt: Date
    let serverSalt: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case serverSalt = "server_salt"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.token = try c.decode(String.self, forKey: .token)
        self.expiresAt = Date(timeIntervalSince1970: TimeInterval(try c.decode(Int64.self, forKey: .expiresAt)))
        self.serverSalt = try c.decode(String.self, forKey: .serverSalt)
    }
}

struct SubmitResponseDTO: Decodable {
    let id: String
    let status: String
    let receivedAt: Date
    let memoRedacted: Bool

    enum CodingKeys: String, CodingKey {
        case id, status
        case receivedAt = "received_at"
        case memoRedacted = "memo_redacted"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.status = try c.decode(String.self, forKey: .status)
        self.receivedAt = Date(timeIntervalSince1970: TimeInterval(try c.decode(Int64.self, forKey: .receivedAt)))
        self.memoRedacted = try c.decode(Bool.self, forKey: .memoRedacted)
    }
}

struct APIErrorResponseDTO: Decodable {
    let error: String
    let message: String
    let retryAfter: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case error, message
        case retryAfter = "retry_after"
    }
}
```

- [ ] **Step 5: test pass + commit**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/APIErrorTests \
                   -only-testing:AdblockKeshiTests/WorkersResponseDTOTests

git add App/Networking/APIError.swift App/Networking/WorkersResponseDTO.swift \
        Tests/App/Networking/APIErrorTests.swift Tests/App/Networking/WorkersResponseDTOTests.swift \
        Tests/Fixtures/workers_responses/submit_success.json \
        Tests/Fixtures/workers_responses/submit_rate_limited.json \
        Tests/Fixtures/workers_responses/token_response.json
git commit -m "feat(v3): add APIError + Workers DTOs

- APIError: 8 cases with Japanese localizedDescription
- isRetryable for backoff logic
- Encodable request DTOs + Decodable response DTOs
- Fixtures for token/submit success+rate_limit"
```

### Task 4.5: ReportAPIClientProtocol + Mock URLProtocol テストハーネス

URLSession を直接 inject せず、`URLProtocol` カスタム実装で test request を intercept する。これは Apple 公式パターン。

**Files:**
- Create: `App/Networking/ReportAPIClient.swift`
- Create: `Tests/App/Networking/MockURLProtocol.swift`
- Create: `Tests/App/Networking/ReportAPIClientTests.swift`

#### 仕様詳細

| 観点 | 仕様 |
|---|---|
| baseURL | Phase 2 = `https://adblockkeshi-reports.kureho.workers.dev` (Phase 5 で feature-flags.json) |
| timeout | 連結 timeout 30 秒、データ受信 60 秒 |
| Content-Type | `application/json` |
| Accept | `application/json` |
| User-Agent | `AdblockKeshi/3.0 (iOS)` |
| 認証 | token は body に含める (header ではない、IDOR 防止) |

- [ ] **Step 1: ReportAPIClientProtocol 定義**

`App/Networking/ReportAPIClient.swift` の先頭:

```swift
import Foundation

protocol ReportAPIClientProtocol {
    func requestToken(turnstileResponse: String, scope: TokenScope) async throws -> (HMACToken, String /* server_salt */)
    func submitReport(url: URL, memo: String?) async throws -> SubmitResponseDTO
    func fetchHistory() async throws -> ReportHistoryResponse
    func requestDeletion(urlPathHash: String?) async throws
}
```

- [ ] **Step 2: MockURLProtocol 作成 (test 用 stub)**

`Tests/App/Networking/MockURLProtocol.swift`:

```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
    static var receivedRequests: [URLRequest] = []

    static func reset() {
        requestHandler = nil
        receivedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }
        MockURLProtocol.receivedRequests.append(request)
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static func makeMocked() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 3: ReportAPIClient failing test (token request)**

`Tests/App/Networking/ReportAPIClientTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class ReportAPIClientTests: XCTestCase {
    private var session: URLSession!
    private var uuidStore: DeviceUUIDStore!
    private var tokenStore: HMACTokenStore!
    private var client: ReportAPIClient!
    private let baseURL = URL(string: "https://test.workers.dev")!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = URLSession.makeMocked()
        let keychain = KeychainHelper(service: "test.api.client.\(UUID())", accessGroup: nil)
        uuidStore = DeviceUUIDStore(keychain: keychain, serverSalt: "test-salt")
        tokenStore = HMACTokenStore()
        client = ReportAPIClient(
            baseURL: baseURL,
            session: session,
            uuidStore: uuidStore,
            tokenStore: tokenStore
        )
    }

    func testRequestToken_postsCorrectBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://test.workers.dev/v1/reports/token")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = self.bodyOfRequest(request)
            let dto = try JSONDecoder().decode(TokenRequestDTO.self, from: body)
            XCTAssertEqual(dto.turnstileResponse, "tr-response-123")
            XCTAssertEqual(dto.scope, "submit")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let respData = """
            {"token":"abc.def","expires_at":\(Int(Date().timeIntervalSince1970) + 300),"server_salt":"new-salt"}
            """.data(using: .utf8)!
            return (response, respData)
        }

        let (token, salt) = try await client.requestToken(turnstileResponse: "tr-response-123", scope: .submit)
        XCTAssertEqual(token.value, "abc.def")
        XCTAssertEqual(token.scope, .submit)
        XCTAssertTrue(token.isValid())
        XCTAssertEqual(salt, "new-salt")
    }

    func testRequestToken_400_throwsTurnstileFailed() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let body = """
            {"error":"turnstile_failed","message":"verification failed"}
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.requestToken(turnstileResponse: "bad", scope: .submit)
            XCTFail("Expected throw")
        } catch let error as APIError {
            if case .turnstileVerificationFailed = error {
                // expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSubmitReport_postsTokenAndUUIDHashAndURL() async throws {
        // 既に submit token がキャッシュにある状態
        let cachedToken = HMACToken(value: "cached.token", scope: .submit, expiresAt: Date().addingTimeInterval(300))
        await tokenStore.set(cachedToken)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/reports/submit")
            let body = self.bodyOfRequest(request)
            let dto = try JSONDecoder().decode(SubmitRequestDTO.self, from: body)
            XCTAssertEqual(dto.token, "cached.token")
            XCTAssertEqual(dto.url, "https://example.com/article")
            XCTAssertEqual(dto.memo, "オーバーレイ広告")
            XCTAssertFalse(dto.uuidHash.isEmpty)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let respData = """
            {"id":"01HYZ","status":"pending","received_at":\(Int(Date().timeIntervalSince1970)),"memo_redacted":false}
            """.data(using: .utf8)!
            return (response, respData)
        }

        let result = try await client.submitReport(url: URL(string: "https://example.com/article")!, memo: "オーバーレイ広告")
        XCTAssertEqual(result.id, "01HYZ")
        XCTAssertEqual(result.status, "pending")
    }

    func testSubmitReport_429_throwsRateLimit() async {
        let cachedToken = HMACToken(value: "t", scope: .submit, expiresAt: Date().addingTimeInterval(300))
        await tokenStore.set(cachedToken)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            let body = """
            {"error":"rate_limit_exceeded","message":"daily limit","retry_after":86400}
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.submitReport(url: URL(string: "https://x.com")!, memo: nil)
            XCTFail("Expected throw")
        } catch let error as APIError {
            if case .rateLimitExceeded(let after) = error {
                XCTAssertEqual(after, 86400)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchHistory_sendsTokenAndUUIDHash() async throws {
        let cachedToken = HMACToken(value: "h.token", scope: .history, expiresAt: Date().addingTimeInterval(300))
        await tokenStore.set(cachedToken)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/reports/history")
            let body = self.bodyOfRequest(request)
            let dto = try JSONDecoder().decode(HistoryRequestDTO.self, from: body)
            XCTAssertEqual(dto.token, "h.token")
            XCTAssertFalse(dto.uuidHash.isEmpty)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let respData = """
            {"items":[],"fetched_at":\(Int(Date().timeIntervalSince1970))}
            """.data(using: .utf8)!
            return (response, respData)
        }

        let result = try await client.fetchHistory()
        XCTAssertEqual(result.items.count, 0)
    }

    func testRequestToken_networkUnavailable_throwsNetworkError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await client.requestToken(turnstileResponse: "x", scope: .submit)
            XCTFail("Expected throw")
        } catch let error as APIError {
            if case .networkUnavailable = error {
                // expected
            } else {
                XCTFail("Wrong: \(error)")
            }
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // helper: HTTPBodyStream を Data に変換
    private func bodyOfRequest(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        var data = Data()
        stream.open()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate(); stream.close() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

- [ ] **Step 4: test 実行 → fail 確認** (ReportAPIClient 未実装)

- [ ] **Step 5: ReportAPIClient 本体実装**

`App/Networking/ReportAPIClient.swift` に追加:

```swift
final class ReportAPIClient: ReportAPIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let uuidStore: DeviceUUIDStore
    private let tokenStore: HMACTokenStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL,
         session: URLSession = .shared,
         uuidStore: DeviceUUIDStore,
         tokenStore: HMACTokenStore = HMACTokenStore()) {
        self.baseURL = baseURL
        self.session = session
        self.uuidStore = uuidStore
        self.tokenStore = tokenStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func requestToken(turnstileResponse: String, scope: TokenScope) async throws -> (HMACToken, String) {
        let url = baseURL.appendingPathComponent("/v1/reports/token")
        var request = makeBaseRequest(url: url)
        let body = TokenRequestDTO(turnstileResponse: turnstileResponse, scope: scope.rawValue)
        request.httpBody = try encoder.encode(body)

        let dto: TokenResponseDTO = try await send(request, decodingErrorFor: .turnstileVerificationFailed)
        let token = HMACToken(value: dto.token, scope: scope, expiresAt: dto.expiresAt)
        await tokenStore.set(token)
        return (token, dto.serverSalt)
    }

    func submitReport(url: URL, memo: String?) async throws -> SubmitResponseDTO {
        let token = try await acquireToken(scope: .submit)
        let uuidHash = try uuidStore.getUUIDHash()
        let endpoint = baseURL.appendingPathComponent("/v1/reports/submit")
        var request = makeBaseRequest(url: endpoint)
        let body = SubmitRequestDTO(token: token.value, uuidHash: uuidHash, url: url.absoluteString, memo: memo)
        request.httpBody = try encoder.encode(body)
        return try await send(request, decodingErrorFor: nil)
    }

    func fetchHistory() async throws -> ReportHistoryResponse {
        let token = try await acquireToken(scope: .history)
        let uuidHash = try uuidStore.getUUIDHash()
        let endpoint = baseURL.appendingPathComponent("/v1/reports/history")
        var request = makeBaseRequest(url: endpoint)
        let body = HistoryRequestDTO(token: token.value, uuidHash: uuidHash)
        request.httpBody = try encoder.encode(body)
        return try await send(request, decodingErrorFor: nil)
    }

    func requestDeletion(urlPathHash: String?) async throws {
        let token = try await acquireToken(scope: .delete)
        let uuidHash = try uuidStore.getUUIDHash()
        let endpoint = baseURL.appendingPathComponent("/v1/reports/delete")
        var request = makeBaseRequest(url: endpoint)
        let body = DeletionRequestDTO(token: token.value, uuidHash: uuidHash, urlPathHash: urlPathHash)
        request.httpBody = try encoder.encode(body)
        let _: SubmitResponseDTO? = try? await send(request, decodingErrorFor: nil)
    }

    // MARK: - private

    private func acquireToken(scope: TokenScope) async throws -> HMACToken {
        if let cached = await tokenStore.get(scope: scope) { return cached }
        // Phase 2 では Turnstile 連携が UI 側に無い場合のフォールバック:
        // テスト時は事前に tokenStore に set される、本番は ReportFormView 経由で
        // Turnstile WebView 完了後 requestToken 呼び出し済みであることが前提。
        throw APIError.unauthorized
    }

    private func makeBaseRequest(url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("AdblockKeshi/3.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func send<T: Decodable>(_ request: URLRequest, decodingErrorFor specificError: APIError?) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.networkUnavailable
            }
            switch http.statusCode {
            case 200..<300:
                do { return try decoder.decode(T.self, from: data) }
                catch { throw APIError.decodingFailed(underlying: error) }
            case 400:
                if let err = specificError { throw err }
                throw try APIError.fromBody(data: data, statusCode: 400)
            case 401, 403:
                throw APIError.unauthorized
            case 429:
                throw try APIError.fromBody(data: data, statusCode: 429)
            case 500..<600:
                throw APIError.serverError(statusCode: http.statusCode, body: data)
            default:
                throw APIError.serverError(statusCode: http.statusCode, body: data)
            }
        } catch let urlError as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code) {
            throw APIError.networkUnavailable
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.decodingFailed(underlying: error)
        }
    }
}

extension APIError {
    static func fromBody(data: Data, statusCode: Int) throws -> APIError {
        let dto = try JSONDecoder().decode(APIErrorResponseDTO.self, from: data)
        switch dto.error {
        case "turnstile_failed": return .turnstileVerificationFailed
        case "rate_limit_exceeded": return .rateLimitExceeded(retryAfter: dto.retryAfter ?? 3600)
        case "validation_failed": return .validationFailed(field: "url", reason: dto.message)
        case "banned": return .banned(level: 1, expiresAt: Date(timeIntervalSinceNow: dto.retryAfter ?? 86400))
        default: return .serverError(statusCode: statusCode, body: data)
        }
    }
}
```

- [ ] **Step 6: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportAPIClientTests 2>&1 | tail -20
```

Expected: 6 tests passed

- [ ] **Step 7: commit**

```bash
git add App/Networking/ReportAPIClient.swift Tests/App/Networking/MockURLProtocol.swift \
        Tests/App/Networking/ReportAPIClientTests.swift
git commit -m "feat(v3): add ReportAPIClient with URLProtocol-based test harness

- Protocol-oriented ReportAPIClientProtocol (history tests already use it)
- POST-only API, JSON body, no token in headers (IDOR防止)
- HMAC token cache integration (acquireToken)
- APIError.fromBody mapping for 400/429/banned response shapes
- 6 test cases covering token/submit/history/network/rate limit/turnstile"
```

### Task 4.6: ReportFormView を APIClient に接続 (TDD + シミュレータ確認)

Chunk 3 で作った ReportFormView の送信処理を実 API client に差し替え。Turnstile WebView 連携は Phase 2 では「open-text Turnstile site key で UI integration test」、Phase 5 で本番化。

**Files:**
- Modify: `App/ReportTab/ReportFormView.swift`
- Modify: `App/ReportTab/ReportFormViewModel.swift` (新規 or 既存修正、Chunk 3 で先に作る前提)

- [ ] **Step 1: ReportFormViewModel の failing test (submit 成功シナリオ)**

```swift
@MainActor
final class ReportFormViewModelTests: XCTestCase {
    func testSubmit_success_callsOnSuccess() async {
        let api = MockReportAPIClient()
        api.stubSubmitResult = .success(SubmitResponseDTO(
            id: "01HYZ", status: "pending",
            receivedAt: Date(), memoRedacted: false
        ))
        var successCalled = false
        let vm = ReportFormViewModel(apiClient: api, onSuccess: { successCalled = true })
        vm.url = "https://example.com/a"
        vm.memo = "test"
        await vm.submit()
        XCTAssertTrue(successCalled)
        XCTAssertEqual(vm.state, .idle)
    }
    // 他: error, validating, rate limit, 等
}
```

- [ ] **Step 2-5: 実装、シミュレータでフォーム送信 → Sent 遷移確認、commit**

### Task 4.7: Chunk 4 完了確認 + PR

- [ ] **Step 1**: 全 test pass、シミュレータ E2E (フォーム → 送信 → Sent → 履歴で表示確認)、PR 作成、kureho 承認後 merge

### Chunk 4 完了 → 次は Chunk 5 (履歴 UI、既に詳細化済み)

---

## Chunk 5: Phase 2 - 履歴 UI (Tab B Sub-screen)

**目的: 自分の報告履歴を Tab B から閲覧できる UI、ステータスバッジ 5 種と PII redact 注記バッジを実装。空状態 / loading / error / pull-to-refresh / キャッシュ + background fetch を完備**。

### Task 5.1: 子ブランチ `feat/v3-history-ui` 切る

**Files:**
- Modify: 既存 git 状態のみ

- [ ] **Step 1: 親ブランチへ checkout + 最新化**

```bash
cd /Users/oharakureho/claude/AdblockKeshi
git checkout feature/v3.0-learning-adblock
git pull origin feature/v3.0-learning-adblock
git log --oneline -5
```

Expected: Chunk 4 の commit が反映されている (`feat/v3-device-uuid-and-api-client` PR merge 済)

- [ ] **Step 2: 子ブランチ `feat/v3-history-ui` 作成**

```bash
git checkout -b feat/v3-history-ui
git status
```

Expected: `On branch feat/v3-history-ui`、clean working tree

### Task 5.2: ReportStatus enum と Codable 型定義 (TDD)

履歴 UI のステータスは spec §2 で定義: `pending` / `validating` / `approved` / `rejected_no_ad_detected` / `rejected_safety_gate`。Workers レスポンスとの JSON 互換が必要。

**Files:**
- Create: `App/Models/ReportStatus.swift`
- Create: `App/Models/ReportHistoryItem.swift`
- Create: `Tests/App/Models/ReportStatusTests.swift`
- Create: `Tests/App/Models/ReportHistoryItemTests.swift`
- Create: `Tests/Fixtures/workers_responses/history_with_items.json`
- Create: `Tests/Fixtures/workers_responses/history_empty.json`

- [ ] **Step 1: Failing test を書く (ReportStatusTests)**

`Tests/App/Models/ReportStatusTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class ReportStatusTests: XCTestCase {
    func testReportStatus_decodesFromPendingString() throws {
        let json = "\"pending\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(ReportStatus.self, from: json)
        XCTAssertEqual(status, .pending)
    }

    func testReportStatus_decodesAllFiveValues() throws {
        let values: [(String, ReportStatus)] = [
            ("\"pending\"", .pending),
            ("\"validating\"", .validating),
            ("\"approved\"", .approved),
            ("\"rejected_no_ad_detected\"", .rejectedNoAdDetected),
            ("\"rejected_safety_gate\"", .rejectedSafetyGate),
        ]
        for (jsonString, expected) in values {
            let json = jsonString.data(using: .utf8)!
            let status = try JSONDecoder().decode(ReportStatus.self, from: json)
            XCTAssertEqual(status, expected, "Failed for \(jsonString)")
        }
    }

    func testReportStatus_rejectsUnknownString() {
        let json = "\"unknown_value\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ReportStatus.self, from: json))
    }

    func testReportStatus_displayLabelMatchesJapanese() {
        XCTAssertEqual(ReportStatus.pending.displayLabel, "受付済")
        XCTAssertEqual(ReportStatus.validating.displayLabel, "検証中")
        XCTAssertEqual(ReportStatus.approved.displayLabel, "反映済")
        XCTAssertEqual(ReportStatus.rejectedNoAdDetected.displayLabel, "対象外")
        XCTAssertEqual(ReportStatus.rejectedSafetyGate.displayLabel, "対象外")
    }

    func testReportStatus_badgeColorMapping() {
        XCTAssertEqual(ReportStatus.pending.badgeRole, .neutral)
        XCTAssertEqual(ReportStatus.validating.badgeRole, .info)
        XCTAssertEqual(ReportStatus.approved.badgeRole, .success)
        XCTAssertEqual(ReportStatus.rejectedNoAdDetected.badgeRole, .warning)
        XCTAssertEqual(ReportStatus.rejectedSafetyGate.badgeRole, .warning)
    }
}
```

- [ ] **Step 2: test 実行して fail 確認**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:AdblockKeshiTests/ReportStatusTests 2>&1 | tail -15
```

Expected: FAIL (ReportStatus, ReportStatusBadgeRole 未定義)

- [ ] **Step 3: ReportStatus.swift 実装**

`App/Models/ReportStatus.swift`:

```swift
import SwiftUI

enum ReportStatus: String, Codable, CaseIterable, Equatable {
    case pending
    case validating
    case approved
    case rejectedNoAdDetected = "rejected_no_ad_detected"
    case rejectedSafetyGate = "rejected_safety_gate"

    var displayLabel: String {
        switch self {
        case .pending: return "受付済"
        case .validating: return "検証中"
        case .approved: return "反映済"
        case .rejectedNoAdDetected, .rejectedSafetyGate: return "対象外"
        }
    }

    var badgeRole: BadgeRole {
        switch self {
        case .pending: return .neutral
        case .validating: return .info
        case .approved: return .success
        case .rejectedNoAdDetected, .rejectedSafetyGate: return .warning
        }
    }

    var detailDescription: String {
        switch self {
        case .pending: return "報告を受け付けました。検証開始まで最大 1 時間。"
        case .validating: return "自動検証中です。最大 7 日間で結果が出ます。"
        case .approved: return "広告ブロックリストへ反映済みです。"
        case .rejectedNoAdDetected: return "自動検証で広告を検出できませんでした。"
        case .rejectedSafetyGate: return "安全装置で除外されました (大手サイト等)。"
        }
    }
}

enum BadgeRole: Equatable {
    case neutral
    case info
    case success
    case warning

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        }
    }
}
```

- [ ] **Step 4: test pass 確認**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:AdblockKeshiTests/ReportStatusTests 2>&1 | tail -10
```

Expected: 5 tests passed

- [ ] **Step 5: ReportHistoryItem の Failing test 書く**

`Tests/Fixtures/workers_responses/history_with_items.json` を先に作成:

```json
{
  "items": [
    {
      "id": "01HYZ1234567890ABCDEFGHIJK",
      "url": "https://example.com/article/123",
      "memo": "動画上のオーバーレイ広告",
      "memo_redacted": false,
      "status": "approved",
      "created_at": 1717718400,
      "validated_at": 1717804800,
      "applied_at": 1718323200
    },
    {
      "id": "01HYZ9876543210ZYXWVUTSRQP",
      "url": "https://news.example.jp/page",
      "memo": "ヘッダー下に***-****-****が含まれていた広告",
      "memo_redacted": true,
      "status": "validating",
      "created_at": 1718064000,
      "validated_at": null,
      "applied_at": null
    },
    {
      "id": "01HYZAAAAAAAAAAAAAAAAAAAA",
      "url": "https://blog.example.org/post/1",
      "memo": null,
      "memo_redacted": false,
      "status": "rejected_no_ad_detected",
      "created_at": 1717459200,
      "validated_at": 1717545600,
      "applied_at": null
    }
  ],
  "fetched_at": 1718668800
}
```

`Tests/Fixtures/workers_responses/history_empty.json`:

```json
{
  "items": [],
  "fetched_at": 1718668800
}
```

`Tests/App/Models/ReportHistoryItemTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class ReportHistoryItemTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle(for: type(of: self)).url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures/workers_responses"
        ) else {
            throw XCTSkip("Fixture \(name).json not found in test bundle")
        }
        return try Data(contentsOf: url)
    }

    func testReportHistoryResponse_decodesThreeItems() throws {
        let data = try loadFixture("history_with_items")
        let response = try JSONDecoder().decode(ReportHistoryResponse.self, from: data)
        XCTAssertEqual(response.items.count, 3)
    }

    func testReportHistoryResponse_decodesEmpty() throws {
        let data = try loadFixture("history_empty")
        let response = try JSONDecoder().decode(ReportHistoryResponse.self, from: data)
        XCTAssertEqual(response.items.count, 0)
    }

    func testReportHistoryItem_redactedFlagPreserved() throws {
        let data = try loadFixture("history_with_items")
        let response = try JSONDecoder().decode(ReportHistoryResponse.self, from: data)
        XCTAssertTrue(response.items[1].memoRedacted)
        XCTAssertFalse(response.items[0].memoRedacted)
    }

    func testReportHistoryItem_nullMemoDecodesToNil() throws {
        let data = try loadFixture("history_with_items")
        let response = try JSONDecoder().decode(ReportHistoryResponse.self, from: data)
        XCTAssertNil(response.items[2].memo)
        XCTAssertNotNil(response.items[0].memo)
    }

    func testReportHistoryItem_createdAtDecodesAsDate() throws {
        let data = try loadFixture("history_with_items")
        let response = try JSONDecoder().decode(ReportHistoryResponse.self, from: data)
        let expected = Date(timeIntervalSince1970: 1717718400)
        XCTAssertEqual(response.items[0].createdAt, expected)
    }

    func testReportHistoryItem_appliedAtNullForNonApproved() throws {
        let data = try loadFixture("history_with_items")
        let response = try JSONDecoder().decode(ReportHistoryResponse.self, from: data)
        XCTAssertNotNil(response.items[0].appliedAt)
        XCTAssertNil(response.items[1].appliedAt)
        XCTAssertNil(response.items[2].appliedAt)
    }
}
```

- [ ] **Step 6: test 実行 → fail 確認**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:AdblockKeshiTests/ReportHistoryItemTests 2>&1 | tail -10
```

Expected: FAIL (ReportHistoryResponse / ReportHistoryItem 未定義 or Fixtures が test bundle に未登録)

- [ ] **Step 7: ReportHistoryItem.swift 実装**

`App/Models/ReportHistoryItem.swift`:

```swift
import Foundation

struct ReportHistoryResponse: Codable, Equatable {
    let items: [ReportHistoryItem]
    let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case items
        case fetchedAt = "fetched_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decode([ReportHistoryItem].self, forKey: .items)
        let ts = try container.decode(Int64.self, forKey: .fetchedAt)
        self.fetchedAt = Date(timeIntervalSince1970: TimeInterval(ts))
    }

    init(items: [ReportHistoryItem], fetchedAt: Date) {
        self.items = items
        self.fetchedAt = fetchedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(Int64(fetchedAt.timeIntervalSince1970), forKey: .fetchedAt)
    }
}

struct ReportHistoryItem: Codable, Equatable, Identifiable {
    let id: String                  // ULID from Workers
    let url: String
    let memo: String?
    let memoRedacted: Bool          // rev4 §2: redact 発火フラグ
    let status: ReportStatus
    let createdAt: Date
    let validatedAt: Date?
    let appliedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, url, memo, status
        case memoRedacted = "memo_redacted"
        case createdAt = "created_at"
        case validatedAt = "validated_at"
        case appliedAt = "applied_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.url = try container.decode(String.self, forKey: .url)
        self.memo = try container.decodeIfPresent(String.self, forKey: .memo)
        self.memoRedacted = try container.decode(Bool.self, forKey: .memoRedacted)
        self.status = try container.decode(ReportStatus.self, forKey: .status)

        let createdTs = try container.decode(Int64.self, forKey: .createdAt)
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(createdTs))

        if let validatedTs = try container.decodeIfPresent(Int64.self, forKey: .validatedAt) {
            self.validatedAt = Date(timeIntervalSince1970: TimeInterval(validatedTs))
        } else {
            self.validatedAt = nil
        }

        if let appliedTs = try container.decodeIfPresent(Int64.self, forKey: .appliedAt) {
            self.appliedAt = Date(timeIntervalSince1970: TimeInterval(appliedTs))
        } else {
            self.appliedAt = nil
        }
    }

    init(id: String, url: String, memo: String?, memoRedacted: Bool, status: ReportStatus,
         createdAt: Date, validatedAt: Date?, appliedAt: Date?) {
        self.id = id; self.url = url; self.memo = memo; self.memoRedacted = memoRedacted
        self.status = status; self.createdAt = createdAt; self.validatedAt = validatedAt; self.appliedAt = appliedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encode(memoRedacted, forKey: .memoRedacted)
        try container.encode(status, forKey: .status)
        try container.encode(Int64(createdAt.timeIntervalSince1970), forKey: .createdAt)
        try container.encodeIfPresent(validatedAt.map { Int64($0.timeIntervalSince1970) }, forKey: .validatedAt)
        try container.encodeIfPresent(appliedAt.map { Int64($0.timeIntervalSince1970) }, forKey: .appliedAt)
    }
}
```

- [ ] **Step 8: project.yml に Tests/Fixtures を test target resource として登録**

`project.yml` の `AdblockKeshiTests` target の `sources:` または `resources:` を確認・追加:

```yaml
  AdblockKeshiTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    resources:
      - path: Tests/Fixtures
```

xcodegen 再実行:

```bash
xcodegen
```

- [ ] **Step 9: test pass 確認**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:AdblockKeshiTests/ReportHistoryItemTests 2>&1 | tail -10
```

Expected: 6 tests passed

- [ ] **Step 10: commit**

```bash
git add App/Models/ReportStatus.swift App/Models/ReportHistoryItem.swift \
        Tests/App/Models/ReportStatusTests.swift Tests/App/Models/ReportHistoryItemTests.swift \
        Tests/Fixtures/workers_responses/history_with_items.json \
        Tests/Fixtures/workers_responses/history_empty.json \
        project.yml
git commit -m "feat(v3): add ReportStatus enum and ReportHistoryItem Codable models

- ReportStatus: 5 cases matching spec §2 (pending/validating/approved/rejected_*)
- BadgeRole + displayLabel + detailDescription for UI
- ReportHistoryItem with memo_redacted flag (rev4 §2)
- Fixtures for workers /v1/reports/history response shape"
```

### Task 5.3: ReportHistoryCache (UserDefaults キャッシュ) TDD

履歴 UI は「起動時 cached を即表示、background で API fetch、新しいデータで上書き」(spec §2)。
キャッシュ層を ReportHistoryCache として独立、テスト可能にする。

**Files:**
- Create: `App/Storage/ReportHistoryCache.swift`
- Create: `Tests/App/Storage/ReportHistoryCacheTests.swift`

- [ ] **Step 1: Failing test**

`Tests/App/Storage/ReportHistoryCacheTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class ReportHistoryCacheTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var cache: ReportHistoryCache!

    override func setUp() {
        super.setUp()
        suiteName = "test.report.history.cache.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        cache = ReportHistoryCache(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoad_returnsNilOnFirstLaunch() {
        XCTAssertNil(cache.load())
    }

    func testSave_persistsResponseAcrossInstances() throws {
        let response = makeFixtureResponse()
        cache.save(response)

        let cache2 = ReportHistoryCache(defaults: defaults)
        let loaded = cache2.load()

        XCTAssertEqual(loaded, response)
    }

    func testClear_removesPersistedData() throws {
        let response = makeFixtureResponse()
        cache.save(response)
        XCTAssertNotNil(cache.load())

        cache.clear()
        XCTAssertNil(cache.load())
    }

    func testSave_corruptedDataIsRecoverable() {
        // 壊れた JSON 書いてしまった場合 load が nil を返し crash しない
        defaults.set("not-valid-json".data(using: .utf8), forKey: ReportHistoryCache.cacheKey)
        XCTAssertNil(cache.load())
    }

    private func makeFixtureResponse() -> ReportHistoryResponse {
        let item = ReportHistoryItem(
            id: "01HYZ1234567890ABCDEFGHIJK",
            url: "https://example.com/x",
            memo: "test memo",
            memoRedacted: false,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1718000000),
            validatedAt: nil,
            appliedAt: nil
        )
        return ReportHistoryResponse(items: [item], fetchedAt: Date(timeIntervalSince1970: 1718001000))
    }
}
```

- [ ] **Step 2: test 実行 → fail 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportHistoryCacheTests
```

Expected: FAIL (ReportHistoryCache 未定義)

- [ ] **Step 3: ReportHistoryCache.swift 実装**

`App/Storage/ReportHistoryCache.swift`:

```swift
import Foundation

final class ReportHistoryCache {
    static let cacheKey = "v3.report.history.cache.v1"

    private let defaults: UserDefaults
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func load() -> ReportHistoryResponse? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? decoder.decode(ReportHistoryResponse.self, from: data)
    }

    func save(_ response: ReportHistoryResponse) {
        guard let data = try? encoder.encode(response) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.cacheKey)
    }
}
```

- [ ] **Step 4: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportHistoryCacheTests 2>&1 | tail -10
```

Expected: 4 tests passed

- [ ] **Step 5: commit**

```bash
git add App/Storage/ReportHistoryCache.swift Tests/App/Storage/ReportHistoryCacheTests.swift
git commit -m "feat(v3): add ReportHistoryCache for instant-load + background-refresh UX"
```

### Task 5.4: ReportHistoryItemView (1 件分の表示、status badge + redact 注記) TDD

**Files:**
- Create: `App/ReportTab/ReportHistoryItemView.swift`
- Create: `Tests/App/ReportTab/ReportHistoryItemViewTests.swift`

- [ ] **Step 1: Failing test (view inspection ベース、最小限の構造確認)**

`Tests/App/ReportTab/ReportHistoryItemViewTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import AdblockKeshi

final class ReportHistoryItemViewTests: XCTestCase {
    func testItemView_initWithApprovedStatus_setsBadgeRoleSuccess() {
        let item = makeItem(status: .approved, memoRedacted: false)
        let view = ReportHistoryItemView(item: item)
        XCTAssertEqual(view.item.status.badgeRole, .success)
    }

    func testItemView_redactedItem_setsShowsRedactBadge() {
        let item = makeItem(status: .pending, memoRedacted: true)
        let view = ReportHistoryItemView(item: item)
        XCTAssertTrue(view.shouldShowRedactBadge)
    }

    func testItemView_nonRedactedItem_hidesRedactBadge() {
        let item = makeItem(status: .pending, memoRedacted: false)
        let view = ReportHistoryItemView(item: item)
        XCTAssertFalse(view.shouldShowRedactBadge)
    }

    func testItemView_truncatesLongURL() {
        let longURL = "https://example.com/" + String(repeating: "a", count: 200)
        let item = makeItem(url: longURL, status: .pending, memoRedacted: false)
        let view = ReportHistoryItemView(item: item)
        XCTAssertLessThanOrEqual(view.displayURL.count, 60)
        XCTAssertTrue(view.displayURL.hasSuffix("..."))
    }

    func testItemView_relativeDateForRecent() {
        let recent = Date().addingTimeInterval(-3600)
        let item = makeItem(createdAt: recent, status: .pending, memoRedacted: false)
        let view = ReportHistoryItemView(item: item)
        XCTAssertTrue(view.displayDate.contains("時間") || view.displayDate.contains("分") || view.displayDate.contains("今"))
    }

    private func makeItem(url: String = "https://example.com/x",
                          createdAt: Date = Date(),
                          status: ReportStatus,
                          memoRedacted: Bool) -> ReportHistoryItem {
        ReportHistoryItem(
            id: UUID().uuidString,
            url: url,
            memo: memoRedacted ? "***-****-****" : nil,
            memoRedacted: memoRedacted,
            status: status,
            createdAt: createdAt,
            validatedAt: nil,
            appliedAt: nil
        )
    }
}
```

- [ ] **Step 2: test 実行 → fail 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportHistoryItemViewTests
```

Expected: FAIL (ReportHistoryItemView, shouldShowRedactBadge, displayURL, displayDate 未定義)

- [ ] **Step 3: ReportHistoryItemView.swift 実装**

`App/ReportTab/ReportHistoryItemView.swift`:

```swift
import SwiftUI

struct ReportHistoryItemView: View {
    let item: ReportHistoryItem

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var shouldShowRedactBadge: Bool {
        item.memoRedacted
    }

    var displayURL: String {
        let maxLen = 60
        if item.url.count <= maxLen { return item.url }
        let prefix = item.url.prefix(maxLen - 3)
        return prefix + "..."
    }

    var displayDate: String {
        relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(displayURL)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                Text(displayDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if shouldShowRedactBadge {
                    redactBadge
                }
            }

            if let memo = item.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(item.status.detailDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusBadge: some View {
        Text(item.status.displayLabel)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.status.badgeRole.color.opacity(0.15))
            .foregroundStyle(item.status.badgeRole.color)
            .clipShape(Capsule())
    }

    private var redactBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "eye.slash.fill")
                .font(.caption2)
            Text("一部伏字")
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(Color.orange)
        .clipShape(Capsule())
        .accessibilityLabel("個人情報を含む可能性があるため一部を伏せて保存しました")
    }

    private var accessibilityLabel: String {
        var parts = [displayURL, item.status.displayLabel, displayDate]
        if shouldShowRedactBadge {
            parts.append("一部伏字あり")
        }
        return parts.joined(separator: "、")
    }
}

#Preview("approved + redacted") {
    ReportHistoryItemView(item: ReportHistoryItem(
        id: "01HYZ",
        url: "https://example.com/very/long/path/that/should/be/truncated/eventually",
        memo: "下部の***-****-****の付近",
        memoRedacted: true,
        status: .approved,
        createdAt: Date().addingTimeInterval(-86400 * 3),
        validatedAt: Date().addingTimeInterval(-86400 * 2),
        appliedAt: Date().addingTimeInterval(-86400 * 1)
    ))
    .padding()
}

#Preview("pending + no memo") {
    ReportHistoryItemView(item: ReportHistoryItem(
        id: "01HYZ",
        url: "https://news.example.jp/article/1",
        memo: nil,
        memoRedacted: false,
        status: .pending,
        createdAt: Date().addingTimeInterval(-3600),
        validatedAt: nil,
        appliedAt: nil
    ))
    .padding()
}
```

- [ ] **Step 4: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportHistoryItemViewTests 2>&1 | tail -10
```

Expected: 5 tests passed

- [ ] **Step 5: シミュレータで preview 確認**

Xcode で `ReportHistoryItemView.swift` を開き、Canvas で 2 つの Preview (approved + redacted、pending + no memo) が表示されることを確認。Capsule の色、redact badge の位置、長 URL truncation が意図通りか目視。

- [ ] **Step 6: commit**

```bash
git add App/ReportTab/ReportHistoryItemView.swift Tests/App/ReportTab/ReportHistoryItemViewTests.swift
git commit -m "feat(v3): add ReportHistoryItemView with status badge + redact notice (rev4 §2)

- 5 status badges with role-mapped colors
- PII redact badge with accessible label (rev4 §2 spec)
- URL truncation at 60 chars
- Japanese relative date formatter"
```

### Task 5.5: ReportHistoryViewModel (cache + API + state machine) TDD

履歴 view の状態は: `loading` (初回 cache なし) / `cached` (cache あり、API fetch 中) / `loaded` (新データ反映) / `empty` / `error`。
ViewModel として独立、Tests から駆動可能にする。

**Files:**
- Create: `App/ReportTab/ReportHistoryViewModel.swift`
- Create: `Tests/App/ReportTab/ReportHistoryViewModelTests.swift`

- [ ] **Step 1: Failing test**

`Tests/App/ReportTab/ReportHistoryViewModelTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

@MainActor
final class ReportHistoryViewModelTests: XCTestCase {
    private var apiClient: MockReportAPIClient!
    private var cache: ReportHistoryCache!
    private var suiteName: String!
    private var viewModel: ReportHistoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        apiClient = MockReportAPIClient()
        suiteName = "test.history.viewmodel.\(UUID().uuidString)"
        cache = ReportHistoryCache(defaults: UserDefaults(suiteName: suiteName)!)
        viewModel = ReportHistoryViewModel(apiClient: apiClient, cache: cache)
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testInitialState_isLoading() {
        XCTAssertEqual(viewModel.state, .loading)
    }

    func testRefresh_noCacheNoNetwork_setsErrorState() async {
        apiClient.stubFetchHistoryResult = .failure(APIError.networkUnavailable)
        await viewModel.refresh()
        if case .error(let err) = viewModel.state {
            XCTAssertTrue(err is APIError)
        } else {
            XCTFail("Expected .error state, got \(viewModel.state)")
        }
    }

    func testRefresh_noCacheAPISuccess_setsLoadedWithItems() async {
        let item = makeItem(status: .pending)
        apiClient.stubFetchHistoryResult = .success(ReportHistoryResponse(items: [item], fetchedAt: Date()))
        await viewModel.refresh()
        guard case .loaded(let response) = viewModel.state else {
            return XCTFail("Expected .loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(response.items.count, 1)
    }

    func testRefresh_noCacheAPIEmpty_setsEmptyState() async {
        apiClient.stubFetchHistoryResult = .success(ReportHistoryResponse(items: [], fetchedAt: Date()))
        await viewModel.refresh()
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testRefresh_withCacheAndAPISuccess_showsCachedThenLoaded() async {
        // 既存 cache あり
        let cachedItem = makeItem(status: .pending)
        cache.save(ReportHistoryResponse(items: [cachedItem], fetchedAt: Date().addingTimeInterval(-86400)))

        // API が新しいデータ返す
        let freshItem = makeItem(status: .approved)
        apiClient.stubFetchHistoryResult = .success(ReportHistoryResponse(items: [cachedItem, freshItem], fetchedAt: Date()))

        // refresh 直後は cache 反映 → API 完了で loaded
        let viewModelWithCache = ReportHistoryViewModel(apiClient: apiClient, cache: cache)
        XCTAssertEqual(viewModelWithCache.state, .cached(ReportHistoryResponse(items: [cachedItem], fetchedAt: Date().addingTimeInterval(-86400))))

        await viewModelWithCache.refresh()
        guard case .loaded(let response) = viewModelWithCache.state else {
            return XCTFail("Expected .loaded after refresh")
        }
        XCTAssertEqual(response.items.count, 2)
    }

    func testRefresh_withCacheAPIFailure_keepsCachedState() async {
        let cachedItem = makeItem(status: .pending)
        let cachedResponse = ReportHistoryResponse(items: [cachedItem], fetchedAt: Date().addingTimeInterval(-86400))
        cache.save(cachedResponse)

        apiClient.stubFetchHistoryResult = .failure(APIError.networkUnavailable)

        let vm = ReportHistoryViewModel(apiClient: apiClient, cache: cache)
        await vm.refresh()

        // API 失敗だが cache は維持
        XCTAssertEqual(vm.state, .cached(cachedResponse))
    }

    private func makeItem(status: ReportStatus) -> ReportHistoryItem {
        ReportHistoryItem(
            id: UUID().uuidString,
            url: "https://example.com/\(UUID().uuidString.prefix(8))",
            memo: nil, memoRedacted: false, status: status,
            createdAt: Date(), validatedAt: nil, appliedAt: nil
        )
    }
}

// MARK: - Mock

final class MockReportAPIClient: ReportAPIClientProtocol {
    var stubFetchHistoryResult: Result<ReportHistoryResponse, Error> = .success(ReportHistoryResponse(items: [], fetchedAt: Date()))

    func fetchHistory() async throws -> ReportHistoryResponse {
        switch stubFetchHistoryResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    // Phase 2 で他の method は別途 stub
    func requestToken(turnstileResponse: String, scope: TokenScope) async throws -> HMACToken {
        fatalError("not used in HistoryViewModel tests")
    }
    func submitReport(url: URL, memo: String?) async throws { fatalError("not used") }
    func requestDeletion(urlPathHash: String?) async throws { fatalError("not used") }
}
```

- [ ] **Step 2: test 実行 → fail 確認**

Expected: FAIL (ReportHistoryViewModel, state, ReportAPIClientProtocol 等未定義)

- [ ] **Step 3: ReportHistoryViewModel.swift 実装**

`App/ReportTab/ReportHistoryViewModel.swift`:

```swift
import Foundation
import SwiftUI

enum ReportHistoryState: Equatable {
    case loading
    case cached(ReportHistoryResponse)
    case loaded(ReportHistoryResponse)
    case empty
    case error(Error)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.empty, .empty): return true
        case let (.cached(a), .cached(b)): return a == b
        case let (.loaded(a), .loaded(b)): return a == b
        case (.error, .error): return true
        default: return false
        }
    }
}

@MainActor
final class ReportHistoryViewModel: ObservableObject {
    @Published private(set) var state: ReportHistoryState

    private let apiClient: ReportAPIClientProtocol
    private let cache: ReportHistoryCache

    init(apiClient: ReportAPIClientProtocol, cache: ReportHistoryCache) {
        self.apiClient = apiClient
        self.cache = cache

        // 起動時 cache を即座に評価
        if let cached = cache.load() {
            self.state = .cached(cached)
        } else {
            self.state = .loading
        }
    }

    func refresh() async {
        do {
            let response = try await apiClient.fetchHistory()
            if response.items.isEmpty {
                state = .empty
                cache.clear()
            } else {
                state = .loaded(response)
                cache.save(response)
            }
        } catch {
            // cache があれば cached を維持、なければ error
            if case .cached = state {
                // 維持: state は既に .cached
                return
            } else if let cached = cache.load() {
                state = .cached(cached)
            } else {
                state = .error(error)
            }
        }
    }
}
```

- [ ] **Step 4: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportHistoryViewModelTests 2>&1 | tail -15
```

Expected: 6 tests passed

- [ ] **Step 5: commit**

```bash
git add App/ReportTab/ReportHistoryViewModel.swift Tests/App/ReportTab/ReportHistoryViewModelTests.swift
git commit -m "feat(v3): add ReportHistoryViewModel with cache-first + background-refresh state machine

- 5 states: loading / cached / loaded / empty / error
- cache-first UX (instant display) + API fetch
- Graceful degradation: API failure keeps cached state"
```

### Task 5.6: ReportHistoryView 実装 (ViewModel を表示する View) TDD + manual UI verify

**Files:**
- Create: `App/ReportTab/ReportHistoryView.swift`
- Create: `Tests/App/ReportTab/ReportHistoryViewTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import SwiftUI
@testable import AdblockKeshi

@MainActor
final class ReportHistoryViewTests: XCTestCase {
    func testView_initializesWithViewModel() {
        let vm = ReportHistoryViewModel(
            apiClient: MockReportAPIClient(),
            cache: ReportHistoryCache(defaults: UserDefaults(suiteName: "test")!)
        )
        let view = ReportHistoryView(viewModel: vm)
        XCTAssertNotNil(view.body)
    }
}
```

- [ ] **Step 2: 実装**

`App/ReportTab/ReportHistoryView.swift`:

```swift
import SwiftUI

struct ReportHistoryView: View {
    @ObservedObject var viewModel: ReportHistoryViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("読み込み中…").progressViewStyle(.circular)
            case .empty:
                emptyState
            case .error(let err):
                errorState(error: err)
            case .cached(let response), .loaded(let response):
                List {
                    Section {
                        ForEach(response.items) { item in
                            ReportHistoryItemView(item: item)
                        }
                    } footer: {
                        Text("最終更新: \(formatFetchedAt(response.fetchedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("報告履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("再読み込み")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("まだ報告がありません")
                .font(.headline)
            Text("Tab B トップ画面から、消えない広告を報告してください。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func errorState(error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("読み込めませんでした")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("再試行") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
    }

    private func formatFetchedAt(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }
}
```

- [ ] **Step 3: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportHistoryViewTests
```

- [ ] **Step 4: シミュレータで 4 状態目視確認**

シミュレータ起動 → Tab B → 履歴ボタンタップ → 以下 4 シナリオを確認:

1. **empty 状態**: 起動直後、報告 0 件 → 「まだ報告がありません」表示
2. **loaded 状態**: 報告送信後 → リスト表示、最新が上
3. **cached 状態**: アプリ再起動 (オフライン) → cached items 表示 + 古い fetchedAt
4. **error 状態**: 初回起動 + オフライン → 「読み込めませんでした」表示 + 再試行ボタン

- [ ] **Step 5: commit**

```bash
git add App/ReportTab/ReportHistoryView.swift Tests/App/ReportTab/ReportHistoryViewTests.swift
git commit -m "feat(v3): add ReportHistoryView with 4 states + pull-to-refresh

- empty / loading / loaded / cached / error UI
- Toolbar refresh button + pull-to-refresh + .task auto-refresh on appear
- Footer shows last fetchedAt timestamp"
```

### Task 5.7: Tab B 内部ナビ統合 (Entry → Form → Sent → History 戻り経路)

spec §2 で「Tab B 内 subtab or 履歴ボタンで [履歴を見る]」と書いた。実装: ReportTabView の root を NavigationStack にし、Entry 画面に「履歴を見る」ボタン、History への push 遷移。

**Files:**
- Modify: `App/ReportTab/ReportTabView.swift`
- Modify: `App/ReportTab/ReportEntryView.swift` (履歴 button 追加)
- Create: `Tests/App/ReportTab/ReportTabViewTests.swift` (smoke test)

- [ ] **Step 1: Failing test (navigation smoke)**

```swift
import XCTest
import SwiftUI
@testable import AdblockKeshi

@MainActor
final class ReportTabViewTests: XCTestCase {
    func testTabView_initializesWithDependencies() {
        let view = ReportTabView(
            apiClient: MockReportAPIClient(),
            historyCache: ReportHistoryCache(defaults: UserDefaults(suiteName: "test.tabview")!)
        )
        XCTAssertNotNil(view.body)
    }
}
```

- [ ] **Step 2: ReportTabView をナビ統合形に書き換え**

`App/ReportTab/ReportTabView.swift`:

```swift
import SwiftUI

enum ReportTabRoute: Hashable {
    case form
    case sent
    case history
}

struct ReportTabView: View {
    let apiClient: ReportAPIClientProtocol
    let historyCache: ReportHistoryCache

    @State private var path: [ReportTabRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ReportEntryView(
                onReportTap: { path.append(.form) },
                onHistoryTap: { path.append(.history) }
            )
            .navigationTitle("報告")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ReportTabRoute.self) { route in
                switch route {
                case .form:
                    ReportFormView(
                        apiClient: apiClient,
                        onSubmitSuccess: {
                            path.append(.sent)
                        }
                    )
                case .sent:
                    ReportSentView(
                        onAgainTap: {
                            // form だけ pop してエントリに戻る、または form に直接戻る
                            path.removeAll()
                            path.append(.form)
                        },
                        onCloseTap: {
                            path.removeAll()
                        }
                    )
                case .history:
                    ReportHistoryView(viewModel: makeHistoryViewModel())
                }
            }
        }
    }

    private func makeHistoryViewModel() -> ReportHistoryViewModel {
        ReportHistoryViewModel(apiClient: apiClient, cache: historyCache)
    }
}
```

- [ ] **Step 3: ReportEntryView に「履歴を見る」ボタン追加**

`App/ReportTab/ReportEntryView.swift` 修正:

```swift
struct ReportEntryView: View {
    let onReportTap: () -> Void
    let onHistoryTap: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // ... (既存の Image + Text + 報告ボタン) ...

            Button(action: onHistoryTap) {
                Label("これまでの報告履歴", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        // ...
    }
}
```

(既存 init signature `init(onTap:)` を `init(onReportTap:, onHistoryTap:)` に変えるので、上位の Preview も更新)

- [ ] **Step 4: AdblockKeshiApp.swift の TabView から ReportTabView の init 引数を修正**

```swift
ReportTabView(
    apiClient: ReportAPIClient(/* env-configured */),
    historyCache: ReportHistoryCache()
)
.tabItem { ... }
```

- [ ] **Step 5: シミュレータで全 navigation 動作確認**

シナリオ:
1. Tab B → エントリ → 報告ボタン → Form → 送信 → Sent → 「またする」→ Form (path リセット後 push)
2. Tab B → エントリ → 履歴 → History → back → エントリ
3. Form 入力中に back → エントリに戻る (入力 discard)

- [ ] **Step 6: commit**

```bash
git add App/ReportTab/ReportTabView.swift App/ReportTab/ReportEntryView.swift App/AdblockKeshiApp.swift \
        Tests/App/ReportTab/ReportTabViewTests.swift
git commit -m "feat(v3): integrate Tab B navigation (Entry → Form → Sent / Entry → History)

- NavigationStack with ReportTabRoute enum (form/sent/history)
- Entry screen gets 'history' button alongside primary report CTA
- ReportTabView accepts apiClient + historyCache for testability"
```

### Task 5.8: Chunk 5 完了確認 + PR

- [ ] **Step 1: chunk 全 test pass**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -20
```

Expected: 全 PASS。新規追加 test 件数 = 約 23 個 (ReportStatus 5 + ReportHistoryItem 6 + ReportHistoryCache 4 + ReportHistoryItemView 5 + ReportHistoryViewModel 6 + ReportHistoryView 1 + ReportTabView 1 = 28 個程度)

- [ ] **Step 2: E2E シミュレータシナリオ**

1. 報告 0 件 → Tab B 履歴 = empty state
2. 報告 3 件送信 → Tab B 履歴 = 3 件 loaded、最新が上
3. アプリ kill → 再起動 → 履歴即表示 (cached)
4. オフライン化 → 履歴 = cached のまま、refresh で「読み込めませんでした」エラー
5. 各 status (pending/validating/approved/rejected_*) の badge 色目視確認
6. memoRedacted = true の item で「一部伏字」バッジ目視確認

- [ ] **Step 3: PR 作成**

```bash
gh pr create --base feature/v3.0-learning-adblock --title "feat(v3): Tab B history UI with cache + status/redact badges" --body "$(cat <<'EOF'
## Summary
- ReportStatus enum (5 cases) + BadgeRole + Codable
- ReportHistoryItem + ReportHistoryResponse Codable
- ReportHistoryCache (UserDefaults) for instant-load UX
- ReportHistoryItemView with status badge + PII redact notice (rev4 §2)
- ReportHistoryViewModel state machine (loading/cached/loaded/empty/error)
- ReportHistoryView with empty/error states + pull-to-refresh
- Tab B internal NavigationStack (Entry → Form → Sent / Entry → History)

## Tests
- 28 new XCTest cases all passing
- E2E sim: 6 scenarios verified (empty / loaded / cached / offline error / status badges / redact badge)

## Refs
- spec §2 (report tab UX)
- spec rev4 §2 (PII redact notice badge)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: kureho 承認後 merge**

### Chunk 5 完了 → 次は Chunk 6 (ContentRuleListState + Phase 1-2 統合)

---

## Chunk 6: Phase 2 完了 + Phase 1-2 統合テスト

### Task 6.1: ContentRuleListState (2 extension 状態検出) 実装

**Files:**
- Create: `App/ContentRuleListState.swift`
- Create: `Tests/App/ContentRuleListStateTests.swift`

spec §4 2 extension UX (4 パターン状態検出)。

- [ ] **Step 1-N: SFContentBlockerManager.getStateOfContentBlocker(withIdentifier:) を 2 つ並行 fetch、4 パターン enum + Tab A での UI 反映 (黄バナー/赤バナー)**

### Task 6.2: Tab B での 2 extension 状態連動

spec §2 §4 の「学習 OFF 時に報告タブで警告表示」を実装。

### Task 6.3: 全 unit test 実行 + シミュレータ E2E 確認

- [ ] **Step 1: iOS 側全 test pass**

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

- [ ] **Step 2: Workers 全 test pass**

```bash
cd workers && npm test
```

- [ ] **Step 3: 統合 E2E シナリオ実機相当テスト (シミュレータ)**

1. アプリ起動
2. Settings → Safari → 両 extension ON
3. アプリ復帰 → 状態検出で「両方 ON」表示
4. Tab B → 報告ボタン → URL 入力 → 送信
5. Workers が `200 OK` 返却、SentView 表示
6. Tab B → 履歴 → 自分の報告が pending ステータスで表示

- [ ] **Step 4: 動作 screencast 録画 → docs/screenshots/phase2-e2e.mov**

### Task 6.4: Phase 1-2 統合 PR (feature/v3.0-learning-adblock 上の全子 PR を merge 後の状態確認)

- [ ] **Step 1**: feature/v3.0-learning-adblock の状態確認
- [ ] **Step 2**: spec §11 確定事項のうち Phase 1-2 で達成した項目を progress 記録
- [ ] **Step 3**: kureho 承認後、Phase 1-2 完了宣言

---

## Plan A 完了後の次ステップ

Phase 1-2 完了後、次に作成する plan:

- **Plan B**: Phase 3-4 (Week 5-9) — 8 層 safety gate L1-L8 + GitHub Actions workflow 8 個統合
- **Plan C**: Phase 5 (Week 10-12) — abuse 自動化 + 履歴 UI 高度化 + moat 可視化 + feature flag + Privacy Policy 更新
- **Plan D**: Phase 6-7 (Week 13-15) — シミュレータ + 実機テスト + 4 点監査 + ASC 提出

Plan B 作成時の前提:
- Plan A の 2 extension PoC 結果 (Path 1 採用 / Path 2-4 fallback) で Phase 3 CDN 構造を確定
- Plan A の Workers 構造が安定 (`/v1/reports/*` endpoint suite が存在) の前提で safety gate logic を載せる

---

## 関連 skill リファレンス

- @superpowers:test-driven-development — TDD 遵守 (各 task で test 先行)
- @superpowers:verification-before-completion — 各 Task 完了前に test 実行 + 動作確認
- @superpowers:systematic-debugging — バグ遭遇時の場当たり修正禁止
- @superpowers:subagent-driven-development — 各子ブランチを独立 subagent で並行実装する選択肢
- @batch-job-safety — Phase 3 以降 workflow 作成時に invoke
- @safe-schema-change — D1 migration 追加時に invoke

---

## Phase 1-2 完了 DoD 再確認

実装が完了したと宣言できる条件:

1. ✅ Workers `/v1/health` が 200 OK
2. ✅ D1 全 5 テーブル作成、local migrations 適用済
3. ✅ Turnstile site key 発行、`/v1/reports/token` で HMAC token 発行成功
4. ✅ project.yml に 2 extension target、xcodegen ビルド成功
5. ✅ **2 extension シミュレータ動作 screencast** (`docs/screenshots/2-extension-poc.mov`)
6. ✅ Tab B UI: Entry → Form → Sent → History 全 4 画面動作
7. ✅ Tab B から Workers `/v1/reports/submit` で実通信成功
8. ✅ 履歴 UI が `POST /v1/reports/history` で自分の報告一覧取得・表示
9. ✅ ContentRuleListState の 4 パターン UX (両方 ON / base のみ / 学習のみ / 両方 OFF)
10. ✅ 全 unit test pass (iOS XCTest + Workers Vitest)
11. ✅ Phase 1-2 統合 E2E シミュレータ実証 (`docs/screenshots/phase2-e2e.mov`)
12. ✅ feature/v3.0-learning-adblock branch に全子 PR merge 済、main は v2.1.1 hotfix 余地維持

---

**(end of Plan A, 2026-06-07)**
