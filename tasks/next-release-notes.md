# 次回提出に載せるもの（正典・2026-08-11 更新 = v4.0.3 hotfix 向け）

次に AdblockKeshi を提出するセッションは、`submitting-ios-build` skill と合わせて本ファイルを反映すること。反映したら本ファイルを削除する。

詳細設計は `tasks/dns-hotfix-4.0.3-design.md`（**公開 repo には含めないローカル文書**）。

## 提出対象 = v4.0.3 / build 10003（DNS 実害バグの hotfix）

### 同梱される変更（2件）

**1. DNS 自己報告ファストレーンの廃止 + 残骸削除（本題）**

報告 URL のホスト名が DNS ブロックリストに追記され、DNS には first-party / third-party の区別が無いため、**報告したサイト自体が名前解決できなくなっていた**（v4.0.2 まで実在。Pro + DNS トグル ON が条件）。

- 書き込み停止（`DNSSelfReportApplier` 型ごと削除）
- tunnel が `dns-self.json` を読まない（`PacketTunnelProvider.reloadEngine`）
- 起動時に `dns-self.json` を削除（`DNSSelfReportStore.purge()`・idempotent）
- 稼働中 tunnel へ即時 reload 要求（`TunnelManager.requestReloadIfRunning()`）

**2. 保護ドメイン報告の送信前ガード（f6828a7）**

`CriticalDomainGuard` で入力時に弾き、URL 欄下に日本語で理由表示 + 送信ボタン無効化。サーバ 400 フォールバック文言も日本語化（`APIError.criticalDomainProtected`）。

> 報告機能は後続バージョンで再設計予定のため、この案内は過渡的な仕様。現行 live（英語の技術文言 + 再試行を誘発する表示）よりは改善のため、hotfix ではそのまま出荷する。

## whatsNew（`fastlane/metadata/ja/release_notes.txt` に投入済み）

> ・一部のサイトが表示されなくなることがある不具合を修正しました。
> ・報告を送れなかったときの案内を分かりやすくしました。

- NG 語チェック済み: 価格表記（¥/円/無料/買い切り）なし・Apple 商標（Safari/iPhone/iOS 等）なし
- 「報告したサイトが」とは書かない（ユーザーから見える症状だけを書く）
- 提出方式が stage script（ASC API 直 PATCH）の場合も、WHATS_NEW 定数にこの文面を使うこと

## 注意

- name/subtitle/keywords/description は変更しない（ASO 効果測定保護・8月中旬〜9月の rank_check 観測中）
- **★概要評価のリセットは、この版では設定しない**（設定する版はローカル設計文書を参照）
- 提出前に 4 点監査・提出後に auditing-apple-submission（通常フロー）
- review contact phone の法人化 PATCH を build attach 後 / submit 前に実行
