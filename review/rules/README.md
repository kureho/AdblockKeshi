# review/rules/ — 週1回の判定で書く「そのサイト限定」のルール

A-88 §2「報告の週1回判定」で、報告されたページに残っている広告を止めるルールをここに置く。
`review/rules/*.json` への push（と毎週火曜の定期実行）で `.github/workflows/weekly-cdn-sync.yml` が動き、
`scripts/sync/reported-rules-build.ts` が D1 の自動反映分（`rule_candidates.status='stable'`）の後ろに
ここのルールを足して `docs/cdn/rules-reported.json` を作り直す。アプリは 2 本目のブロッカー
（報告反映）でこのファイルを読む。旧版（4.3.0 以前）も同じファイルを直接読むので、アプリの更新なしで届く。

## ファイル形式

1 ファイル = 1 サイト（か 1 回の判定）。ファイル名は自由（例: `2026-09-28-thedigestweb.json`）。

```json
{
  "added_at": "2026-09-28",
  "rules": [
    {
      "trigger": { "url-filter": "^https?://([^/]+\\.)?html-load\\.com[/:]", "if-domain": ["*thedigestweb.com"] },
      "action": { "type": "block" }
    }
  ]
}
```

- `added_at`: `YYYY-MM-DD`。アプリの「直近 30 日に追加したルール数」の数え方に使う
- `rules`: Safari コンテンツブロッカーの規則。**1 本でも次の条件を外れると、配信ファイルの作り直しごと失敗する**
  （壊れたルールを全利用者に配らないため）
  - `trigger.if-domain` が必須（1〜20 件・小文字のドメイン・先頭 `*` でサブドメインも含む）＝報告されたサイトでだけ効く
  - `trigger` に使えるのは `url-filter` / `url-filter-is-case-sensitive` / `if-domain` / `resource-type` / `load-type` だけ
  - `action.type` は `block` か `css-display-none`（`selector` 必須）だけ。`ignore-previous-rules` は使えない
    （ほかの防御を外せてしまう）
  - `block` で `resource-type` に `document` を入れない・`url-filter` を `.*` 等の「何でも」にしない
    （サイトそのものが開けなくなる）

★**このリポジトリは公開**。書いてよいのは**サイトのドメイン**と**広告の通信先・広告の要素**だけ。
報告された URL のパス・クエリ・メモの内容は書かない（利用者の入力には個人情報が混ざりうる）。

## 入れる前の確認

判定用の束（`scripts/review/build_review_packet.py` が作る `.review-packets/`）で漏れを見つけたら、
計測ツールでルールありとなしの画面を並べて、広告が消えてページが壊れないことを見てから入れる:

```bash
swiftc -O scripts/measure/measure.swift -o /tmp/measure -framework WebKit -framework AppKit
R=.review-packets/.rules
/tmp/measure shoot --site "<報告されたページ>" --rules $R/merged-rules.json,$R/popunder-rules.json \
  --out /tmp/before.png --wait 8
/tmp/measure shoot --site "<報告されたページ>" --rules $R/merged-rules.json,$R/popunder-rules.json,review/rules/<新しいファイル>.rules.json \
  --out /tmp/after.png --wait 8
```

（計測ツールは規則の配列 JSON を読むので、試すときは `rules` の中身だけを別ファイルに書き出して渡す）

判定の手順全体は `tasks/a88-review-runbook.md`。
