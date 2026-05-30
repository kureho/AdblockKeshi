# Plan B 完了レポート (v0.2.0-plan-b)

**完了日**: 2026-05-30
**spec**: `~/claude/docs/superpowers/specs/2026-05-30-adblock-design.md`
**plan**: `~/claude/docs/superpowers/plans/2026-05-30-adblock-keshi-plan-b-cdn-pipeline.md`

## 着手前判断確定（kureho）

- **判断1**: GitHub リポジトリ = **public** → https://github.com/kureho/AdblockKeshi
- **判断2**: CDN URL 戦略 = **β（GitHub Pages 自前ミラー優先 + 上流fallback）**

## 達成事項

### License audit
- SafariConverterLib = GPL-3.0 (CLI 利用なのでアプリ全体 GPL 化不要、mere aggregation 成立)
- 全 LICENSE 全文を App/Resources/Licenses/ に同梱
- spec §5 の Acknowledgements 義務満たす

### Filter pipeline
- **5本構成**（spec の 6本から EasyList Japanese を除外、AdGuard Japanese で代替）
  - EasyList (CC-BY-SA-3.0) / EasyPrivacy (CC-BY-SA-3.0)
  - AdGuard Base / Japanese / Annoyances (GPL-3.0)
- 理由: EasyList Japanese 専用 repo が公式に存在しない（要追加調査でも 404 確認）
- 統合変換結果: **150,000 ルール / 23.8MB / SHA256 `6c9252e5...`**

### CDN
- GitHub Pages 有効化 (main /docs path)
- URL: https://kureho.github.io/AdblockKeshi/cdn/blockerList.json
- version.json: https://kureho.github.io/AdblockKeshi/cdn/version.json
- HTTP 200 配信確認、SHA256 一致

### Aplication
- `Shared/FilterDownloader` (async/await, URLSession, atomic write, JSON validity check)
- `App/BackgroundTaskManager` (BGTaskScheduler, weekly refresh)
- `ContentView.task { downloadAndReload() }` 起動時取得 + `SFContentBlockerManager.reloadContentBlocker`
- `project.yml`: UIBackgroundModes + BGTaskSchedulerPermittedIdentifiers

### CI/CD
- `.github/workflows/monthly-filter-update.yml`: macos-latest, 毎月1日 03:00 UTC
- 変換 → diff 検出 → auto commit + push
- セキュリティ: schedule + workflow_dispatch のみ、untrusted input なし

### 動作確認（シミュレータ自動）
- iPhone 17 (iOS 26.3.1) でアプリ起動
- App Group コンテナに 23.8MB blockerList.json 書き込み確認
- パス: `Containers/Shared/AppGroup/.../blockerList.json`
- file timestamp = 起動時刻 = FilterDownloader が正常実行された証拠

### Test (12/12 passing)
- BlockerListResolverTests (5)
- ContentBlockerStateCheckerTests (4)
- **FilterDownloaderTests (3)** ← Plan B 追加

## Plan B 残タスク（kureho 1回確認、Plan C 着手時に1分だけ）

実 Safari で広告ブロックが効くかの最終目視確認:
1. シミュレータで「広告消し」アプリ起動済
2. 設定 → Safari → 機能拡張 → 「広告消し」→ ON
3. Safari で `https://www.adblock-tester.com/` 開く
4. Block 率 ≥ 90% 期待
5. スクショ `docs/screenshots/phase-b-final.png` 保存

## 次の Plan

- **Plan C**: App Store 提出物（スクショ・メタデータ・実機テスト・審査提出）
- **Plan D**: SNS プロモ動画クリエイティブ + X¥1,500プロモ実行

## Repository

- https://github.com/kureho/AdblockKeshi (public)
- Tag: `v0.2.0-plan-b`
- CDN: https://kureho.github.io/AdblockKeshi/cdn/
