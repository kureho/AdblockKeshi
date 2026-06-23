# Phase B 実機ビルド記録（KPhone）— 4→3 統合

## トレーサビリティ
- コミット: `089258ffa0d7eda05feb1460bc3a0d5228a35151`（branch `feat/consolidate-reported-content-blocker`）
- PR: #30（base main・未マージ）
- ビルド: Debug / 実機 / Automatic signing / Team `L455WPL8QZ` / derivedData `/tmp/adblock-phaseb-device`

## インストール先 / 結果
- デバイス: KPhone（iPhone 17 Pro・iPhone18,1）／ bundleId `com.kureho.adblockkeshi`／ version 3.4.0 build 24
- 同梱拡張: **3本**（ContentBlockerExtension / PopunderBlockerExtension / PopupShieldExtension。ReportedRulesExtension **無し**）
- device build: **SUCCEEDED**
- **update install**（既存4拡張版へ削除せず上書き）: **成功**（installationURL 更新）
- launch: **成功**（「Launched application」）。起動時 migration（`migrateReportedRulesIfNeeded` → sanitize purge + combined 再生成 + 標準 ContentBlocker reload）が発火する build を起動。

## 実機 E2E 検証結果（kureho 目視）— 2026-06-23 PASS

> kureho による実機目視確認。未計測の件数（popup 数等）は推測しない。

| 項目 | 結果（kureho 目視） |
|---|---|
| Safari 設定の拡張数 | **4拡張 → 3拡張に減少** |
| 独立「自己学習フィルタ」 | **非表示（消えた）** |
| 標準フィルタ ON 状態 | **維持** |
| 3拡張 ON で Streamtape | **表示可能** |
| player / media | 問題なし |
| 一般サイト表示 | 問題なし |
| Safari 再起動後 | 問題なし |
| 広告報告機能 | 継続（サーバ報告経路 + 自己報告ファストレーン） |
| 新規報告 → 自己報告ルールが標準フィルタの combined へ反映 | **確認** |
| 報告元の top-level ページ | 遮断されない（壊さない） |

→ **実機 E2E ゲートを kureho が PASS 判断**。combined への自己学習統合が標準 ContentBlocker 経由で実機動作することを確認。

## 制約
push（feature branch のみ）/ PR #30 未マージ / App Store upload・TestFlight・審査提出なし。
