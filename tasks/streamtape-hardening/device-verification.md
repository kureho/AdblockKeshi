# 実機検証（Phase 8）— 自動化範囲と手動チェックリスト

接続実機: **KPhone = iPhone 17 Pro（iPhone18,1・現行 iOS）** を devicectl で検出。

## 自動化できること / できないこと（正直な区別）

| 項目 | 自動化 | 状態 |
|---|---|---|
| 開発ビルドの build / install / launch（実機） | devicectl + xcodebuild | 手順は下記。署名状況に依存 |
| Safari 拡張の有効化（設定→Safari→拡張） | ❌ 不可（OS 設定の物理操作） | kureho 手動 |
| 対象サイト権限の許可 | ❌ 不可 | kureho 手動 |
| streamtape での 3 cold load × 10 操作・popup 目視 | ❌ 不可（画面操作・目視） | kureho 手動 |
| registerContentScripts world:MAIN の実機実動作 | ❌ 自動目視不可（popup 診断で可視化済み） | kureho 手動 |
| **iOS 17 実機での world:MAIN** | ❌ この端末は現行 iOS（iOS 17 端末が別途必要） | 未確認 |

→ **挙動の実機 E2E は kureho の手動確認が必須**。本タスクの規定により、これが未完のため **本 PR はマージ不可**。

## 自走できる部分（開発ビルドの build/install/launch）

```bash
# 1) デバイス確認
xcrun devicectl list devices

# 2) 開発ビルド（自動署名・Team L455WPL8QZ）
xcodegen generate
xcodebuild build -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS,name=KPhone' -derivedDataPath build/DeviceBuild \
  -allowProvisioningUpdates

# 3) install / launch（.app パスは build 出力から）
APP=$(find build/DeviceBuild -name 'AdblockKeshi.app' -path '*Debug-iphoneos*' | head -1)
xcrun devicectl device install app --device KPhone "$APP"
xcrun devicectl device process launch --device KPhone com.kureho.adblockkeshi
```

> ⚠️ 新規 bundle id `com.kureho.adblockkeshi.popupshield` は Developer Portal 未登録のため、
> 自動署名でプロファイル生成が必要（`-allowProvisioningUpdates`）。失敗する場合は Xcode で一度
> 対象を開いて Automatic signing を確定させる（提出前作業）。本 build/install の成否は本ファイル末尾に追記する。

## kureho 手動チェックリスト（実機・最小）

成人向け映像の視聴・録画・スクショは不要。記録するのは下表の項目のみ。

1. アプリをインストール（上記 or Xcode）
2. iOS 設定 → Safari → 機能拡張 →「強力ポップアップ対策」を ON
3. streamtape.com へのアクセス権限を「許可」
4. 強力モード OFF（拡張 popup のトグル）で streamtape の動画ページを開く（baseline 体感）
5. 強力モード ON
6. 拡張 popup が **registered（有効・動作確認待ち）** になる
7. 対象ページを再読み込み → 拡張 popup が **active（動作確認済み）** になる（= world:MAIN 実動作の証跡）
8. 3 回コールドロード
9. 各ロードでプレーヤー領域を 10 回タップ
10. 意図しない新規タブ **0**
11. current-tab 広告リダイレクト **0**
12. プレーヤー初期化 **3/3**
13. media 再生（読み込み）**3/3**
14. 正規リンク（サイトメニュー等）が使える
15. 強力モード OFF → 介入しない（baseline に戻る）
16. サイト一時停止 → 介入しない
17. 再 ON → 復帰（active）
18. Safari 再起動後も状態復元（拡張 popup の状態確認）
19. iPhone 再起動後も復元
20. Private Browsing での挙動を記録（拡張が動くか・popup 状態）

### MAIN world が実機で非対応だった場合（静かに劣化させない）

popup が `unsupported` を表示する。その場合は推測で進めず、次の順で実機検証:
1. `scripting.executeScript` の MAIN world
2. manifest 宣言型 content script の MAIN world
3. ISOLATED bridge からのページ script 注入（CSP 環境で実動作確認）
いずれも動かなければ: 強力モードを「この端末では利用できません」表示・ON 不可・静的 L2 のみ提供。
App Store 説明で強力モード対応を断定しない。

## 記録テンプレ（手動確認後に追記）

```
- OS バージョン:
- アプリ build:
- extension version: 3.4.0
- registration 状態（popup 表示）:
- popup 件数（3 ロード合計）:
- redirect 件数:
- player 生存（n/3）:
- media 生存（n/3）:
- エラー分類（あれば）:
```

## build/install/launch 実行結果（自走分）— 2026-06-23

- 端末: KPhone = iPhone 17 Pro（iPhone18,1・現行 iOS）
- **device build: BUILD SUCCEEDED**（`-allowProvisioningUpdates`・自動署名）。
  新規 bundle id `com.kureho.adblockkeshi.popupshield` の provisioning profile も自動生成され、
  app + 全 4 拡張（標準/自己学習/ポップアップ/**強力ポップアップ**）が署名された。
- **install: 成功**（`xcrun devicectl device install app`・bundleID com.kureho.adblockkeshi）。
- **launch: 成功**（`xcrun devicectl device process launch`・「Launched application」確認）。

→ 実機での build / install / launch は自走で確認済み。**ただし挙動の E2E（拡張有効化・権限付与・
streamtape での 3 cold load × 10 操作・popup 0・プレーヤー生存・active 表示）は画面操作と目視が必要で
自動化できないため kureho 手動待ち。よって「実機挙動 未確認」＝本 PR はマージ不可。**
