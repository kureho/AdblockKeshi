# 広告消し 4.4.1（build 10402）提出前の照合表（2026-10-03）

対応言語は ja のみ（ASC の localization も appInfo も ja だけ・API で確認）。この版で利用者の目に入る物が変わるのは「キーワード」「更新内容」の 2 つだけ（アプリ内の文言・画面・権限・課金は無変更）。

| 対象 | ストア側（ASC 実データ） | アプリ実物 / 手元 | 結果 |
|---|---|---|---|
| ストア名 ⇔ ホーム画面の名前 | 学習する広告消し - 消えない広告もブロック（22 字） | `CFBundleDisplayName` = 広告消し（project.yml:35） | ✅ ホーム名がストア名に含まれる |
| サブタイトル | 他で消えない広告も、報告で進化 | 無変更 | ✅ |
| 説明文・プロモーション・URL | 配信中 4.4.0 の値 | `fastlane/metadata/ja/*.txt` | ✅ 4 項目とも一致（deliver・stage で古い値に戻らない） |
| キーワード | 4.4.0 の値（A-81 前） | keywords.txt（88 字・価格語なし） | ⏳ 4.4.1 で差し替え（A-81）→ 版の作成後に GET で照合 |
| 更新内容 | （新規） | release_notes.txt：トグルを戻した直後に閉じた件の修正＋購入画面からのリンク遷移の修正（53bce7a） | ✅ 2 点ともこの build に入っている（単体テスト・再現テストで確認） |
| 審査メモの手順 | `tasks/review-notes-4.4.1.txt` | 「広告ブロック」トグル（BlockerControlView.swift:82）・「広告ブロック中」表示（ContentView.swift:229）・設定 > アプリ > Safari > 機能拡張 | ✅ 実コードどおり |
| 掲載スクショ | 配信中 4.4.0：APP_IPHONE_67 × 5 枚 | `tasks/screenshot-drafts-v440/final/` の 5 枚 | ✅ md5 ⇔ sourceFileChecksum が 5 枚とも一致（新しい版は引き継ぐ→作成後に再照合） |
| 価格語（名前・サブタイトル・キーワード・更新内容） | — | ¥ / 円 / 無料 / Free / 割引 / セール なし | ✅ |
| 権限ダイアログ・エラー文 | — | 無変更 | ✅ N/A |

## 積み残し（`tasks/todo.md` の「次版で必ず反映」）
- 53bce7a（リンク到着で購入画面を閉じる）→ 載せた（4.4.1）
- A-81 キーワード差し替え → 載せる（版の作成後に GET で照合してから「載せた」を付ける）

## 監査（読み取りのみ・2026-10-03 実行）
audit_pending_iap_names / audit_description_prices / audit_store_privacy_claims / audit_review_notes_version / hitarea_sweep / paywall_reach_sweep：すべて exit 0
