> **🔖 このコメントが最新状態です（2026-06-23・HEAD `7912257`）。** 過去のコメントより本コメントを優先してください。

## 追加修正: 自己学習フィルタによる top-level document 誤ブロックの根治

### 発見の経緯
強力モード（PopupShield）の実機検証中に、**Safari の機能拡張4本すべてを ON にすると Streamtape 等のサイト自体が表示できなくなる**事象を発見。自己学習フィルタを OFF にすると表示できることから、原因を自己学習フィルタに切り分けた。

### 根本原因
クライアント側の自己報告ファストレーン `ReportedRuleBuilder.blockRule(forURL:)` が、報告された URL の host を **`resource-type` / `load-type` 無制限の `block` ルール**にしていた。これが top-level document を遮断し、端末 `rules-self.json` に永続していた。サーバ / CDN / bundle は無実（サーバは `css-display-none` cosmetic のみ）。

### 多層修正
1. 生成ルールに `load-type:["third-party"]` + document 除外の `resource-type` を付与（訪問中サイトを first-party で絶対に遮断しない）
2. 判定述語 `ReportedRuleSafety.isDocumentBlockingRisk`
3. **起動時 migration で既存被害端末を治癒**（旧危険ルールを purge・変化時のみ reload・ネットワーク非依存）
4. merged 生成経路でも document-block を strip + structural dedup
5. サーバ不変条件（`decideL6` は `block` を出さない）をテストでロック

### 実機結果（kureho 目視）
- **4拡張すべて ON でも Streamtape 表示可能**になった
- 自己学習フィルタ ON でも top-level document 非遮断
- 強力ポップアップ対策 有効時も表示・操作・広告抑止とも良好
- 実機 E2E ゲートは kureho が PASS 判断
- ⚠️ iOS 17 実機の `world:MAIN` は未確認（残存リスク）

### 最新テスト件数（HEAD `7912257`）
Swift 135 pass / 1 skip / 0 fail ・ workers vitest 195 ・ Node 54 ・ Python 14 ・ deterministic fixture 14 checks ・ WebKit compile green ・ Release build green。
CI run: https://github.com/kureho/AdblockKeshi/actions/runs/28012181641

### ステータス
- 最新 HEAD: `7912257f3a78fd23f227b4d413d938ffaaedc804`
- **main 未変更**（origin/main は `65063b0` のまま）
- **App Store upload / 提出なし**
- マージはまだ行わない（merge-ready 判定のみ）
