# review/results/ — 週1回の人手判定結果

A-88 §2「報告の週1回判定」で、Claude が判定した結果をここに置く。
`review/results/**` への push で `.github/workflows/apply-review-results.yml` が動き、
`scripts/review/apply-review-results.ts` が内容を D1 の `reports.review_outcome` /
`reports.reviewed_at` に書き込む。

## ファイル形式

1 ファイル = 1 回の判定。ファイル名は自由（例: `2026-09-27.json`）。

```json
{
  "reviewed_at": "2026-09-27",
  "results": [
    { "report_id": "<reports.id の UUID>", "outcome": "applied", "note": "任意のメモ" },
    { "report_id": "<reports.id の UUID>", "outcome": "not_reproduced" }
  ]
}
```

- `reviewed_at`: `YYYY-MM-DD`。その日の 00:00 UTC を Unix 秒に変換して保存する
- `results[].report_id`: 判定対象の `reports.id`（UUID）。UUID 形式でない値が1件でもあると
  **ファイル全体が失敗する**（そのファイルからは1件も D1 に書き込まれない）
- `results[].outcome`: 次の 5 値のいずれか。未知の値が1件でもあると同様にファイル全体が失敗する
  - `applied` — 反映した（そのサイト限定の if-domain ルールを次の週次配信に載せた）
  - `in_app_ad` — アプリ内広告で Safari のフィルタでは消せない
  - `site_own_ad` — サイト自身が出している広告で消せない
  - `not_reproduced` — 再現しない
  - `invalid` — 無効な報告
- `results[].note`: 任意。人間向けのメモで、D1 には書き込まれない（読むのは判定した本人だけ）

`POST /v1/reports/status` はこの `outcome` をさらに丸めて報告者へ返す
（`not_reproduced` と `invalid` はどちらも `declined` になる。丸め方は
`workers/src/lib/review-outcome.ts` の `resolveReviewOutcome` を参照）。

## 冪等性

同じファイルを2回流しても結果は変わらない（`UPDATE ... SET review_outcome=?, reviewed_at=? WHERE id=?`
は同じ値を書き直すだけ）。判定をやり直したいときは同じ `report_id` を含む新しいファイルを追加すればよい
（後から流したファイルの値で上書きされる）。

## 実データについて

このディレクトリに実データのファイルを置くのは判定を行う本人のみ。このコミットの時点では
サンプル・実データのどちらも置いていない（README のみ）。
