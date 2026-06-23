# 実機ビルド記録（KPhone）— streamtape 誤ブロック修正

## トレーサビリティ
- **コミット SHA**: `e3d625bd26216535457e27d75b0e1ddbc70adfd6`（short `e3d625b`）
- branch: `fix/streamtape-adblock-hardening`（main 未変更・push 未実施）
- ビルド構成: Debug / 実機（iphoneos）/ Automatic signing / Team `L455WPL8QZ`
- derivedData: `/tmp/adblock-device-build`

## インストール先
- デバイス: **KPhone**（iPhone 17 Pro / iPhone18,1）
  - devicectl id: `1A69FD3E-8284-5AD0-B181-B6BD8CCF8E5B`
  - hardware UDID: `00008150-001470823A23401C`
- bundleId: `com.kureho.adblockkeshi`
- **version 3.4.0 / build 24**（このブランチの開発版。配信中の v3.2.0/v3.3.0 とは別系列）
- 同梱拡張4本: ContentBlockerExtension / ReportedRulesExtension / PopunderBlockerExtension / PopupShieldExtension
- installationURL: `file:///private/var/containers/Bundle/Application/8451F991-8ECD-4195-A479-AD0067F1B952/AdblockKeshi.app/`

## 結果
- build: **SUCCEEDED**（exit 0）
- install: **成功**（App installed）
- launch: **成功**（2026-06-23・KPhone アンロック後・`xcrun devicectl device process launch` で「Launched application」）。
  起動時に既存端末治癒 migration（`migrateReportedRulesIfNeeded`）が発火する build を起動。
- 実機 E2E: **kureho 目視で PASS**（詳細は `device-verification.md` の「実機 E2E 検証結果（kureho 目視）」）。

## 制約遵守
push 未実施 / PR #29 未更新 / main 未変更 / App Store upload・提出なし。
