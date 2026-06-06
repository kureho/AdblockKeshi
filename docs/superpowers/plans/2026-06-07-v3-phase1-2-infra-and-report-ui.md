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

### Task 2.6: Turnstile validation lib + `/v1/reports/token` endpoint (TDD)

⚠️ Phase 2 では Turnstile 連携の **本番 site key** は端末側 WebView 整備後に差し替え (Task 4.X)。
ここでは Workers 側 server validation を実装、test では Cloudflare の `XXXX.DUMMY.DUMMY.XXXX` test secret を使う。

#### 仕様詳細

| 項目 | 値 |
|---|---|
| Turnstile siteverify endpoint | `https://challenges.cloudflare.com/turnstile/v0/siteverify` |
| 必須 body params | `secret`, `response` (端末からの Turnstile token) |
| 推奨 body params | `remoteip` (Workers req.headers から取得) |
| 成功判定 | response `{ "success": true, ... }` |
| 失敗 reason | `[ "missing-input-secret", "missing-input-response", "invalid-input-secret", "invalid-input-response", "bad-request", "timeout-or-duplicate" ]` |
| Test secret (dev) | `1x0000000000000000000000000000000AA` (Cloudflare 公式 test、必ず success) |

**Files:**
- Create: `workers/src/lib/turnstile.ts`
- Create: `workers/src/handlers/token.ts`
- Create: `workers/tests/lib/turnstile.test.ts`
- Create: `workers/tests/handlers/token.test.ts`
- Modify: `workers/src/index.ts` (router)

- [ ] **Step 1: turnstile.ts failing test**

`workers/tests/lib/turnstile.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { verifyTurnstile, TurnstileError } from '../../src/lib/turnstile'

describe('verifyTurnstile', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it('returns true for Cloudflare always-success test secret', async () => {
    // SELF.fetch mock not applicable since we hit external. Use vi.spyOn on fetch
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )
    const result = await verifyTurnstile({
      secret: '1x0000000000000000000000000000000AA',
      response: 'dummy-token',
      remoteip: '1.2.3.4',
    })
    expect(result).toBe(true)
  })

  it('throws TurnstileError for invalid-input-response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({
        success: false,
        'error-codes': ['invalid-input-response'],
      }), { status: 200 })
    )
    await expect(verifyTurnstile({
      secret: 's',
      response: 'bad',
    })).rejects.toThrow(TurnstileError)
  })

  it('throws TurnstileError for Cloudflare always-fail test secret', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({
        success: false,
        'error-codes': ['invalid-input-response'],
      }), { status: 200 })
    )
    await expect(verifyTurnstile({
      secret: '2x0000000000000000000000000000000AA',
      response: 'x',
    })).rejects.toThrow(TurnstileError)
  })

  it('includes remoteip in request body', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )
    await verifyTurnstile({
      secret: '1x0000000000000000000000000000000AA',
      response: 'dummy',
      remoteip: '1.2.3.4',
    })
    expect(fetchSpy).toHaveBeenCalled()
    const callArgs = fetchSpy.mock.calls[0]
    const body = callArgs[1]?.body as string
    expect(body).toContain('remoteip=1.2.3.4')
  })

  it('throws for non-200 Cloudflare response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response('Server Error', { status: 500 })
    )
    await expect(verifyTurnstile({
      secret: 's',
      response: 'x',
    })).rejects.toThrow()
  })
})
```

- [ ] **Step 2: test 実行 → fail 確認**

```bash
cd workers && npm test -- turnstile.test.ts
```

Expected: FAIL (lib/turnstile not found)

- [ ] **Step 3: turnstile.ts 実装**

`workers/src/lib/turnstile.ts`:

```typescript
export class TurnstileError extends Error {
  constructor(public readonly errorCodes: string[]) {
    super(`Turnstile verification failed: ${errorCodes.join(', ')}`)
    this.name = 'TurnstileError'
  }
}

interface VerifyArgs {
  secret: string
  response: string
  remoteip?: string
}

interface TurnstileResponseBody {
  success: boolean
  'error-codes'?: string[]
  challenge_ts?: string
  hostname?: string
  action?: string
}

const SITEVERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify'

export async function verifyTurnstile(args: VerifyArgs): Promise<boolean> {
  const params = new URLSearchParams()
  params.set('secret', args.secret)
  params.set('response', args.response)
  if (args.remoteip) params.set('remoteip', args.remoteip)

  const response = await fetch(SITEVERIFY_URL, {
    method: 'POST',
    body: params.toString(),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  })

  if (!response.ok) {
    throw new Error(`Turnstile siteverify HTTP ${response.status}`)
  }

  const body = (await response.json()) as TurnstileResponseBody
  if (!body.success) {
    throw new TurnstileError(body['error-codes'] ?? ['unknown'])
  }
  return true
}
```

- [ ] **Step 4: test pass 確認**

```bash
npm test -- turnstile.test.ts
```

Expected: 5 tests passed

- [ ] **Step 5: token endpoint failing test**

`workers/tests/handlers/token.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'

describe('POST /v1/reports/token', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    // Cloudflare test secret = 必ず success
    env.TURNSTILE_SECRET = '1x0000000000000000000000000000000AA'
    env.HMAC_KEY = 'test-hmac-key-do-not-use-in-prod'
    env.SERVER_SALT = 'test-server-salt'
  })

  it('returns 200 with token + expires_at + server_salt for valid Turnstile', async () => {
    // Cloudflare siteverify を fake success
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )

    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'dummy-tr', scope: 'submit' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = (await response.json()) as { token: string; expires_at: number; server_salt: string }
    expect(body.token).toBeTruthy()
    expect(body.token).toMatch(/^.+\..+$/)  // data.signature 形式
    expect(body.expires_at).toBeGreaterThan(Date.now() / 1000)
    expect(body.expires_at).toBeLessThan(Date.now() / 1000 + 310)  // 5 分 + 余裕
    expect(body.server_salt).toBe('test-server-salt')
  })

  it('returns 400 for missing turnstile_response', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ scope: 'submit' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = (await response.json()) as { error: string }
    expect(body.error).toBe('validation_failed')
  })

  it('returns 400 for invalid scope', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'x', scope: 'invalid_scope' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('returns 400 with turnstile_failed when Turnstile rejects', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: false, 'error-codes': ['invalid-input-response'] }), { status: 200 })
    )
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'bad-token', scope: 'submit' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = (await response.json()) as { error: string }
    expect(body.error).toBe('turnstile_failed')
  })

  it('returns 405 for GET', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', { method: 'GET' })
    expect(response.status).toBe(405)
  })

  it('issued token can be verified with same HMAC_KEY', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'x', scope: 'submit' }),
      headers: { 'Content-Type': 'application/json' },
    })
    const body = (await response.json()) as { token: string }
    // verify
    const { verifyToken } = await import('../../src/lib/hmac')
    const payload = await verifyToken(body.token, env.HMAC_KEY!)
    expect(payload.scope).toBe('submit')
  })
})
```

- [ ] **Step 6: token.ts 実装**

`workers/src/handlers/token.ts`:

```typescript
import type { Env } from '../env'
import { verifyTurnstile, TurnstileError } from '../lib/turnstile'
import { signToken, type TokenPayload } from '../lib/hmac'

interface TokenRequestBody {
  turnstile_response?: string
  scope?: string
}

const VALID_SCOPES = new Set(['submit', 'history', 'delete'])
const TOKEN_TTL_SECONDS = 300  // 5 分

export async function handleToken(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: TokenRequestBody
  try {
    body = await request.json()
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON body')
  }

  const { turnstile_response, scope } = body
  if (!turnstile_response || typeof turnstile_response !== 'string') {
    return jsonError(400, 'validation_failed', 'turnstile_response required')
  }
  if (!scope || !VALID_SCOPES.has(scope)) {
    return jsonError(400, 'validation_failed', `scope must be one of: ${[...VALID_SCOPES].join(', ')}`)
  }

  // Turnstile verify
  try {
    const remoteip = request.headers.get('CF-Connecting-IP') ?? undefined
    await verifyTurnstile({
      secret: env.TURNSTILE_SECRET,
      response: turnstile_response,
      remoteip,
    })
  } catch (e) {
    if (e instanceof TurnstileError) {
      return jsonError(400, 'turnstile_failed', e.message)
    }
    return jsonError(500, 'turnstile_internal', 'verification service error')
  }

  // device-specific subject は token 発行時点では未知 (端末がまだ uuid_hash を送ってない)
  // → subject は placeholder で発行、submit 時に request body の uuid_hash を verify side で照合する設計
  // 簡略化: subject = "anonymous"、submit ハンドラで uuid_hash を別途検証 (token は scope と expires のみ enforce)
  const payload: TokenPayload = {
    subject: 'anonymous',
    expires: Date.now() + TOKEN_TTL_SECONDS * 1000,
    scope: scope as TokenPayload['scope'],
  }
  const token = await signToken(payload, env.HMAC_KEY)

  return new Response(JSON.stringify({
    token,
    expires_at: Math.floor(payload.expires / 1000),
    server_salt: env.SERVER_SALT,
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
```

- [ ] **Step 7: index.ts router に追加**

`workers/src/index.ts` の `fetch` 関数内に分岐追加:

```typescript
import { handleToken } from './handlers/token'

// 中略...
if (url.pathname === '/v1/reports/token') {
  return handleToken(request, env)
}
```

- [ ] **Step 8: test pass + commit**

```bash
npm test -- token.test.ts
# Expected: 6 tests passed

git add workers/src/lib/turnstile.ts workers/src/handlers/token.ts workers/src/index.ts \
        workers/tests/lib/turnstile.test.ts workers/tests/handlers/token.test.ts
git commit -m "feat(workers): add Turnstile verify + /v1/reports/token endpoint

- verifyTurnstile lib with TurnstileError class
- POST /v1/reports/token: Turnstile validate → HMAC sign → 5min token
- Returns { token, expires_at, server_salt }
- 11 test cases covering all error paths"
```

### Task 2.7: `/v1/reports/submit` endpoint (URL validation + D1 INSERT) TDD

#### 仕様詳細

| 項目 | 値 |
|---|---|
| Body | `{ token, uuid_hash, url, memo? }` |
| URL 検証 | `https://` + host 非空 + 200 字以内 |
| Tranco Top 1M | Phase 2 では未実装 (Plan B で導入)、stub: 既知 critical list 50 件のみ即 reject |
| memo PII redact | rev3 §2: 電話/メール/CC 検出 → 置換、`pii_redacted` で abuse_log INSERT (ban 加算しない) |
| rate limit | per uuid_hash 5/日、per ip_hash 5/15min (Phase 2 で基本実装) |
| token 検証 | HMAC verify + scope == 'submit' + 5 分以内 |
| 成功 response | `{ id, status: "pending", received_at, memo_redacted }` |
| 失敗 | 400 validation / 401 unauthorized / 429 rate_limit / 403 banned |

**Files:**
- Create: `workers/src/handlers/submit.ts`
- Create: `workers/src/lib/validation.ts` (URL/memo validation)
- Create: `workers/src/lib/pii-redact.ts` (rev3 §2 redact)
- Create: `workers/src/lib/rate-limit.ts` (D1-backed)
- Create: `workers/src/lib/critical-list.ts` (50 ドメイン静的 list)
- Tests: 同名 `tests/handlers/submit.test.ts` + lib tests
- Migrations: 既に 0001-0005 完了

- [ ] **Step 1: pii-redact lib failing test**

`workers/tests/lib/pii-redact.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { redactPII } from '../../src/lib/pii-redact'

describe('redactPII', () => {
  it('returns original if no PII', () => {
    const { redacted, didRedact } = redactPII('動画上のオーバーレイ広告')
    expect(redacted).toBe('動画上のオーバーレイ広告')
    expect(didRedact).toBe(false)
  })

  it('masks Japanese phone with hyphens', () => {
    const { redacted, didRedact } = redactPII('連絡先 03-1234-5678 です')
    expect(redacted).toContain('***-****-****')
    expect(redacted).not.toContain('03-1234-5678')
    expect(didRedact).toBe(true)
  })

  it('masks free-dial', () => {
    const { redacted, didRedact } = redactPII('0120-123-456 で予約')
    expect(redacted).toContain('***-****-****')
    expect(didRedact).toBe(true)
  })

  it('masks Japanese phone without hyphens', () => {
    const { redacted, didRedact } = redactPII('電話 03123456 78 番号')
    // partial match still ok if regex covers
    expect(didRedact).toBe(true)
  })

  it('masks email addresses', () => {
    const { redacted, didRedact } = redactPII('連絡先: user@example.com まで')
    expect(redacted).toContain('***@***.***')
    expect(redacted).not.toContain('user@example.com')
    expect(didRedact).toBe(true)
  })

  it('masks credit card numbers', () => {
    const { redacted, didRedact } = redactPII('カード 4242-4242-4242-4242 の不正利用')
    expect(redacted).toContain('****-****-****-****')
    expect(didRedact).toBe(true)
  })

  it('does NOT mask short digit sequences', () => {
    const { redacted, didRedact } = redactPII('ABCD-1234 のID')
    expect(redacted).toBe('ABCD-1234 のID')
    expect(didRedact).toBe(false)
  })

  it('handles multiple PIIs in one memo', () => {
    const { redacted, didRedact } = redactPII('tel 03-1234-5678 email a@b.com')
    expect(redacted).toContain('***-****-****')
    expect(redacted).toContain('***@***.***')
    expect(didRedact).toBe(true)
  })

  it('preserves URL-like substrings (URL is rejected separately)', () => {
    const { redacted } = redactPII('see https://example.com/path')
    // URL は MemoValidator で hard reject される設計、redact lib では URL 触らない
    expect(redacted).toContain('https://example.com')
  })

  it('handles empty input', () => {
    const { redacted, didRedact } = redactPII('')
    expect(redacted).toBe('')
    expect(didRedact).toBe(false)
  })
})
```

- [ ] **Step 2: pii-redact.ts 実装**

`workers/src/lib/pii-redact.ts`:

```typescript
export interface RedactResult {
  redacted: string
  didRedact: boolean
}

const PATTERNS: Array<{ regex: RegExp; mask: string }> = [
  // 電話番号 (日本、ハイフンあり/なし両対応)
  { regex: /0\d{1,4}-?\d{1,4}-?\d{4}/g, mask: '***-****-****' },
  // 国際電話番号
  { regex: /\+\d{1,3}[\s-]?\d{2,4}[\s-]?\d{2,4}[\s-]?\d{2,4}/g, mask: '+**-****-****' },
  // メールアドレス
  { regex: /[\w._%+-]+@[\w.-]+\.\w+/g, mask: '***@***.***' },
  // クレジットカード (16 桁、ハイフンあり/なし)、Luhn 検証は省略 (rev3 spec 通り簡易)
  { regex: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, mask: '****-****-****-****' },
]

export function redactPII(input: string): RedactResult {
  let didRedact = false
  let result = input
  for (const { regex, mask } of PATTERNS) {
    if (regex.test(result)) {
      didRedact = true
      result = result.replace(regex, mask)
    }
  }
  return { redacted: result, didRedact }
}
```

- [ ] **Step 3: rate-limit lib failing test + 実装**

`workers/tests/lib/rate-limit.test.ts`:

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { env } from 'cloudflare:test'
import { checkRateLimit, recordRequest } from '../../src/lib/rate-limit'

describe('rate-limit (D1-backed)', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('allows first request', async () => {
    const result = await checkRateLimit(env.DB, {
      uuidHash: 'aaa', ipHash: 'bbb', now: Date.now() / 1000
    })
    expect(result.allowed).toBe(true)
  })

  it('blocks 6th uuid request within 24h', async () => {
    const now = Math.floor(Date.now() / 1000)
    const uuid = 'user-1'
    for (let i = 0; i < 5; i++) {
      await recordRequest(env.DB, { uuidHash: uuid, ipHash: 'ip-1', url: `https://x.com/${i}`, status: 'pending', createdAt: now - 100 })
    }
    const result = await checkRateLimit(env.DB, { uuidHash: uuid, ipHash: 'ip-1', now })
    expect(result.allowed).toBe(false)
    expect(result.reason).toBe('uuid_daily_limit')
  })

  it('blocks 6th ip request within 15min', async () => {
    const now = Math.floor(Date.now() / 1000)
    for (let i = 0; i < 5; i++) {
      await recordRequest(env.DB, { uuidHash: `uuid-${i}`, ipHash: 'ip-X', url: `https://x.com/${i}`, status: 'pending', createdAt: now - 100 })
    }
    const result = await checkRateLimit(env.DB, { uuidHash: 'new-uuid', ipHash: 'ip-X', now })
    expect(result.allowed).toBe(false)
    expect(result.reason).toBe('ip_15min_limit')
  })

  it('respects banned uuid in bans table', async () => {
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(`
      INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind('banned-uuid', 'uuid', 'rate_limit_repeat', 5, 2, now + 7 * 86400, now).run()

    const result = await checkRateLimit(env.DB, { uuidHash: 'banned-uuid', ipHash: 'ip-Z', now })
    expect(result.allowed).toBe(false)
    expect(result.reason).toBe('banned')
  })

  it('respects expired ban (banned but expires_at < now)', async () => {
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(`
      INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind('expired-banned', 'uuid', 'old', 3, 1, now - 100, now - 86400).run()

    const result = await checkRateLimit(env.DB, { uuidHash: 'expired-banned', ipHash: 'ip-Q', now })
    expect(result.allowed).toBe(true)
  })
})
```

`workers/src/lib/rate-limit.ts`:

```typescript
export interface RateLimitArgs {
  uuidHash: string
  ipHash: string
  now: number  // unix sec
}

export interface RateLimitResult {
  allowed: boolean
  reason?: 'banned' | 'uuid_daily_limit' | 'ip_15min_limit' | 'uuid_monthly_limit'
}

export interface RecordArgs {
  uuidHash: string
  ipHash: string
  url: string
  status: string
  createdAt: number
}

const UUID_DAILY_LIMIT = 5
const UUID_MONTHLY_LIMIT = 30
const IP_15MIN_LIMIT = 5
const ONE_DAY_SEC = 86400
const ONE_MONTH_SEC = 30 * ONE_DAY_SEC
const FIFTEEN_MIN_SEC = 15 * 60

export async function checkRateLimit(db: D1Database, args: RateLimitArgs): Promise<RateLimitResult> {
  // 1. ban check
  const ban = await db.prepare(
    'SELECT identifier_hash FROM bans WHERE identifier_hash IN (?, ?) AND expires_at > ?'
  ).bind(args.uuidHash, args.ipHash, args.now).first()
  if (ban) return { allowed: false, reason: 'banned' }

  // 2. uuid daily
  const uuidDaily = await db.prepare(
    'SELECT COUNT(*) as c FROM reports WHERE uuid_hash = ? AND created_at > ?'
  ).bind(args.uuidHash, args.now - ONE_DAY_SEC).first<{ c: number }>()
  if ((uuidDaily?.c ?? 0) >= UUID_DAILY_LIMIT) {
    return { allowed: false, reason: 'uuid_daily_limit' }
  }

  // 3. uuid monthly
  const uuidMonthly = await db.prepare(
    'SELECT COUNT(*) as c FROM reports WHERE uuid_hash = ? AND created_at > ?'
  ).bind(args.uuidHash, args.now - ONE_MONTH_SEC).first<{ c: number }>()
  if ((uuidMonthly?.c ?? 0) >= UUID_MONTHLY_LIMIT) {
    return { allowed: false, reason: 'uuid_monthly_limit' }
  }

  // 4. ip 15-min
  const ip15 = await db.prepare(
    'SELECT COUNT(*) as c FROM reports WHERE ip_hash = ? AND created_at > ?'
  ).bind(args.ipHash, args.now - FIFTEEN_MIN_SEC).first<{ c: number }>()
  if ((ip15?.c ?? 0) >= IP_15MIN_LIMIT) {
    return { allowed: false, reason: 'ip_15min_limit' }
  }

  return { allowed: true }
}

export async function recordRequest(db: D1Database, args: RecordArgs): Promise<void> {
  // 内部 helper、本来は submit handler から D1 INSERT を直接呼ぶが、rate-limit テストでは別関数として使う
  const id = crypto.randomUUID()
  const urlHash = await sha256Hex(args.url)
  const domain = new URL(args.url).host
  await db.prepare(`
    INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(id, args.uuidHash, args.ipHash, domain, args.url, urlHash, args.status, args.createdAt).run()
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}
```

- [ ] **Step 4: critical-list lib (50 ドメイン静的)**

`workers/src/lib/critical-list.ts`:

```typescript
// Phase 2 では最小限の静的 list、Plan B で Tranco Top 1M に拡張
export const CRITICAL_DOMAINS = new Set<string>([
  'apple.com', 'icloud.com', 'me.com', 'mac.com',
  'google.com', 'gmail.com', 'youtube.com', 'googleusercontent.com',
  'microsoft.com', 'outlook.com', 'live.com', 'office.com',
  'amazon.com', 'amazon.co.jp', 'amazonaws.com',
  'meta.com', 'facebook.com', 'instagram.com', 'whatsapp.com',
  'twitter.com', 'x.com', 't.co',
  'linkedin.com', 'github.com',
  'cloudflare.com',
  // 日本系
  'yahoo.co.jp', 'rakuten.co.jp', 'mercari.com',
  'mhlw.go.jp', 'meti.go.jp', 'mof.go.jp', 'jnto.go.jp',
  'nhk.or.jp', 'mainichi.jp', 'asahi.com', 'nikkei.com',
  'kureho.app', 'kureho.com',
  // payment 系
  'visa.com', 'mastercard.com', 'paypal.com', 'stripe.com',
  // bank
  'mizuhobank.co.jp', 'smbc.co.jp', 'mufg.jp',
  // 教育
  'u-tokyo.ac.jp', 'kyoto-u.ac.jp',
  // 検索エンジン
  'bing.com', 'duckduckgo.com',
  // adblockkeshi 自身
  'adblockkeshi.kureho.app',
])

export function isCriticalDomain(domain: string): boolean {
  // exact match + suffix match (subdomain も保護)
  if (CRITICAL_DOMAINS.has(domain)) return true
  for (const critical of CRITICAL_DOMAINS) {
    if (domain.endsWith('.' + critical)) return true
  }
  return false
}
```

- [ ] **Step 5: validation lib (URL/memo basic) failing test + 実装**

`workers/src/lib/validation.ts`:

```typescript
export interface ValidationResult {
  ok: boolean
  reason?: string
}

const MAX_URL_LENGTH = 200
const MAX_MEMO_LENGTH = 200

export function validateURL(url: string): ValidationResult {
  if (!url || url.trim().length === 0) return { ok: false, reason: 'url_empty' }
  if (url.length > MAX_URL_LENGTH) return { ok: false, reason: 'url_too_long' }
  if (!url.toLowerCase().startsWith('https://')) return { ok: false, reason: 'url_not_https' }
  try {
    const u = new URL(url)
    if (!u.host) return { ok: false, reason: 'url_malformed' }
    if (u.host.length < 7) return { ok: false, reason: 'url_domain_too_short' }
    return { ok: true }
  } catch {
    return { ok: false, reason: 'url_malformed' }
  }
}

export function validateMemo(memo: string | undefined | null): ValidationResult {
  if (memo == null || memo === '') return { ok: true }
  if (memo.length > MAX_MEMO_LENGTH) return { ok: false, reason: 'memo_too_long' }
  // URL contained check (PII filter は別、redact 処理)
  if (/https?:\/\//.test(memo)) return { ok: false, reason: 'memo_contains_url' }
  return { ok: true }
}
```

- [ ] **Step 6: submit.ts handler failing test (Vitest workers)**

`workers/tests/handlers/submit.test.ts`:

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

async function makeToken(scope: 'submit' = 'submit'): Promise<string> {
  return signToken(
    { subject: 'anonymous', expires: Date.now() + 60000, scope },
    env.HMAC_KEY
  )
}

describe('POST /v1/reports/submit', () => {
  beforeEach(async () => {
    env.HMAC_KEY = 'test-hmac-key'
    env.SERVER_SALT = 'test-salt'
    env.TURNSTILE_SECRET = '1x0000000000000000000000000000000AA'
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('returns 200 and creates D1 row for valid submission', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token,
        uuid_hash: 'a'.repeat(64),
        url: 'https://example.com/article',
        memo: 'overlay ad',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = (await response.json()) as any
    expect(body.id).toBeTruthy()
    expect(body.status).toBe('pending')
    expect(body.memo_redacted).toBe(false)

    const row = await env.DB.prepare('SELECT * FROM reports WHERE id = ?').bind(body.id).first<any>()
    expect(row.url).toBe('https://example.com/article')
    expect(row.memo).toBe('overlay ad')
  })

  it('redacts PII in memo and sets memo_redacted=true', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token,
        uuid_hash: 'b'.repeat(64),
        url: 'https://news.example.jp/page',
        memo: '電話 03-1234-5678 を見せる広告',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = (await response.json()) as any
    expect(body.memo_redacted).toBe(true)

    const row = await env.DB.prepare('SELECT memo FROM reports WHERE id = ?').bind(body.id).first<any>()
    expect(row.memo).toContain('***-****-****')

    const abuse = await env.DB.prepare('SELECT reason FROM abuse_log WHERE identifier_hash = ?').bind('b'.repeat(64)).first<any>()
    expect(abuse.reason).toBe('pii_redacted')
  })

  it('rejects with 400 for invalid URL', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: 'c'.repeat(64), url: 'http://no-https.com' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = (await response.json()) as any
    expect(body.error).toBe('validation_failed')
  })

  it('rejects with 400 for critical domain (apple.com)', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: 'd'.repeat(64), url: 'https://apple.com/support' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = (await response.json()) as any
    expect(body.error).toBe('validation_failed')
    expect(body.message).toContain('critical')
  })

  it('rejects subdomain of critical domain', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: 'e'.repeat(64), url: 'https://developer.apple.com/docs' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('rejects with 401 for invalid token', async () => {
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token: 'invalid.signature',
        uuid_hash: 'f'.repeat(64),
        url: 'https://example.com/x',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('rejects with 401 for wrong scope token', async () => {
    const token = await signToken(
      { subject: 'anonymous', expires: Date.now() + 60000, scope: 'history' },
      env.HMAC_KEY
    )
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: 'g'.repeat(64), url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('rejects with 429 after 5 reports/day per uuid', async () => {
    const token = await makeToken('submit')
    const uuidHash = 'h'.repeat(64)
    // 5 件挿入
    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).bind(`r${i}`, uuidHash, 'ip', 'example.com', `https://example.com/${i}`, `hash${i}`, 'pending', Math.floor(Date.now() / 1000)).run()
    }
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuidHash, url: 'https://example.com/6' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(429)
    const body = (await response.json()) as any
    expect(body.error).toBe('rate_limit_exceeded')
  })
})
```

- [ ] **Step 7: submit.ts 実装**

`workers/src/handlers/submit.ts`:

```typescript
import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'
import { validateURL, validateMemo } from '../lib/validation'
import { redactPII } from '../lib/pii-redact'
import { isCriticalDomain } from '../lib/critical-list'
import { checkRateLimit } from '../lib/rate-limit'

interface SubmitBody {
  token?: string
  uuid_hash?: string
  url?: string
  memo?: string
}

export async function handleSubmit(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: SubmitBody
  try {
    body = await request.json()
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON')
  }

  // 必須項目
  if (!body.token) return jsonError(400, 'validation_failed', 'token required')
  if (!body.uuid_hash || body.uuid_hash.length !== 64) return jsonError(400, 'validation_failed', 'uuid_hash must be 64 hex chars')
  if (!body.url) return jsonError(400, 'validation_failed', 'url required')

  // token verify
  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'submit') return jsonError(401, 'unauthorized', 'wrong scope')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid or expired token')
  }

  // URL validation
  const urlCheck = validateURL(body.url)
  if (!urlCheck.ok) return jsonError(400, 'validation_failed', urlCheck.reason!)

  const domain = new URL(body.url).host
  if (isCriticalDomain(domain)) {
    return jsonError(400, 'validation_failed', `critical_domain: ${domain} is protected`)
  }

  // memo validation
  const memoCheck = validateMemo(body.memo)
  if (!memoCheck.ok) return jsonError(400, 'validation_failed', memoCheck.reason!)

  // PII redact
  const { redacted: memoRedacted, didRedact } = redactPII(body.memo ?? '')

  // rate limit
  const ipHash = await sha256Hex((request.headers.get('CF-Connecting-IP') ?? 'unknown') + env.SERVER_SALT)
  const now = Math.floor(Date.now() / 1000)
  const rl = await checkRateLimit(env.DB, { uuidHash: body.uuid_hash, ipHash, now })
  if (!rl.allowed) {
    const retryAfter = rl.reason === 'uuid_daily_limit' ? 86400 : rl.reason === 'uuid_monthly_limit' ? 30 * 86400 : 900
    if (rl.reason === 'banned') return jsonError(403, 'banned', 'temporarily banned')
    return jsonErrorWithRetry(429, 'rate_limit_exceeded', rl.reason ?? 'unknown', retryAfter)
  }

  // D1 INSERT
  const id = crypto.randomUUID()
  const urlPathHash = await sha256Hex(body.url)
  await env.DB.prepare(`
    INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(id, body.uuid_hash, ipHash, domain, body.url, urlPathHash, memoRedacted || null, 'pending', now).run()

  if (didRedact) {
    await env.DB.prepare(`
      INSERT INTO abuse_log (identifier_hash, identifier_type, reason, url, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(body.uuid_hash, 'uuid', 'pii_redacted', body.url, now).run()
  }

  return new Response(JSON.stringify({
    id,
    status: 'pending',
    received_at: now,
    memo_redacted: didRedact,
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

function jsonErrorWithRetry(status: number, error: string, message: string, retryAfter: number): Response {
  return new Response(JSON.stringify({ error, message, retry_after: retryAfter }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}
```

- [ ] **Step 8: index.ts router に追加** + test pass 確認

```typescript
import { handleSubmit } from './handlers/submit'
// in fetch:
if (url.pathname === '/v1/reports/submit') return handleSubmit(request, env)
```

- [ ] **Step 9: commit**

```bash
git add workers/src/lib/{pii-redact,validation,critical-list,rate-limit}.ts \
        workers/src/handlers/submit.ts workers/src/index.ts \
        workers/tests/lib/{pii-redact,rate-limit,validation}.test.ts \
        workers/tests/handlers/submit.test.ts
git commit -m "feat(workers): /v1/reports/submit with PII redact + rate limit + critical list

- pii-redact: phone/email/CC mask (silent, ban-加算なし)
- validation: URL https-only/200char, memo URL-detect
- critical-list: 50 domains, exact+suffix match
- rate-limit: 5/day/uuid + 5/15min/ip + ban check
- submit handler: full chain with HMAC token verify
- 8 submit test cases + 10 supporting lib tests"
```

### Task 2.8: `/v1/reports/history` endpoint (HMAC token verify + D1 SELECT)

#### 仕様詳細

| 項目 | 値 |
|---|---|
| Body | `{ token, uuid_hash }` |
| token scope | `history` 必須 |
| D1 query | `SELECT ... FROM reports WHERE uuid_hash = ? ORDER BY created_at DESC LIMIT 50` |
| Response | `{ items: [{id, url, memo, memo_redacted, status, created_at, validated_at, applied_at}], fetched_at }` |
| memo_redacted フラグ | rev4 §2: 該当 abuse_log に `pii_redacted` 行があれば true |

**Files:**
- Create: `workers/src/handlers/history.ts`
- Create: `workers/tests/handlers/history.test.ts`

- [ ] **Step 1-5: TDD で実装** (submit と同パターン、再掲省略)

```typescript
// workers/src/handlers/history.ts
import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'

export async function handleHistory(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') return jsonError(405, 'method_not_allowed', 'POST required')

  let body: { token?: string; uuid_hash?: string }
  try { body = await request.json() } catch { return jsonError(400, 'validation_failed', 'invalid JSON') }
  if (!body.token || !body.uuid_hash) return jsonError(400, 'validation_failed', 'token and uuid_hash required')

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'history') return jsonError(401, 'unauthorized', 'wrong scope')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid token')
  }

  // reports + abuse_log JOIN for memo_redacted flag
  const rows = await env.DB.prepare(`
    SELECT
      r.id, r.url, r.memo, r.status, r.created_at, r.validated_at, r.applied_at,
      EXISTS (
        SELECT 1 FROM abuse_log a WHERE a.identifier_hash = r.uuid_hash AND a.reason = 'pii_redacted' AND a.url = r.url
      ) AS memo_redacted
    FROM reports r WHERE r.uuid_hash = ?
    ORDER BY r.created_at DESC LIMIT 50
  `).bind(body.uuid_hash).all<any>()

  const items = (rows.results ?? []).map(r => ({
    id: r.id,
    url: r.url,
    memo: r.memo,
    memo_redacted: Boolean(r.memo_redacted),
    status: r.status,
    created_at: r.created_at,
    validated_at: r.validated_at,
    applied_at: r.applied_at,
  }))

  return new Response(JSON.stringify({
    items,
    fetched_at: Math.floor(Date.now() / 1000),
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), { status, headers: { 'Content-Type': 'application/json' } })
}
```

Tests (history.test.ts) は token 検証、空 list、limit 50、memo_redacted フラグ反映の 4 ケース。

- [ ] **Step 6: commit**

```bash
git commit -m "feat(workers): /v1/reports/history with HMAC scope=history + memo_redacted flag JOIN"
```

### Task 2.9: `/v1/reports/delete` endpoint (Phase 2 stub、Plan C で本格)

Phase 2 では `deletion_requests` 行を INSERT するだけの最小実装。実際の DELETE は Plan C の `hourly-deletion-processor.yml` workflow 範囲。

**Files:**
- Create: `workers/src/handlers/delete.ts`、`workers/tests/handlers/delete.test.ts`

- [ ] **Step 1-4: TDD で実装、stub レベル**

```typescript
export async function handleDelete(request: Request, env: Env): Promise<Response> {
  // token (scope='delete') + uuid_hash + url_path_hash? を受信
  // → deletion_requests に INSERT、status='pending'
  // 実際の削除は hourly cron (Plan C) で処理
  // ...
}
```

- [ ] **Step 5: commit**

### Task 2.10: Phase 1 完了確認 + PR (rev2 Step 8: end-to-end curl)

- [ ] **Step 1: workers/ 全 test pass 確認**

```bash
cd workers && npm test
```

Expected: 全 PASS (約 50 tests: health 1 + hmac 4 + turnstile 5 + token 6 + submit 8 + history 4 + delete 3 + pii-redact 10 + rate-limit 5 + validation 8 + critical 4)

- [ ] **Step 2: wrangler dev で end-to-end curl 確認**

```bash
npm run dev
# 別ターミナル
# 1. health
curl http://localhost:8787/v1/health

# 2. token request (Cloudflare test secret 利用)
curl -X POST http://localhost:8787/v1/reports/token \
  -H 'Content-Type: application/json' \
  -d '{"turnstile_response": "dummy", "scope": "submit"}'
# → token を取り出す

# 3. submit (token を埋める)
TOKEN="..."
curl -X POST http://localhost:8787/v1/reports/submit \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"uuid_hash\":\"$(printf 'a%.0s' {1..64})\",\"url\":\"https://example.com/article\",\"memo\":\"overlay\"}"

# 4. history token + history fetch
curl -X POST http://localhost:8787/v1/reports/token -H 'Content-Type: application/json' -d '{"turnstile_response":"d","scope":"history"}'
H_TOKEN="..."
curl -X POST http://localhost:8787/v1/reports/history \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$H_TOKEN\",\"uuid_hash\":\"$(printf 'a%.0s' {1..64})\"}"
```

Expected: 全成功、submit 結果が history に反映、PII redact 含む memo が正しく mask される

- [ ] **Step 3: PR 作成**

```bash
gh pr create --base feature/v3.0-learning-adblock --title "feat(v3): Cloudflare Workers backbone (Phase 1 complete)"  --body "$(cat <<'EOF'
## Summary
- Workers project init with D1 + Turnstile + Wrangler
- 5 migrations: reports / rule_candidates / abuse_log / bans / deletion_requests
- /v1/health endpoint
- HMAC ephemeral token sign/verify (subject/expires/scope, 5min)
- Turnstile verify lib + /v1/reports/token endpoint
- /v1/reports/submit (URL validation + PII redact + critical list + rate limit + D1 INSERT)
- /v1/reports/history (HMAC scope check + JOIN abuse_log for memo_redacted)
- /v1/reports/delete (stub, full impl in Plan C)

## Tests
- ~50 Vitest cases (handlers + libs)
- E2E curl verified locally with wrangler dev

## Production constraints honored
- Cloudflare Paid plan disabled (per memory feedback_no_silent_paid_infra)
- Hard cap 80k req/day enforced in code (rate-limit lib)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: kureho 承認後 merge**

### Chunk 2 完了 → Chunk 3 (Tab B UI、既に詳細化済み)

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

### Task 3.4: ReportFormViewModel (validation + state) TDD

入力フォームの state と validation を ViewModel として独立、SwiftUI View からテスト可能に切り離す。
spec §2 入力 validation 仕様: URL は `https://` 必須・200 字以内、memo は 200 字以内・URL 含むと拒否。Turnstile/rate limit はサーバ側で hard enforce、端末側は UX のため UI 抑止のみ。

**Files:**
- Create: `App/ReportTab/ReportFormViewModel.swift`
- Create: `App/ReportTab/URLValidator.swift` (テスト可能 pure 関数)
- Create: `Tests/App/ReportTab/ReportFormViewModelTests.swift`
- Create: `Tests/App/ReportTab/URLValidatorTests.swift`

#### 仕様詳細

| 項目 | ルール |
|---|---|
| URL 必須 | `https://` プレフィックス必須 (`http://` 拒否) |
| URL 長さ | 200 字以内 |
| URL 構造 | `URLComponents` で parse 可能、`host` 非空 |
| URL ドメイン | 7+ 文字 (`a.io` のような極短は拒否、誤入力対策) |
| memo 任意 | 0-200 字 |
| memo URL 検知 | `https?://...` パターンを含むと拒否 (spam 対策) |
| memo 改行 | 許可 (5 行まで) |
| state machine | `.idle` / `.validating` / `.submitting` / `.success` / `.error(APIError)` |

- [ ] **Step 1: URLValidator failing test**

`Tests/App/ReportTab/URLValidatorTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class URLValidatorTests: XCTestCase {
    func testValidURL_https_passes() {
        XCTAssertEqual(URLValidator.validate("https://example.com"), .valid(URL(string: "https://example.com")!))
    }

    func testValidURL_withPathAndQuery_passes() {
        let result = URLValidator.validate("https://example.com/article/123?q=test")
        if case .valid(let url) = result {
            XCTAssertEqual(url.host, "example.com")
        } else {
            XCTFail("Expected valid")
        }
    }

    func testHTTP_isRejected() {
        XCTAssertEqual(URLValidator.validate("http://example.com"), .invalid(.httpNotAllowed))
    }

    func testEmpty_isRejected() {
        XCTAssertEqual(URLValidator.validate(""), .invalid(.empty))
    }

    func testWhitespaceOnly_isRejected() {
        XCTAssertEqual(URLValidator.validate("   "), .invalid(.empty))
    }

    func testTooLong_isRejected() {
        let long = "https://example.com/" + String(repeating: "a", count: 200)
        XCTAssertEqual(URLValidator.validate(long), .invalid(.tooLong))
    }

    func testNoScheme_isRejected() {
        XCTAssertEqual(URLValidator.validate("example.com"), .invalid(.malformed))
    }

    func testEmptyHost_isRejected() {
        XCTAssertEqual(URLValidator.validate("https://"), .invalid(.malformed))
    }

    func testShortDomain_isRejected() {
        XCTAssertEqual(URLValidator.validate("https://a.io"), .invalid(.suspiciouslyShort))
    }

    func testIPAddress_passesIfValid() {
        if case .valid = URLValidator.validate("https://192.168.1.1/page") {
            // expected
        } else {
            XCTFail("IP host should pass")
        }
    }

    func testTrailingSpace_trimmedAndAccepted() {
        if case .valid(let url) = URLValidator.validate(" https://example.com  ") {
            XCTAssertEqual(url.absoluteString, "https://example.com")
        } else {
            XCTFail("Trimmed should pass")
        }
    }

    func testJapaneseDomain_isAccepted() {
        if case .valid = URLValidator.validate("https://日本語.example.jp/path") {
            // Punycode 経由でも OK
        } else {
            XCTFail("Japanese domain should pass")
        }
    }
}
```

- [ ] **Step 2: test 実行 → fail 確認**

Expected: FAIL (URLValidator 未定義)

- [ ] **Step 3: URLValidator.swift 実装**

`App/ReportTab/URLValidator.swift`:

```swift
import Foundation

enum URLValidator {
    enum Result: Equatable {
        case valid(URL)
        case invalid(Reason)
    }

    enum Reason: Equatable {
        case empty
        case httpNotAllowed
        case tooLong
        case malformed
        case suspiciouslyShort

        var userMessage: String {
            switch self {
            case .empty: return "URL を入力してください"
            case .httpNotAllowed: return "https:// で始まる URL を入力してください"
            case .tooLong: return "URL が長すぎます (200 文字以内)"
            case .malformed: return "URL の形式が正しくありません"
            case .suspiciouslyShort: return "ドメインが短すぎる可能性があります"
            }
        }
    }

    static let maxLength = 200
    static let minDomainLength = 7  // "a.b.com" 最小

    static func validate(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(.empty) }
        guard trimmed.count <= maxLength else { return .invalid(.tooLong) }
        guard trimmed.lowercased().hasPrefix("https://") else {
            if trimmed.lowercased().hasPrefix("http://") {
                return .invalid(.httpNotAllowed)
            }
            return .invalid(.malformed)
        }
        guard let components = URLComponents(string: trimmed),
              let host = components.host,
              !host.isEmpty else {
            return .invalid(.malformed)
        }
        // Punycode 後の長さで判定
        let asciiHost = host.idnaEncoded ?? host
        guard asciiHost.count >= minDomainLength else {
            return .invalid(.suspiciouslyShort)
        }
        guard let url = components.url else {
            return .invalid(.malformed)
        }
        return .valid(url)
    }
}

// Note: Punycode 変換は iOS では URL が IDN を透過的に扱うので簡易実装
private extension String {
    var idnaEncoded: String? {
        return self  // iOS では URL が透過扱い、host.count で日本語ドメインは長く判定される
    }
}
```

- [ ] **Step 4: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/URLValidatorTests
```

Expected: 12 tests passed

- [ ] **Step 5: MemoValidator (URL 検知 + 長さ) failing test**

`Tests/App/ReportTab/MemoValidatorTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class MemoValidatorTests: XCTestCase {
    func testEmpty_isValid() {
        XCTAssertEqual(MemoValidator.validate(""), .valid)
    }

    func testTypicalMemo_isValid() {
        XCTAssertEqual(MemoValidator.validate("動画上のオーバーレイ広告"), .valid)
    }

    func testTooLong_isRejected() {
        let long = String(repeating: "a", count: 201)
        XCTAssertEqual(MemoValidator.validate(long), .invalid(.tooLong))
    }

    func testContainsHTTPSURL_isRejected() {
        XCTAssertEqual(
            MemoValidator.validate("これ https://example.com で表示されてる"),
            .invalid(.containsURL)
        )
    }

    func testContainsHTTPURL_isRejected() {
        XCTAssertEqual(
            MemoValidator.validate("http://spam.com を見ろ"),
            .invalid(.containsURL)
        )
    }

    func testMultiline_5LinesOk() {
        let memo = "1\n2\n3\n4\n5"
        XCTAssertEqual(MemoValidator.validate(memo), .valid)
    }

    func testMultiline_6LinesRejected() {
        let memo = "1\n2\n3\n4\n5\n6"
        XCTAssertEqual(MemoValidator.validate(memo), .invalid(.tooManyLines))
    }
}
```

- [ ] **Step 6: MemoValidator.swift 実装**

`App/ReportTab/URLValidator.swift` に追加 (or 別ファイル):

```swift
enum MemoValidator {
    enum Result: Equatable {
        case valid
        case invalid(Reason)
    }

    enum Reason: Equatable {
        case tooLong
        case containsURL
        case tooManyLines

        var userMessage: String {
            switch self {
            case .tooLong: return "メモは 200 文字以内で入力してください"
            case .containsURL: return "メモに URL を入れないでください。URL は上の欄に入力してください"
            case .tooManyLines: return "メモは 5 行以内で入力してください"
            }
        }
    }

    static let maxLength = 200
    static let maxLines = 5

    private static let urlPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"https?://[^\s]+"#, options: [.caseInsensitive])
    }()

    static func validate(_ raw: String) -> Result {
        guard raw.count <= maxLength else { return .invalid(.tooLong) }
        let lineCount = raw.components(separatedBy: .newlines).count
        guard lineCount <= maxLines else { return .invalid(.tooManyLines) }
        let range = NSRange(raw.startIndex..., in: raw)
        if urlPattern.firstMatch(in: raw, options: [], range: range) != nil {
            return .invalid(.containsURL)
        }
        return .valid
    }
}
```

- [ ] **Step 7: test pass 確認** + commit MemoValidator + URLValidator together

```bash
git add App/ReportTab/URLValidator.swift \
        Tests/App/ReportTab/URLValidatorTests.swift Tests/App/ReportTab/MemoValidatorTests.swift
git commit -m "feat(v3): add URLValidator + MemoValidator pure functions

- URL: https-only, 200 char max, parse validity, min domain length
- Memo: 200 char max, 5 lines max, no embedded URLs (spam guard)
- 19 tests across both"
```

- [ ] **Step 8: ReportFormViewModel failing test**

`Tests/App/ReportTab/ReportFormViewModelTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

@MainActor
final class ReportFormViewModelTests: XCTestCase {
    private var api: MockReportAPIClient!
    private var vm: ReportFormViewModel!
    private var successCallCount = 0

    override func setUp() async throws {
        try await super.setUp()
        api = MockReportAPIClient()
        successCallCount = 0
        vm = ReportFormViewModel(
            apiClient: api,
            onSuccess: { [weak self] in self?.successCallCount += 1 }
        )
    }

    func testInitialState_isIdleAndCannotSubmit() {
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.canSubmit)
    }

    func testValidURL_emptyMemo_canSubmit() {
        vm.urlInput = "https://example.com/x"
        vm.memoInput = ""
        XCTAssertTrue(vm.canSubmit)
        XCTAssertNil(vm.urlError)
        XCTAssertNil(vm.memoError)
    }

    func testInvalidURL_cannotSubmit_andShowsError() {
        vm.urlInput = "http://example.com"
        XCTAssertFalse(vm.canSubmit)
        XCTAssertEqual(vm.urlError, URLValidator.Reason.httpNotAllowed.userMessage)
    }

    func testValidMemo_passes() {
        vm.urlInput = "https://example.com/x"
        vm.memoInput = "動画オーバーレイ"
        XCTAssertTrue(vm.canSubmit)
    }

    func testMemoWithEmbeddedURL_rejected() {
        vm.urlInput = "https://example.com/x"
        vm.memoInput = "spam https://bad.com"
        XCTAssertFalse(vm.canSubmit)
        XCTAssertEqual(vm.memoError, MemoValidator.Reason.containsURL.userMessage)
    }

    func testSubmit_validInput_callsAPIAndOnSuccess() async {
        api.stubSubmitResult = .success(SubmitResponseDTO(
            id: "01HYZ", status: "pending",
            receivedAt: Date(), memoRedacted: false
        ))
        vm.urlInput = "https://example.com/x"
        vm.memoInput = "test"

        await vm.submit()

        XCTAssertEqual(successCallCount, 1)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(api.submitCallCount, 1)
        XCTAssertEqual(api.lastSubmitURL?.absoluteString, "https://example.com/x")
        XCTAssertEqual(api.lastSubmitMemo, "test")
    }

    func testSubmit_apiRateLimitError_setsErrorState() async {
        api.stubSubmitResult = .failure(APIError.rateLimitExceeded(retryAfter: 86400))
        vm.urlInput = "https://example.com/x"

        await vm.submit()

        XCTAssertEqual(successCallCount, 0)
        if case .error(let err) = vm.state {
            if case .rateLimitExceeded = err {
                // ok
            } else { XCTFail("Wrong error: \(err)") }
        } else {
            XCTFail("Expected error state, got \(vm.state)")
        }
    }

    func testSubmit_whileSubmitting_blockedByState() async {
        api.stubSubmitResult = .success(SubmitResponseDTO(id: "x", status: "pending", receivedAt: Date(), memoRedacted: false))
        api.submitDelay = 0.1
        vm.urlInput = "https://example.com/x"

        async let first: Void = vm.submit()
        async let second: Void = vm.submit()
        _ = await [first, second]

        XCTAssertEqual(api.submitCallCount, 1, "Second submit should be blocked while first is in flight")
    }

    func testCancelError_returnsToIdle() async {
        api.stubSubmitResult = .failure(APIError.networkUnavailable)
        vm.urlInput = "https://example.com/x"
        await vm.submit()
        if case .error = vm.state {
            vm.dismissError()
            XCTAssertEqual(vm.state, .idle)
        }
    }
}

// MockReportAPIClient 拡張 (Chunk 5 で submitDelay 等を追加)
extension MockReportAPIClient {
    // 既存 fetchHistory stub に加え、submit stub を追加
    var submitCallCount: Int { _submitCallCount }
    var lastSubmitURL: URL? { _lastSubmitURL }
    var lastSubmitMemo: String? { _lastSubmitMemo }
    var stubSubmitResult: Result<SubmitResponseDTO, Error>?
    var submitDelay: TimeInterval?
}
// 詳細は MockReportAPIClient のリファクタで再構成 (Chunk 5 で先に拡張、Chunk 3 では呼び出し側)
```

- [ ] **Step 9: ReportFormViewModel.swift 実装**

`App/ReportTab/ReportFormViewModel.swift`:

```swift
import Foundation
import SwiftUI

enum ReportFormState: Equatable {
    case idle
    case submitting
    case error(APIError)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.submitting, .submitting): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

@MainActor
final class ReportFormViewModel: ObservableObject {
    @Published var urlInput: String = ""
    @Published var memoInput: String = ""
    @Published private(set) var state: ReportFormState = .idle

    private let apiClient: ReportAPIClientProtocol
    private let onSuccess: () -> Void

    init(apiClient: ReportAPIClientProtocol, onSuccess: @escaping () -> Void) {
        self.apiClient = apiClient
        self.onSuccess = onSuccess
    }

    var validatedURL: URL? {
        if case .valid(let url) = URLValidator.validate(urlInput) { return url }
        return nil
    }

    var urlError: String? {
        // 入力中は空 OK で error 出さない、空でなく invalid のときだけ表示
        guard !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if case .invalid(let reason) = URLValidator.validate(urlInput) {
            return reason.userMessage
        }
        return nil
    }

    var memoError: String? {
        guard !memoInput.isEmpty else { return nil }
        if case .invalid(let reason) = MemoValidator.validate(memoInput) {
            return reason.userMessage
        }
        return nil
    }

    var canSubmit: Bool {
        guard validatedURL != nil else { return false }
        if !memoInput.isEmpty, case .invalid = MemoValidator.validate(memoInput) { return false }
        if case .submitting = state { return false }
        return true
    }

    var memoCharCount: Int { memoInput.count }
    var memoCharRemaining: Int { MemoValidator.maxLength - memoInput.count }

    func submit() async {
        guard canSubmit, let url = validatedURL else { return }
        state = .submitting
        do {
            let memo = memoInput.isEmpty ? nil : memoInput
            _ = try await apiClient.submitReport(url: url, memo: memo)
            state = .idle
            urlInput = ""
            memoInput = ""
            onSuccess()
        } catch let err as APIError {
            state = .error(err)
        } catch {
            state = .error(APIError.decodingFailed(underlying: error))
        }
    }

    func dismissError() {
        if case .error = state { state = .idle }
    }
}
```

- [ ] **Step 10: test pass + commit**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportFormViewModelTests
# Expected: 9 tests passed

git add App/ReportTab/ReportFormViewModel.swift Tests/App/ReportTab/ReportFormViewModelTests.swift
git commit -m "feat(v3): add ReportFormViewModel with state machine + validation surfaces

- @Published urlInput / memoInput
- canSubmit / urlError / memoError computed
- submit() async with state .submitting → .idle (success) or .error
- Concurrent submit blocked by state
- 9 test cases"
```

### Task 3.5: ReportFormView (UI) 実装

ViewModel が完成したので、UI 側はその値を表示するだけ。

**Files:**
- Create: `App/ReportTab/ReportFormView.swift`
- Create: `Tests/App/ReportTab/ReportFormViewTests.swift` (snapshot/init test のみ)

- [ ] **Step 1: ReportFormView.swift 実装**

`App/ReportTab/ReportFormView.swift`:

```swift
import SwiftUI

struct ReportFormView: View {
    @StateObject private var viewModel: ReportFormViewModel
    @FocusState private var focusedField: Field?

    init(apiClient: ReportAPIClientProtocol, onSubmitSuccess: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ReportFormViewModel(apiClient: apiClient, onSuccess: onSubmitSuccess))
    }

    enum Field { case url, memo }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("https://example.com/...", text: $viewModel.urlInput)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .url)
                        Button("貼り付け") {
                            if let s = UIPasteboard.general.string {
                                viewModel.urlInput = s
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let err = viewModel.urlError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("広告があった URL")
            } footer: {
                Text("Safari のアドレスバーからコピーして貼り付けてください")
                    .font(.caption2)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("例: 動画上のオーバーレイ", text: $viewModel.memoInput, axis: .vertical)
                        .lineLimit(5, reservesSpace: true)
                        .focused($focusedField, equals: .memo)
                    HStack {
                        if let err = viewModel.memoError {
                            Text(err).font(.caption2).foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(viewModel.memoCharCount) / \(MemoValidator.maxLength)")
                            .font(.caption2)
                            .foregroundStyle(viewModel.memoCharRemaining < 20 ? .orange : .secondary)
                    }
                }
            } header: {
                Text("メモ (任意)")
            } footer: {
                Text("URL は記述しないでください (上の欄に入れてください)")
                    .font(.caption2)
            }

            Section {
                Button {
                    focusedField = nil
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        if case .submitting = viewModel.state {
                            ProgressView().controlSize(.small)
                            Text("送信中…").padding(.leading, 6)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("送信").padding(.leading, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSubmit)
            }
        }
        .navigationTitle("報告")
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: errorBinding) {
            Alert(
                title: Text("送信に失敗しました"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK")) { viewModel.dismissError() }
            )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { if case .error = viewModel.state { return true }; return false },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var errorMessage: String {
        if case .error(let err) = viewModel.state {
            return err.localizedDescription
        }
        return ""
    }
}
```

- [ ] **Step 2: ReportFormViewTests (smoke)**

```swift
@MainActor
final class ReportFormViewTests: XCTestCase {
    func testFormView_initializesWithAPIClient() {
        let api = MockReportAPIClient()
        let view = ReportFormView(apiClient: api, onSubmitSuccess: {})
        XCTAssertNotNil(view.body)
    }
}
```

- [ ] **Step 3: シミュレータで動作確認**

シナリオ:
1. URL 欄空 → 送信ボタン disabled
2. `http://example.com` 入力 → 赤エラー「https:// で始まる URL を…」、送信 disabled
3. `https://example.com` 入力 → エラー消える、送信 enabled
4. 「貼り付け」ボタンタップ → クリップボードから自動入力
5. メモ 200 文字超 → カウンタがオレンジ + エラー表示
6. メモに URL 含む → エラー
7. 送信ボタン → ProgressView 表示 → (API mock 成功) → Sent 画面へ遷移
8. API rate limit エラー → Alert 表示、OK → idle 復帰

- [ ] **Step 4: commit**

```bash
git add App/ReportTab/ReportFormView.swift Tests/App/ReportTab/ReportFormViewTests.swift
git commit -m "feat(v3): add ReportFormView with paste-from-clipboard, inline errors, char count

- URL field with paste button, https-only validation hint
- Memo TextField with line limit (5), char counter (orange warn < 20)
- Submit button with submitting state
- APIError → Alert with dismissError"
```

### Task 3.6: ReportSentView (送信完了画面) 実装

**Files:**
- Create: `App/ReportTab/ReportSentView.swift`
- Create: `Tests/App/ReportTab/ReportSentViewTests.swift`

- [ ] **Step 1: Failing test**

`Tests/App/ReportTab/ReportSentViewTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import AdblockKeshi

@MainActor
final class ReportSentViewTests: XCTestCase {
    func testSentView_buildsWithCallbacks() {
        let view = ReportSentView(onAgainTap: {}, onCloseTap: {})
        XCTAssertNotNil(view.body)
    }

    func testSentView_invokesAgainCallback() {
        var againCalled = false
        let view = ReportSentView(onAgainTap: { againCalled = true }, onCloseTap: {})
        view.onAgainTap()
        XCTAssertTrue(againCalled)
    }

    func testSentView_invokesCloseCallback() {
        var closeCalled = false
        let view = ReportSentView(onAgainTap: {}, onCloseTap: { closeCalled = true })
        view.onCloseTap()
        XCTAssertTrue(closeCalled)
    }
}
```

- [ ] **Step 2: 実装**

`App/ReportTab/ReportSentView.swift`:

```swift
import SwiftUI

struct ReportSentView: View {
    let onAgainTap: () -> Void
    let onCloseTap: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text("送信しました")
                    .font(.title2.bold())

                Text("通常 7-14 日以内、最悪 30 日以内に\n広告ブロックリストへ反映を検討します。\n結果はアプリ内通知でお知らせします。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onAgainTap) {
                    Label("もう一度報告する", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onCloseTap) {
                    Text("ブロッカー タブに戻る")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .navigationBarBackButtonHidden(true)  // 送信完了後の back ナビ抑止
    }
}

#Preview {
    NavigationStack {
        ReportSentView(onAgainTap: {}, onCloseTap: {})
    }
}
```

- [ ] **Step 3: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ReportSentViewTests
```

Expected: 3 tests passed

- [ ] **Step 4: シミュレータで preview 確認 + commit**

```bash
git add App/ReportTab/ReportSentView.swift Tests/App/ReportTab/ReportSentViewTests.swift
git commit -m "feat(v3): add ReportSentView with 'again' and 'close' CTAs (back nav disabled)"
```

### Task 3.7: Navigation pattern decision の commit (Coordinator vs @State, reviewer #1 指摘)

reviewer #1 で「Coordinator pattern or @State 管理」の選択を spec で決めるべきと指摘あり。
**確定**: `@State path: [ReportTabRoute]` enum-driven NavigationStack を採用。理由:

| 評価軸 | @State NavigationStack (採用) | Coordinator pattern |
|---|---|---|
| iOS 17+ native | ✅ NavigationStack 標準 | △ UIKit 由来、SwiftUI 適合性低 |
| 状態管理の単純さ | ✅ ルート enum + path array で完結 | △ Coordinator class + Subject 必要 |
| テスト | ✅ ReportTabView の path array を直接検証 | △ Coordinator mock 必要 |
| Tab 切り替え時の保持 | ✅ NavigationStack の path は自動保持 | △ Coordinator の lifecycle 管理必要 |
| 巨大化リスク | ◯ Route enum が増えても 1 ファイル | ✗ Coordinator 肥大化しやすい |

Chunk 5 Task 5.7 で実装した形 (NavigationStack + path: [ReportTabRoute]) をそのまま採用、本 Task 3.7 では Decision Log 記録のみ:

- [ ] **Step 1: `docs/superpowers/decisions/2026-06-07-tab-b-navigation.md` 作成**

```markdown
# Decision: Tab B 内部ナビゲーションパターン

**日付**: 2026-06-07
**決定**: `@State path: [ReportTabRoute]` を使った NavigationStack 形式を採用
**理由**: 上記表参照 (SwiftUI native, テスト容易, lifecycle 自動)

## 影響範囲
- `App/ReportTab/ReportTabView.swift` (Chunk 5 Task 5.7 で実装)
- 子 View (ReportEntryView, ReportFormView, ReportSentView, ReportHistoryView) は path に対する依存ゼロ、callback ベースで分離

## 不採用
- Coordinator pattern: UIKit-era の慣習、SwiftUI 自然ではない
- Sheet ベース: Tab B 内部は push が UX 的に自然 (sheet は別 context modal 用)
```

- [ ] **Step 2: commit**

```bash
mkdir -p docs/superpowers/decisions
git add docs/superpowers/decisions/2026-06-07-tab-b-navigation.md
git commit -m "docs(v3): record Tab B navigation pattern decision (@State NavigationStack)"
```

### Task 3.8: Chunk 3 完了確認 + PR

- [ ] **Step 1: 全 test pass** (URLValidator 12 + MemoValidator 7 + ReportFormViewModel 9 + ReportFormView 1 + ReportSentView 3 = 32 tests)

- [ ] **Step 2: シミュレータ E2E**:
1. Tab B → 報告ボタン → Form 画面表示
2. URL 不正入力 → 赤エラー + 送信 disabled
3. URL 正入力 + memo 入力 → 送信 enabled
4. 送信 → API mock 成功 → Sent 画面遷移
5. Sent → 「もう一度報告する」→ Form 画面 (入力 clear 確認)
6. Sent → 「ブロッカータブに戻る」→ Tab A 表示

- [ ] **Step 3: PR 作成**

```bash
gh pr create --base feature/v3.0-learning-adblock --title "feat(v3): Tab B form + validation + sent screens" --body "$(cat <<'EOF'
## Summary
- URLValidator: https-only, 200 char max, parse validity
- MemoValidator: 200 char max, 5 lines, no embedded URLs
- ReportFormViewModel: state machine (idle/submitting/error) with canSubmit
- ReportFormView: paste button, inline errors, char counter, alert on error
- ReportSentView: success illustration + again/close CTAs
- Decision log: @State NavigationStack chosen for Tab B nav

## Tests
- 32 new XCTest cases all passing
- E2E sim verified

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: kureho 承認後 merge**

### Chunk 3 完了 → 次は Chunk 6 (ContentRuleListState + Phase 1-2 統合)

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

### Task 6.1: ContentRuleListState (2 extension 状態検出) TDD

spec §4: 2 extension の ON/OFF 状態を検出して 4 パターンの UX に反映。
- 両方 ON → 通常
- base のみ ON → 黄バナー (Tab A) + Tab B 報告に警告
- 学習のみ ON → 赤バナー (Tab A、本体が機能しない)
- 両方 OFF → onboarding 戻し

**Files:**
- Create: `App/ContentRuleListState.swift`
- Create: `App/ContentRuleListStateChecker.swift` (protocol で抽象化、テスト時 mock)
- Create: `Tests/App/ContentRuleListStateTests.swift`

#### 仕様詳細

| 項目 | 値 |
|---|---|
| ベース extension id | `com.kureho.adblockkeshi.blocker` |
| 学習 extension id | `com.kureho.adblockkeshi.reportedblocker` |
| 状態取得 API | `SFContentBlockerManager.getStateOfContentBlocker(withIdentifier:)` |
| 取得失敗 (extension 未認識) | `disabled` 扱い (fail-safe) |
| 並行 fetch | TaskGroup or async let |
| 更新タイミング | アプリ起動時、Settings から復帰時 (`scenePhase` 監視) |

- [ ] **Step 1: ContentRuleListStateChecker protocol と enum 定義**

`App/ContentRuleListState.swift`:

```swift
import Foundation
import SafariServices

enum ContentRuleListMode: Equatable {
    case bothEnabled
    case baseOnly
    case reportedOnly
    case bothDisabled

    var isFullyOperational: Bool {
        self == .bothEnabled
    }

    var statusLabel: String {
        switch self {
        case .bothEnabled: return "広告ブロック中"
        case .baseOnly: return "広告ブロック中 (学習機能 OFF)"
        case .reportedOnly: return "⚠️ 本体ブロッカーが OFF です"
        case .bothDisabled: return "準備未完了"
        }
    }

    var bannerType: BannerType? {
        switch self {
        case .bothEnabled: return nil
        case .baseOnly: return .yellow("「広告消し 学習」を ON にすると、報告で広告ブロックが進化します")
        case .reportedOnly: return .red("「広告消し 本体」を ON にしてください。学習機能だけでは大部分の広告が通り抜けます")
        case .bothDisabled: return nil  // onboarding 戻し
        }
    }
}

enum BannerType: Equatable {
    case yellow(String)
    case red(String)
}

struct ContentRuleListSnapshot: Equatable {
    let baseEnabled: Bool
    let reportedEnabled: Bool
    let mode: ContentRuleListMode

    static func from(base: Bool, reported: Bool) -> ContentRuleListSnapshot {
        let mode: ContentRuleListMode
        switch (base, reported) {
        case (true, true): mode = .bothEnabled
        case (true, false): mode = .baseOnly
        case (false, true): mode = .reportedOnly
        case (false, false): mode = .bothDisabled
        }
        return ContentRuleListSnapshot(baseEnabled: base, reportedEnabled: reported, mode: mode)
    }
}

protocol ContentRuleListStateChecker {
    func check() async -> ContentRuleListSnapshot
}

struct SFContentBlockerStateChecker: ContentRuleListStateChecker {
    static let baseID = "com.kureho.adblockkeshi.blocker"
    static let reportedID = "com.kureho.adblockkeshi.reportedblocker"

    func check() async -> ContentRuleListSnapshot {
        async let baseState = getEnabled(identifier: Self.baseID)
        async let reportedState = getEnabled(identifier: Self.reportedID)
        let (b, r) = await (baseState, reportedState)
        return ContentRuleListSnapshot.from(base: b, reported: r)
    }

    private func getEnabled(identifier: String) async -> Bool {
        await withCheckedContinuation { cont in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, _ in
                cont.resume(returning: state?.isEnabled ?? false)
            }
        }
    }
}
```

- [ ] **Step 2: failing test**

`Tests/App/ContentRuleListStateTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

final class ContentRuleListStateTests: XCTestCase {
    func testSnapshot_bothTrue_isBothEnabled() {
        let s = ContentRuleListSnapshot.from(base: true, reported: true)
        XCTAssertEqual(s.mode, .bothEnabled)
        XCTAssertTrue(s.mode.isFullyOperational)
    }

    func testSnapshot_baseOnly() {
        let s = ContentRuleListSnapshot.from(base: true, reported: false)
        XCTAssertEqual(s.mode, .baseOnly)
        XCTAssertFalse(s.mode.isFullyOperational)
        if case .yellow(let msg) = s.mode.bannerType {
            XCTAssertTrue(msg.contains("学習"))
        } else { XCTFail("Expected yellow banner") }
    }

    func testSnapshot_reportedOnly() {
        let s = ContentRuleListSnapshot.from(base: false, reported: true)
        XCTAssertEqual(s.mode, .reportedOnly)
        if case .red(let msg) = s.mode.bannerType {
            XCTAssertTrue(msg.contains("本体"))
        } else { XCTFail("Expected red banner") }
    }

    func testSnapshot_bothDisabled() {
        let s = ContentRuleListSnapshot.from(base: false, reported: false)
        XCTAssertEqual(s.mode, .bothDisabled)
        XCTAssertNil(s.mode.bannerType)  // onboarding 戻し、banner なし
    }

    func testCheckerProtocol_mockReturnsBoth() async {
        let mock = MockContentRuleListStateChecker(baseEnabled: true, reportedEnabled: true)
        let snapshot = await mock.check()
        XCTAssertEqual(snapshot.mode, .bothEnabled)
    }
}

struct MockContentRuleListStateChecker: ContentRuleListStateChecker {
    let baseEnabled: Bool
    let reportedEnabled: Bool

    func check() async -> ContentRuleListSnapshot {
        ContentRuleListSnapshot.from(base: baseEnabled, reported: reportedEnabled)
    }
}
```

- [ ] **Step 3: test pass 確認**

```bash
xcodebuild test ... -only-testing:AdblockKeshiTests/ContentRuleListStateTests
```

Expected: 5 tests passed

- [ ] **Step 4: commit**

```bash
git add App/ContentRuleListState.swift Tests/App/ContentRuleListStateTests.swift
git commit -m "feat(v3): add ContentRuleListState with 4-pattern UX mode detection

spec §4: 2 extension state detection
- Snapshot.from(base, reported) → mode
- BannerType yellow/red per pattern
- ContentRuleListStateChecker protocol for mock testing
- SFContentBlockerStateChecker production impl with concurrent fetch
- 5 unit tests"
```

### Task 6.2: Tab A での banner 表示 + Tab B 警告連動

spec §4 §2 で「学習 OFF 時に報告タブで警告表示」。Tab A の既存 ContentView を拡張、Tab B の Entry/Form/History でも mode を参照。

**Files:**
- Modify: `App/ContentView.swift` (banner 表示追加)
- Modify: `App/ReportTab/ReportTabView.swift` (mode を取得して子 view に渡す)
- Modify: `App/ReportTab/ReportEntryView.swift` (mode.reportedOnly/bothDisabled で警告)
- Create: `App/Views/StatusBannerView.swift` (再利用可能 banner)
- Create: `Tests/App/Views/StatusBannerViewTests.swift`
- Create: `App/AppStateStore.swift` (ContentRuleListSnapshot を発行する @MainActor ObservableObject)
- Create: `Tests/App/AppStateStoreTests.swift`

- [ ] **Step 1: StatusBannerView 実装 (TDD)**

`Tests/App/Views/StatusBannerViewTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import AdblockKeshi

@MainActor
final class StatusBannerViewTests: XCTestCase {
    func testBanner_yellow_renders() {
        let view = StatusBannerView(banner: .yellow("test message"), onTap: nil)
        XCTAssertNotNil(view.body)
    }

    func testBanner_red_renders() {
        let view = StatusBannerView(banner: .red("error"), onTap: nil)
        XCTAssertNotNil(view.body)
    }

    func testBanner_invokesOnTap() {
        var tapped = false
        let view = StatusBannerView(banner: .yellow("test"), onTap: { tapped = true })
        view.onTap?()
        XCTAssertTrue(tapped)
    }
}
```

`App/Views/StatusBannerView.swift`:

```swift
import SwiftUI

struct StatusBannerView: View {
    let banner: BannerType
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.body.bold())
                    .foregroundStyle(.white)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var iconName: String {
        switch banner {
        case .yellow: return "exclamationmark.triangle.fill"
        case .red: return "xmark.octagon.fill"
        }
    }

    private var message: String {
        switch banner {
        case .yellow(let m), .red(let m): return m
        }
    }

    private var backgroundColor: Color {
        switch banner {
        case .yellow: return Color.orange
        case .red: return Color.red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBannerView(banner: .yellow("学習機能を ON にしてください"), onTap: {})
        StatusBannerView(banner: .red("本体ブロッカーが OFF です"), onTap: {})
    }
    .padding()
}
```

- [ ] **Step 2: AppStateStore (mode をアプリ全体で共有) TDD**

`Tests/App/AppStateStoreTests.swift`:

```swift
import XCTest
@testable import AdblockKeshi

@MainActor
final class AppStateStoreTests: XCTestCase {
    func testInitialState_isLoading() {
        let store = AppStateStore(checker: MockContentRuleListStateChecker(baseEnabled: false, reportedEnabled: false))
        XCTAssertNil(store.currentSnapshot)
    }

    func testRefresh_updatesSnapshot() async {
        let mock = MockContentRuleListStateChecker(baseEnabled: true, reportedEnabled: true)
        let store = AppStateStore(checker: mock)
        await store.refresh()
        XCTAssertEqual(store.currentSnapshot?.mode, .bothEnabled)
    }

    func testRefresh_baseOnly() async {
        let mock = MockContentRuleListStateChecker(baseEnabled: true, reportedEnabled: false)
        let store = AppStateStore(checker: mock)
        await store.refresh()
        XCTAssertEqual(store.currentSnapshot?.mode, .baseOnly)
    }

    func testRefresh_bothDisabled_triggersOnboarding() async {
        let mock = MockContentRuleListStateChecker(baseEnabled: false, reportedEnabled: false)
        let store = AppStateStore(checker: mock)
        await store.refresh()
        XCTAssertEqual(store.currentSnapshot?.mode, .bothDisabled)
        XCTAssertTrue(store.shouldShowOnboarding)
    }
}
```

`App/AppStateStore.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
final class AppStateStore: ObservableObject {
    @Published private(set) var currentSnapshot: ContentRuleListSnapshot?

    private let checker: ContentRuleListStateChecker

    init(checker: ContentRuleListStateChecker = SFContentBlockerStateChecker()) {
        self.checker = checker
    }

    func refresh() async {
        let snapshot = await checker.check()
        currentSnapshot = snapshot
    }

    var shouldShowOnboarding: Bool {
        currentSnapshot?.mode == .bothDisabled
    }
}
```

- [ ] **Step 3: ContentView (Tab A) に banner 統合**

`App/ContentView.swift` を Modify:

```swift
struct ContentView: View {
    @EnvironmentObject var appState: AppStateStore

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = appState.currentSnapshot, let banner = snapshot.mode.bannerType {
                StatusBannerView(banner: banner, onTap: {
                    // Settings へ誘導
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            // 既存の Tab A コンテンツ
            existingTabAContent
        }
        .task { await appState.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await appState.refresh() } }
        }
    }

    @Environment(\.scenePhase) var scenePhase

    @ViewBuilder
    private var existingTabAContent: some View {
        // 既存 ContentView の中身 (準備する/状態表示/フィルタ最終更新日 等)
        // ...
    }
}
```

- [ ] **Step 4: ReportTabView/ReportEntryView でも mode 連動**

```swift
struct ReportTabView: View {
    let apiClient: ReportAPIClientProtocol
    let historyCache: ReportHistoryCache
    @EnvironmentObject var appState: AppStateStore

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if let snapshot = appState.currentSnapshot {
                    if snapshot.mode == .reportedOnly {
                        StatusBannerView(banner: snapshot.mode.bannerType!, onTap: {
                            // Settings へ
                        })
                    } else if snapshot.mode == .baseOnly {
                        // 報告タブ特有: 学習機能 OFF 時の警告
                        StatusBannerView(banner: .yellow("『広告消し 学習』が OFF です。今報告しても、ON にしないとブロックされません"), onTap: {})
                    }
                }
                ReportEntryView(onReportTap: { ... }, onHistoryTap: { ... })
                    .navigationDestination(...)
            }
        }
    }
}
```

- [ ] **Step 5: AdblockKeshiApp.swift で AppStateStore を environmentObject 化**

```swift
@main
struct AdblockKeshiApp: App {
    @StateObject private var appState = AppStateStore()

    var body: some Scene {
        WindowGroup {
            TabView { ... }
                .environmentObject(appState)
        }
    }
}
```

- [ ] **Step 6: test pass + シミュレータで 4 パターン目視確認**

シナリオ:
1. 両方 ON → banner 表示なし、Tab A 通常、Tab B 通常
2. base ON 学習 OFF → Tab A 黄バナー、Tab B 黄バナー (報告タブでは異なる文言)
3. base OFF 学習 ON → Tab A 赤バナー、Tab B 赤バナー
4. 両方 OFF → 自動 onboarding 表示

- [ ] **Step 7: commit**

```bash
git add App/Views/StatusBannerView.swift App/AppStateStore.swift App/ContentView.swift \
        App/ReportTab/ReportTabView.swift App/AdblockKeshiApp.swift \
        Tests/App/Views/StatusBannerViewTests.swift Tests/App/AppStateStoreTests.swift
git commit -m "feat(v3): integrate 4-pattern UX with AppStateStore + StatusBannerView

- AppStateStore: shared @EnvironmentObject for snapshot
- ContentView (Tab A): banner above main content, scenePhase refresh
- ReportTabView (Tab B): pattern-specific banner (different copy than Tab A)
- Settings deep-link on banner tap
- 7 tests"
```

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
