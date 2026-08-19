-- D-lite: 報告を「ブロック対象の指定」ではなく「改善用データ」として扱うための診断列。
-- 設計: tasks/dlite-design-2026-08-11.md §5
--
-- seen_in の有無が新旧クライアントの境界になる（旧クライアントは送ってこないので NULL）。
-- 日時で切らないのは、D-lite 公開後も旧アプリから報告が届き続けるため。
ALTER TABLE reports ADD COLUMN seen_in TEXT;            -- 'safari' | 'other_app' | NULL(旧クライアント)
ALTER TABLE reports ADD COLUMN blocker_enabled INTEGER; -- 1/0/NULL（Content Blocker が有効だったか）
ALTER TABLE reports ADD COLUMN dns_enabled INTEGER;     -- 1/0/NULL（DNS ブロックが実際に動いていたか）
ALTER TABLE reports ADD COLUMN app_version TEXT;
ALTER TABLE reports ADD COLUMN app_build TEXT;
ALTER TABLE reports ADD COLUMN filter_version TEXT;

-- index は追加しない: 集計は `status='pending' ... ORDER BY created_at ASC LIMIT 10000` で走り、
-- 既存の idx_reports_status_created(status, created_at) が効く。seen_in は 3 値でカーディナリティが
-- 低く、単独 index の効果が薄い。
--
-- ★これが成り立つ前提は「pending に集約対象の報告しか入らない」こと。
--   submit 側で対象外（other_app / blocker 無効・不明）は observation_out_of_scope に振り分ける
--   （`workers/src/handlers/submit.ts` の reportStatus）。対象外を pending に入れると
--   どのランでも消費されず滞留し、古い順 LIMIT の枠を埋めて新しい報告を押し出す。

-- 既存の pending は旧仕様（URL の意味が曖昧・診断情報なし）の報告なので、
-- D-lite の 3ユーザー/14日判定の母集団に混ぜない。削除はせず参考データとして残す。
--
-- ★`seen_in IS NULL` の条件は必須。新規報告も pending で入るため、この条件が無いと
--   再実行時に D-lite の新規報告まで巻き込む。条件があればいつ流しても安全。
UPDATE reports SET status = 'observation_legacy'
WHERE status = 'pending' AND seen_in IS NULL;
