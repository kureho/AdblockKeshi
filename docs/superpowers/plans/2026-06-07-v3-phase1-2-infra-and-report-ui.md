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

### Task 4.1: 子ブランチ `feat/v3-device-uuid-and-api-client`

### Task 4.2: DeviceUUIDStore (Keychain 管理) TDD

**Files:**
- Create: `App/Storage/DeviceUUIDStore.swift`
- Create: `Tests/App/Storage/DeviceUUIDStoreTests.swift`

- [ ] **Step 1-5: Keychain UUID 取得/生成、SHA-256(uuid + server_salt) ハッシュ生成、TDD で test → impl → commit**

注意: server_salt は CDN feature-flags.json から取得 (Workers /v1/reports/token response にも含める)。詳細は Phase 5 で確定、Phase 2 は hardcoded test value で進める。

### Task 4.3: HMACTokenStore (token caching) TDD

### Task 4.4: ReportAPIClient (URLSession + Workers endpoint client) TDD

**Files:**
- Create: `App/Networking/ReportAPIClient.swift`
- Create: `App/Networking/APIError.swift`
- Create: `Tests/App/Networking/ReportAPIClientTests.swift`, `APIErrorTests.swift`

API 仕様:
- `func requestToken(turnstileResponse: String, scope: TokenScope) async throws -> Token`
- `func submitReport(token: Token, url: URL, memo: String?) async throws`
- `func fetchHistory(token: Token) async throws -> [ReportHistoryItem]`
- `func requestDeletion(token: Token, urlPathHash: String?) async throws`

- [ ] **Step 1-N: URLSession の inject 可能なテストハーネス + Workers レスポンス fixture + mock URLProtocol で full coverage**

### Task 4.5: ReportFormView と APIClient の接続

- [ ] **Step 1-N: フォーム送信 → APIClient → Workers 実通信 → 成功 → SentView 遷移、エラー → Form に戻る + Toast**

### Chunk 4 完了 → PR

---

## Chunk 5: Phase 2 - 履歴 UI (Tab B Sub-screen)

**目的: 自分の報告履歴を Tab B から閲覧できる UI、ステータスバッジと PII redact 注記バッジを実装**。

### Task 5.1: 子ブランチ `feat/v3-history-ui`

### Task 5.2: ReportHistoryView 実装 (TDD)

- [ ] List view、空状態、loading、error 状態、pull-to-refresh

### Task 5.3: ReportHistoryItemView 実装 (TDD)

- [ ] Status badge 5 色 (pending/validating/approved/rejected_*)
- [ ] PII redact 注記バッジ (rev4 §2 仕様)

### Task 5.4: ReportHistoryCache (UserDefaults キャッシュ)

- [ ] 起動時 cached を即表示、background で API fetch、新しいデータで上書き

### Task 5.5: Tab B 内部ナビ統合 (Entry → Form → Sent → History 戻り経路)

### Chunk 5 完了 → PR

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
