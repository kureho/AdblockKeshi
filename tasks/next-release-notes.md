# 次回提出（D-lite）で反映するリリース文言（正典）

対象: D-lite 版（報告機能の再設計）。**反映してファイルを消すまでが1セット。**

前提: ASO 凍結中のため **name / subtitle / keywords / description / screenshots は変更しない**。
変更するのは version ごとの whatsNew と reviewNotes だけ。

---

## whatsNew（`fastlane/metadata/ja/release_notes.txt`）

```
・広告を報告するときに、Safari で見たのか、ほかのアプリの中で見たのかを選べるようにしました。
・入力する URL は「広告が消えなかったページ」でよいことが分かるようにしました。
・これまで報告できなかった大手サイトのページも、報告できるようになりました。
・いただいた報告は、広告フィルタの改善に活用します。
```

チェック（`feedback_pricing_metadata_strict`）: 価格表記なし（¥ / 無料 / Free / 割引 いずれも不使用）。
「報告で育つ」の訴求は App Store 側で維持（今回変更しない）。

3 行目は 2026-08-09 の問い合わせ（保護ドメインを報告して毎回失敗していた利用者・メール未入力で返信不可）が
更新時に気づける導線。4.0.3 の whatsNew では「案内を分かりやすくした」までだったが、D-lite で実際に送れるようになる。

---

## reviewNotes（`patch_review_notes.py` で投入）

提出 version の実態を反映すること（`feedback_review_notes_must_match_version`）。骨子:

- 本アプリは Safari 用コンテンツブロッカー。追加の「アプリ内広告ブロック」は買い切りの App 内課金で、
  端末内で完結する DNS フィルタリング（NEPacketTunnelProvider）として動作する。外部サーバーへは送らない。
- 本バージョンの変更は**広告報告フォームの再設計**。利用者が「広告が消えなかったページ」の URL と、
  どこで見たか（Safari / それ以外のアプリ）を送る。送信内容は改善用の統計データとしてのみ利用し、
  報告した端末のブロック挙動を即座に変えることはしない。
- 収集する情報に個人を特定するものは含まない（URL・任意メモ・端末の設定状態のみ。メモは PII を除去して保存）。
- App 内課金の確認手順は前バージョンから変更なし。

---

## 反映手順

1. `fastlane/metadata/ja/release_notes.txt` を上の内容へ更新
2. ASC で新 version 作成 → build 添付
3. `patch_review_notes.py` で reviewNotes 投入
4. **このバージョンにだけ概要評価リセットを設定**（ASC Web UI のみ・4.0.3 では設定していない）
5. 反映が終わったら本ファイルを削除
