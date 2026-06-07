<!-- [paid-approved-by-kureho] Plan C for v3.0 Phase 5 implementation -->
# 広告消し v3.0 Phase 5 実装プラン (abuse 自動化 + UI 仕上げ + Privacy)

> **For agentic workers:** controller-driven or subagent-driven execution.

**Goal:** spec rev4 §4 §6 abuse 自動化 (4 段階 ban level up) + Tab A/B banner 統合 + moat 可視化 + feature flag (RemoteConfigStore + emergency_kill_switch) + Privacy Policy 更新 + 実 ReportAPIClient + Turnstile WebView 統合。kureho ゼロタッチ運用の完成。

**Architecture:** ban engine は GitHub Actions hourly-aggregation 内で abuse_log 集計 + bans table upsert。iOS 側で AppStateStore を Tab A/B に環境配置、StatusBannerView を ContentView + ReportTabView 上部に displace。RemoteConfigStore は CDN feature-flags.json fetch + UserDefaults キャッシュ。

**Tech Stack:** Workers + Actions (既存) / iOS SwiftUI (Phase 5 で onboarding 改修も) / kureho.app/apps/adblock-keshi/privacy (app-support repo).

**Scope:** Plan C は Phase 5 (Week 10-12) の 3 週分。

**spec 参照:** `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` §2 §4 §6

---

## File Structure

### Workers + Actions (Plan B 拡張)

```
workers/src/lib/
├── ban-engine.ts                # 既存 Plan B (4 段階 ban level up)
└── ban-engine.test.ts            # 重み付け logic test
scripts/aggregation/
└── aggregate-reports.ts          # 既存 + abuse_log を集計し ban level up
```

### iOS (Phase 5 主体)

```
App/
├── AdblockKeshiApp.swift        # 実 ReportAPIClient inject に切替
├── ContentView.swift             # banner 統合 (top に StatusBannerView 配置)
├── ReportTab/ReportTabView.swift # banner 統合 + 学習 OFF 警告
├── Networking/
│   ├── ReportAPIClient.swift    # 完成 (Turnstile WebView 統合)
│   └── TurnstileWebView.swift   # 新規: SwiftUI WebView wrapper
├── RemoteConfig/
│   ├── RemoteConfigStore.swift  # 新規
│   └── FeatureFlags.swift        # 新規 (report_tab_enabled, emergency_kill_switch)
└── Models/ReportHistoryItem.swift # detail 表示拡張

docs/cdn/                         # 既存
├── feature-flags.json            # 新規: { report_tab_enabled, emergency_kill_switch, version }
└── version.json                  # rev3 仕様で reported.* 追加 (Plan B でやってる場合は skip)
```

### Privacy Policy (app-support repo、別 PR)

`apps/adblock-keshi/privacy/page.tsx` に新規セクション追加:
- 報告データの取り扱い
- 24h 対応コミット (実態は 1h SLA)
- 削除依頼窓口
- 保管インフラ (Cloudflare APAC)
- Nutrition Label との整合

---

## Chunk 1: abuse 自動化 (4 段階 ban level up)

### Task 1.1: lib/ban-engine.ts 実装

仕様 (spec rev4 §4 rev3 fix):
- abuse_log を `ban 加算対象 reason` で filter (rate_limit/spam_memo/invalid_url/critical_domain)
- `pii_redacted` は ban 加算除外
- 過去 24h で abuse_count ≥ 3 → ban level 1 (24h)
- ≥ 10 → level 2 (7d), ≥ 30 → level 3 (30d), ≥ 100 → level 4 (permanent)
- bans table upsert、expires_at 更新

- [ ] **Step 1-5: TDD で実装、12 tests pass**

### Task 1.2: hourly-aggregation.yml に組み込み

- [ ] **Step 1**: 既存 workflow で aggregate-reports.ts 実行後、ban-engine.ts 実行
- [ ] **Step 2**: smoke test

---

## Chunk 2: iOS Tab A/B banner 統合

### Task 2.1: ContentView (Tab A) に banner 統合

```swift
struct ContentView: View {
    @EnvironmentObject var appState: AppStateStore
    
    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = appState.currentSnapshot, let banner = snapshot.mode.bannerType {
                StatusBannerView(banner: banner, onTap: {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                })
                .padding(.horizontal, 16)
            }
            existingContent
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await appState.refresh() } }
        }
    }
}
```

- [ ] **Step 1**: ContentView.swift Read + Modify
- [ ] **Step 2**: 4 パターン UX シミュレータ verify

### Task 2.2: ReportTabView (Tab B) に banner 統合 (報告タブ特有の文言)

- [ ] **Step 1**: ReportTabView に banner 配置 (Tab A と異なる文言)
- [ ] **Step 2**: 学習 OFF 時の警告 (報告タブで「ON にしないと反映されません」)

### Task 2.3: PR + reviewer

---

## Chunk 3: RemoteConfigStore + feature flag

### Task 3.1: lib RemoteConfigStore.swift 実装

```swift
final class RemoteConfigStore {
    static let shared = RemoteConfigStore()
    private let url = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/feature-flags.json")!
    
    func fetchAndUpdate() async { /* UserDefaults キャッシュ + 60 分 TTL */ }
    func boolValue(forKey key: String, default: Bool) -> Bool { /* キャッシュ読み */ }
}
```

- [ ] **Step 1-5: TDD で実装、fail-open 仕様**
- [ ] **Step 6: emergency_kill_switch fail-CLOSED 実装**

### Task 3.2: docs/cdn/feature-flags.json 初期版

```json
{ "report_tab_enabled": true, "emergency_kill_switch": false, "version": "v2" }
```

### Task 3.3: ReportTabView に flag check 組み込み

- [ ] **Step 1**: AppDelegate or AdblockKeshiApp で起動時 fetchAndUpdate
- [ ] **Step 2**: TabView の Tab B を `if FeatureFlags.reportTabEnabled` で表示制御

### Task 3.4: PR + reviewer

---

## Chunk 4: 実 ReportAPIClient + Turnstile WebView 統合

### Task 4.1: TurnstileWebView.swift 実装 (SwiftUI WebView wrapper)

Cloudflare Turnstile widget を WKWebView 内に描画、challenge 完了で `turnstile_response` を取得。

- [ ] **Step 1-N: WKWebView wrapper, challenge コールバック**

### Task 4.2: ReportFormViewModel に Turnstile 統合

- [ ] **Step 1**: 送信前に TurnstileWebView を sheet で開く
- [ ] **Step 2**: 完了したら apiClient.requestToken(turnstileResponse, scope: .submit) → apiClient.submitReport(...)

### Task 4.3: StubReportAPIClient を削除、AdblockKeshiApp で実 ReportAPIClient inject

- [ ] **Step 1**: baseURL を Info.plist の API_BASE_URL から取得 (debug = localhost, release = 本番 Workers URL)
- [ ] **Step 2**: シミュレータ + 実機 E2E で報告送信成功 verify

### Task 4.4: 履歴 UI を実 API に接続

- [ ] **Step 1**: fetchHistory() を実 Workers /v1/reports/history に向ける
- [ ] **Step 2**: cached → loaded 遷移を verify

### Task 4.5: PR + reviewer

---

## Chunk 5: moat 可視化 (完了画面)

### Task 5.1: ContentView (Tab A) に「フィルタ最終更新 / 本体 N 件 / 報告で追加 M 件 (先月 +K 件)」表示

- [ ] **Step 1**: ContentView の完了状態カードに version.json から `reported.rule_count` + `reported.added_last_month` を読んで表示
- [ ] **Step 2**: シミュレータで verify

### Task 5.2: PR + reviewer

---

## Chunk 6: Privacy Policy 更新 (別 repo)

### Task 6.1: app-support repo の `apps/adblock-keshi/privacy/page.tsx` に新規セクション

spec rev4 §6-5 の文案をそのまま反映:
- 報告データの収集項目 / 利用目的 / 保持期間 / 第三者提供なし
- データ削除依頼: 24h SLA (実態 1h)
- 削除窓口 (info@kureho.app + /v1/reports/delete)
- abuse 対応: 自動 ban システム
- 保管インフラ (Cloudflare Workers/D1 APAC)

- [ ] **Step 1**: app-support repo で別 PR
- [ ] **Step 2**: vercel --prod で deploy
- [ ] **Step 3**: PR + reviewer

### Task 6.2: ASC App Privacy (Nutrition Label) 更新

- [ ] **Step 1**: ASC API で User Content + Identifiers を Linked declare に変更
- [ ] **Step 2**: 4 点監査

---

## Plan C 完了 DoD

1. ✅ abuse_log → 4 段階 ban level up 自動化
2. ✅ Tab A/B banner 統合 + 4 パターン UX verify
3. ✅ RemoteConfigStore + feature flag (emergency_kill_switch 動作確認)
4. ✅ 実 ReportAPIClient + Turnstile WebView E2E (実機で報告送信成功)
5. ✅ 履歴 UI が実 API で動作 + moat 可視化
6. ✅ Privacy Policy 更新 + Nutrition Label declare 変更
7. ✅ 全 test pass (Workers + iOS)

---

**(end of Plan C, 2026-06-07)**
