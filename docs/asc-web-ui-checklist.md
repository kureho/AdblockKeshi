# kureho が ASC Web UI でやる残作業（5項目・合計 5-10分）

URL: https://appstoreconnect.apple.com/apps/6774906945

## 1. App Review Information (App 情報 → App Review Information)

StillCam 4K で使ってる値を**そのまま入力**:
- First Name: Kureho
- Last Name: Support
- Email: info@kureho.app
- Phone: (StillCam 4K と同じ番号)
- Demo Account Required: OFF
- Notes:
  ```
  本アプリは Safari Content Blocker です。
  Safari 設定 > 機能拡張 > 「広告消し」を ON にして
  https://adblock-tester.com を開くと広告ブロック動作が確認できます。
  アプリ内画面は最小構成で、設定項目はありません。
  ```

## 2. Primary Category

App 情報 → 一般情報 → カテゴリ
- **プライマリカテゴリ: ユーティリティ**
- セカンダリカテゴリ: なし（または 仕事効率化）

## 3. Price (価格と配信状況)

価格と配信状況 → 価格
- **¥400 (Tier 4)** を選択
- 配信開始日: 即時
- 配信地域: すべて (全世界)

## 4. App Privacy (App プライバシー)

App プライバシー → 「データを収集しない」を選択 → 確定
- 我々のアプリ:
  - データ収集: なし
  - サードパーティ SDK: なし
  - トラッキング: なし
- 「データの収集には該当しません」で確定

## 5. Age Rating (年齢制限)

App 情報 → 年齢制限 → 編集
- すべて「なし」を選択
- 推定年齢: 4+
- 「制限あり Web コンテンツ」: いいえ（広告ブロックは年齢制限要素にならない）

## 6. スクリーンショット (5枚)

別ファイル `docs/app-store-screenshots-prompt.md` の手順で
ChatGPT で 5 枚生成 → `fastlane/screenshots/ja/` に配置 → 私が `fastlane submit_screenshots` で送信

---

## 上記5項目完了後、kureho が最後にやること

1. ASC Web UI で「Submit for Review」(提出ボタン)
2. 「輸出コンプライアンス」「IDFA 利用」等の最終質問に答える
3. 提出完了 → Apple 審査開始 (24-48h)

---

## なぜ私 (Claude) が自動化できなかったか

- Apple ASC API は AppStoreReviewDetail / Category / Privacy の POST/PATCH 対応が不完全
- fastlane Spaceship gem も対応してない
- ASC Web UI で 5分やる方が、API 探索に 30分使うより早い
- (Review Info の値だけは私が StillCam から既に取得済: phone +81***40, email info@kureho.app)
