-- v4.2.0: 報告種別（ad_not_blocked / site_broken）。
-- NULL = 旧クライアント（report_kind を送らない）= 広告報告の意味。
-- site_broken は保存時に status='broken_site' へ隔離され、広告集約（status='pending' のみ消費）には
-- 構造的に混入しない。既存行は全て広告報告なので NULL のままでよい。
ALTER TABLE reports ADD COLUMN report_kind TEXT;
