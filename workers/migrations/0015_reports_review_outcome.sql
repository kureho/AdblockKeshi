-- A-88 §2/§3: 週1回の人手判定の結果を保持する列。
-- 設計: tasks/a88-design-2026-09-27.md §2「判定の結果はリポジトリのファイルに書く」
--        →「報告ごとの結果は GitHub Actions が D1 に書き込む」、§3「報告者に結果を返す」。
--
-- review_outcome: NULL = 未判定（既存行は全て NULL のまま）。
--   値は 5 種（scripts/review/apply-review-results.ts が書き込む raw 値と一致）:
--   applied / in_app_ad / site_own_ad / not_reproduced / invalid
--   API 側（workers/src/lib/review-outcome.ts）が not_reproduced・invalid を declined に丸めて返す。
-- reviewed_at: 判定ファイルの reviewed_at（YYYY-MM-DD）を Unix 秒に変換した値。NULL = 未判定。
--
-- 既存行への影響なし（ALTER TABLE ADD COLUMN は新列を NULL で追加するのみ）。
ALTER TABLE reports ADD COLUMN review_outcome TEXT;
ALTER TABLE reports ADD COLUMN reviewed_at INTEGER;
