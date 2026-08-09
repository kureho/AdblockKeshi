# 次回提出に載せるもの（正典・2026-08-10 作成）

次に AdblockKeshi を提出するセッションは、`submitting-ios-build` skill と合わせて本ファイルを反映すること。反映したら本ファイルを削除する。

## 同梱済みの変更（main に commit 済み・f6828a7）

- **保護ドメイン報告の送信前ガード**: `CriticalDomainGuard` で入力時に弾き、URL 欄下に日本語で理由表示 + 送信ボタン無効化。サーバ 400 フォールバック文言も日本語化（`APIError.criticalDomainProtected`）
- 背景: 2026-08-09 問い合わせ（apps.apple.com 報告 9 回失敗 → 自動 ban）。サーバ側の ban 集計除外は反映済み・アプリ側の案内だけが次回版待ち

## whatsNew（確定・kureho 依頼 2026-08-10「もうやっておきたい」）

`fastlane/metadata/ja/release_notes.txt` に投入済み（v4.0.0 時代の古い文面から差し替え済み）:

> ・報告機能の案内を改善しました。保護対象サイト（大手サービスなど）のURLは報告の対象外のため、入力時に画面で理由が分かるようになりました。

- NG 語チェック済み: 価格表記（¥/円/無料/買い切り）なし・Apple 商標（Safari/iPhone/iOS 等）なし
- 提出方式が stage script（ASC API 直 PATCH）の場合も、WHATS_NEW 定数にこの文面を使うこと
- 次回版に他の変更も入る場合は行を追加してよい（この行は必ず残す）

## 注意

- name/subtitle/keywords/description は変更しない（ASO 効果測定保護・8月中旬〜9月の rank_check 観測中）
- 提出前に 4 点監査・提出後に auditing-apple-submission（通常フロー）
