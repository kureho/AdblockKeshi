# A-88 ルール生成〜配信の地図（2026-09-27・読み取り専用調査）

4.4.0 で「基本保護＝セキュリティ＋広告前半」「2 本目＝ポップアップ＋報告由来＋広告後半」に分け直すために触るファイルを特定する。コード変更なし。

## 1. 生成（CDN ファイル別）

| CDN 出力 | 生成スクリプト | 入力 | 上限・順序 | 実行契機 |
|---|---|---|---|---|
| `docs/cdn/blockerList.json`（広告 15 万件） | `scripts/convert.sh:62-78`（SafariConverterLib） | `scripts/filters.yml:10-21` の4リスト。easyprivacy→adguard-japanese→adguard-base→easylist の順で `cat`（convert.sh:56-57） | 150,000 超で exit 1（convert.sh:72-75） | `.github/workflows/monthly-filter-update.yml`（毎月1日03:00 UTC・macOS runner・SafariConverterLib を毎回 clone+swift build） |
| `docs/cdn/version.json` | `scripts/convert.sh:100-112` | sha256・ルール数・filters配列・**既存 `reported` セクションを保持**（convert.sh:95-98） | - | 同上。`App/Resources/version.json` にもコピー（convert.sh:112） |
| `docs/cdn/security-rules.json`（3万件） | `scripts/build_security_rules.py` | URLhaus + Phishing.Database、Tranco top1M を除外（build_security_rules.py:103-114） | `limit=30000`（:96,127） | `.github/workflows/build-security-rules.yml`（毎週日曜0:00 UTC・ubuntu） |
| `docs/cdn/merged-rules.json`（13万件・**中身セキュリティ0件**） | `scripts/build_merged_rules.py` | 公開中の `blockerList.json`（ad・150k）をCDNから curl 取得（build-security-rules.yml:59-65）＋ 上の security-rules（3万） | `limit=130000`（build_merged_rules.py:16,37）、**ad→security順**（:21）で ad が先に130kへ到達し security が1件も入らない | build-security-rules.yml:67-73（**ad生成の monthly-filter-update.yml とは別workflow・別スケジュール**） |
| `docs/cdn/empty-rules.json` | `scripts/build_empty_rules.py` | 常に `[]` | - | build-security-rules.yml:55-57 |
| `docs/cdn/version-security.json` | build-security-rules.yml:81-92（インラインpython） | 上3ファイルの sha256/bytes | - | 同workflow |
| `PopunderBlockerExtension/Resources/popunder-rules.json` ＋ `docs/cdn/popunder-rules.json`（40件） | `scripts/build_popunder_rules.py` | `tasks/b-popunder-script/popunder-script-networks.txt`（L1・31件）＋`popunder-aggressive-sites.json`（L2・9件、block→ignore-previous-rules） | `MAX_RULES=50000`（:102）、**L1→L2順**（:105-109） | `.github/workflows/popunder-rules-update.yml`（push時path trigger・main限定・workflow_dispatch。**2箇所同時に書き込み＝bundle同梱版とCDN版が常に同一**:46-47） |
| `docs/cdn/rules-reported.json` | `scripts/sync/reported-rules-build.ts` | Cloudflare D1 `rule_candidates` の `status='stable'`（LIMIT 200000・:88,96） | - | `.github/workflows/weekly-cdn-sync.yml`（毎週火曜05:00 UTC）。**現状0件**（実データ未反映=`tasks/report-pipeline-audit-2026-09-27.md`） |

DNS（`docs/cdn/dns-rules.json`・`PacketTunnelExtension`）は別パイプライン（`scripts/build_dns_rules.py`）で本件のスコープ外（Safari Content Blocker ではない・per-site 例外も非対応）。

## 2. 同梱（アプリ bundle）

| ファイル | 更新者 | 備考 |
|---|---|---|
| `Extension/Resources/{ad-rules,merged-rules,security-rules,empty-rules}.json` | **手動**（CI 同期なし・grep 確認済み） | `App/Resources/bundled-rules-info.json:2` に generated_at=2026-06-02 と明記。**2026-06-02 のスナップショットのまま3ヶ月以上更新されていない**（初回起動でCDN未取得時のfail-safe用途なので実害は小さいが、差し替えたらこのJSONも更新する規約） |
| `PopunderBlockerExtension/Resources/popunder-rules.json` | **自動**（popunder-rules-update.yml が commit） | CDN版と同一内容が常に保証される |

## 3. 届き方（App→AppGroup→拡張）

### 3-1. トグル4通りと基本保護が返すファイル（`Shared/BlockerListResolver.swift:92-98`）
| adEnabled | securityEnabled | filename | 中身 |
|---|---|---|---|
| true | true | merged-rules.json | 広告13万+セキュリティ0件 |
| true | false | ad-rules.json | 広告15万 |
| false | true | security-rules.json | セキュリティ3万 |
| false | false | empty-rules.json | 空（常にbundle固定・App Group/combinedを一切見ない：BlockerListResolver.swift:70-73,106-109） |

### 3-2. 解決順序
- 基本保護 `.blocker`: `ContentBlockerRequestHandler.beginRequest`（Extension/ContentBlockerRequestHandler.swift:15-28）→ `StateStore.read()`（App Group state.json）→ `BlockerListResolver.resolve(for:)` → **App Group `combined-<variant>`**（例外ありの時だけ存在）→ App Group `<variant>`（CDN DL済）→ bundle `<variant>` → bundle empty-rules.json（BlockerListResolver.swift:67-83,104-124）
- 2本目 `.popunderblocker`: `PopunderContentBlockerRequestHandler.beginRequest`（PopunderBlockerExtension/PopunderContentBlockerRequestHandler.swift:15-23）→ `PopunderRulesResolver.make()`＝`BlockerListResolver(filterFilename:"popunder-rules.json")`（Shared/PopunderRulesResolver.swift:10-12）→ `.resolve()`（トグル非依存）→ **App Group `combined-popunder-rules.json`**（常に存在＝reported/例外を必ず持つ）→ App Group直 `popunder-rules.json`（CDN DL済）→ bundle（BlockerListResolver.swift:23-38）

### 3-3. `App/CombinedRuleListCoordinator.regenerateIfNeeded()`（App/CombinedRuleListCoordinator.swift:32-96）が2本目に詰める中身
1. base = popunder-rules.json（L1+L2、resolveDirect・:46-48）
2. + `SelfReportedRulesStore.safeMergedReportedRules()`（self∪global報告）を `PopunderReportedFilter.excludingL2Allowed`でL2許可ドメインを除外（:50-53）
3. + `SiteExceptionRules.rules()`（サイト一時オフ、最後尾・:39-40,58）
4. `CombinedRuleListBuilder.rebuildIfNeeded(mayTruncate:false)`→ 変化時のみ `.popunderblocker` を reload（:54-66）

基本保護（同ファイル:68-96）は**例外ルールのみ**を combined に足す（reported は入らない＝ADR記載の「報告由来は基本保護へ」から**既に報告反映側へ再配置済み**。`docs/architecture/report-rule-reallocation-audit.md` のPhase1設計どおり実装されている）。例外なし・両OFFなら combined を消して bundle variant に戻す（:91-96）。

**★現状の欠落**: 2本目はトグル状態を一切見ない（`PopunderRulesResolver.make()` は state 引数を取らない）＝`a88-design-2026-09-27.md:43`で既知の未対応項目。

### 3-4. reload呼び出し箇所（`SFContentBlockerManager.reloadContentBlocker`）
`App/PopunderGlobalSync.swift:25` / `App/BackgroundTaskManager.swift:45` / `App/CombinedRuleListCoordinator.swift:63,87,93` / `App/ContentView.swift:120,157`

### 3-5. `scheduleRegenerate()` 呼び出し元
`App/AdblockKeshiApp.swift:148`（起動時migration）/ `App/PopunderGlobalSync.swift:22` / `App/BlockerControlView.swift:49`（トグル変更） / `App/SiteExceptionsListView.swift:57`（例外追加削除） / `App/ReportTab/ReportedGlobalSync.swift:17` / `App/ReportTab/ReportSentView.swift:99`

## 4. 検証

- CDN生成側: `convert.sh:72-75` が150,000超でビルド失敗。build_merged/build_security は `--limit` 引数で切るのみ（超過検知の失敗終了なし）
- 端末側: `Shared/RuleUpdater.swift` の `RuleUpdatePlanner.plans()`（:80-123）が **variantFilename・DL URL・baseline件数を4種類ハードコード**（merged-rules.json/ad-rules.json(=blockerList.json)/security-rules.json/empty-rules.json、baseline 130k/150k/30k/0）。`validateRuleCount`（:148-152）＝webKitLimit(150,000)超 or baseline比50%未満で拒否。`sha256Hex`比較（:141-144,316）。version.json/version-security.jsonのsha256フィールドと突合
- `Shared/ReportedRuleBudget.swift:12-16`＝`webKitLimit=150_000`, `totalCap=149_000`, `reportedReserve=2_000`, `standardFloor=147_000`（**基本保護のad-onlyのみtruncation対象**）

## 5. サイト単位一時オフ（ignore-previous-rules）

`Shared/SiteExceptionRules.swift:16-25` が `SiteExceptionsStore`（`site-exceptions.json`、上限200件）からドメイン→`ignore-previous-rules`ルールを生成。**両方の拡張の最後尾に追加**（`CombinedRuleListCoordinator.swift:39-40`基本保護分、`:58`2本目分）。基本保護は例外がある時だけcombinedを持つ（`Shared/SiteExceptionRules.swift:33-49`の`BasicExceptionRegenPlan`）。

## 6. 報告由来ルールの流れ

D1 `rule_candidates`(status=stable) → `reported-rules-build.ts` → `docs/cdn/rules-reported.json`（週次） → `FilterDownloader.reportedURL`でDL（`App/ReportTab/ReportedGlobalSync.swift:9-18`）→ AppGroup `rules-global.json` → `SelfReportedRulesStore.rebuildMerged()`（Shared/SelfReportedRulesStore.swift:61-67）→ AppGroup `rules-reported.json`（ローカル名衝突注意・CDN版とは別物）→ `safeMergedReportedRules()`（:74-84、documentブロック除外+dedup）→ 2本目のcombinedへ（3-3節）。**現状 rules-reported.json は0件**なので実配信はまだ無い。

## 7. 関連テスト

- Swift: `Tests/BlockerListResolverTests.swift` / `CombinedRuleListBuilderTests.swift` / `CombinedRuleListMergeTests.swift` / `CombinedRuleListCoordinatorThreadingTests.swift` / `ReportedRuleBudgetTests.swift` / `PopunderRuleCompileTests.swift` / `PopunderCombinedReallocationTests.swift` / `PopunderReportedFilterTests.swift` / `PopunderRulesResolverTests.swift` / `RuleUpdaterTests.swift` / `RuleUpdatePlannerTests.swift` / `SiteExceptionRulesTests.swift` / `SiteExceptionsStoreTests.swift` / `StateStoreTests.swift` / `AppliedRulesStoreTests.swift` / `SelfReportedRulesStoreTests.swift` / `ContentRuleListSnapshotTests.swift` / `ContentBlockerStateCheckerTests.swift` / `ExtensionDisplayNameTests.swift`
- Python: `scripts/tests/test_build_merged_rules.py` / `test_build_popunder_rules.py` / `test_build_security_rules.py`
- TS: `workers/tests/scripts/reported-rules-build.test.ts`（D1周りは他に `workers/tests/lib/aggregation-threshold.test.ts` 等だが報告関門の話で本件のルール分割とは別軸）

## 8. 変更が要るファイル（基本保護=セキュリティ+広告前半／2本目=広告後半+ポップアップ+報告）

| ファイル | 変更内容（1行） |
|---|---|
| `scripts/build_merged_rules.py` | ad→security の順で130kに切り詰める今のロジックを廃止。security全量を先に確保し、残り枠に ad の**前半**を入れる新ロジックに置換（後半は捨てずに別出力へ渡す必要あり） |
| `.github/workflows/build-security-rules.yml` | merged-rules生成ステップを上の新ロジック呼び出しに変更。**ad後半グループを新ファイル（例: `docs/cdn/popunder-ad-rules.json`）に出力する追加ステップが必要**（新規） |
| `scripts/build_popunder_rules.py` または新規スクリプト | 2本目のbase生成にL1+L2に加えて「広告後半グループ」を合流させる分岐を追加。**popunder-rules-update.ymlのtrigger（tasks/b-popunder-script/*）とad後半の更新頻度（週次security workflow）が不一致**＝どちらが2本目のbaseファイルを書くか設計要 |
| `.github/workflows/popunder-rules-update.yml` | 上のbase合流方式次第でtrigger paths・実行順序を見直し（ad後半ファイルの変更でも起動する必要が出る可能性） |
| `Shared/BlockerListResolver.swift:92-98` | `filename(for:)` の4分岐を「セキュリティ+広告前半」ベースの新ファイル名にマッピングし直す（新旧ファイル名の使い分けが要る、下記互換注意） |
| `Shared/PopunderRulesResolver.swift` | base ファイル名を「L1+L2+広告後半」の新ファイルに変更、または`CombinedRuleListCoordinator`側でbase読み込みを広告後半ファイルと結合する形に変更 |
| `App/CombinedRuleListCoordinator.swift:42-96` | 2本目の base 取得元を新ファイルに向ける。トグル状態（3-3節末尾の既知欠落）も同時に直すなら`popunderResolver`をtoggle-aware化 |
| `Shared/RuleUpdater.swift:80-123,186-190` | `RuleUpdatePlanner.plans()`のURL/baseline/variantFilenameを新ファイル名に追加・変更。`legacyFilenames`掃除リストの扱いも要確認 |
| `Shared/ReportedRuleBudget.swift` | 2本目の予算（今は`reportedReserve=2,000`のみ）に「広告後半」の枠を新設するか検討（現行は報告・例外専用） |
| `scripts/convert.sh` | 広告フル生成はそのまま維持しつつ、前半/後半の分割点をどこで決めるか（本スクリプト内 or 後続の別スクリプト）を確定 |
| `App/Resources/bundled-rules-info.json` + `Extension/Resources/*.json` + `PopunderBlockerExtension/Resources/*.json` | 新しい同梱ルールセットに差し替え、generated_atを更新（2章の手動同期忘れに注意） |
| Tests（`BlockerListResolverTests` / `CombinedRuleListBuilderTests` / `RuleUpdaterTests` / `RuleUpdatePlannerTests` / `PopunderRulesResolverTests` / `PopunderCombinedReallocationTests` 等） | 新ファイル名・新分割ロジックに合わせてfixture・期待値を更新 |
| `docs/architecture/report-driven-protection-suite.md` / `report-rule-reallocation-audit.md` | 責務表・現状記述を新構成に更新（ADRの追記） |

### 旧版（4.3.0以前・現行live）を壊さないために残すべきもの

現行live版は `MARKETING_VERSION=4.3.0`（project.yml:14）で、`RuleUpdatePlanner.plans()`にハードコードされた4URL・4sha・4baselineをそのまま信じてDLする。**以下は形式・内容とも変更禁止**（新ファイルは"追加"で対応する）:
- `docs/cdn/blockerList.json`・`docs/cdn/merged-rules.json`・`docs/cdn/security-rules.json`・`docs/cdn/empty-rules.json`（配列JSON、sha256は`version.json`/`version-security.json`と一致必須）
- `docs/cdn/version.json`（`blocker_list_sha256`・`generated_at`・`filters`・`reported`キー）と `docs/cdn/version-security.json`（`merged-rules_sha256`・`security-rules_sha256`・`empty-rules_sha256`・`generated_at`）のキー名・型
- `docs/cdn/popunder-rules.json`（旧版はここから直読み・sha検証なしのため中身が変わると旧版の2本目の中身も変わってしまう＝**広告後半を混ぜるなら旧版にも意図せず配信される**点に注意。旧版へ影響させたくなければ新ファイル名を使うこと）
- `docs/cdn/rules-reported.json`（旧版の`ReportedGlobalSync`が直読み）

新構成は上記と**別名の新ファイル**（例: `docs/cdn/basic-rules-v2.json`, `docs/cdn/popunder-ad-rules.json`）で配信し、4.4.0以降のアプリだけが新ファイル名を読むようにするのが安全。旧ファイル群は当面生成を止めない（stop する場合は旧版利用者ゼロを確認してから別途判断）。

## 未確認
- 4.4.0で旧CDNファイルの生成を止めてよい旧版利用率のしきい値（kureho判断事項）
- 広告ルールの「前半/後半」の分割点をどう決めるか（`tasks/a88-design-2026-09-27.md`の計測ツール`scripts/measure/`で別途決定予定・本調査では未実施）
