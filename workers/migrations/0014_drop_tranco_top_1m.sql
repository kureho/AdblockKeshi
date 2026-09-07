-- 2026-09-07: tranco_top_1m を廃止する。
-- 週次の全入れ替え（DELETE 10万行 + INSERT 10万行、暗黙 PK インデックス + idx_tranco_synced_at
-- 込みで 40万 rows_written）が D1 無料枠（10万 rows_written/日）の 4 倍を毎週日曜に焼いていた。
-- 2026-09-06 に Tranco リストを D1 から外し、唯一の読み手だった daily-validation.yml が
-- CSV を直接メモリに載せる方式へ移行済み（commit ef83865）。
-- 読み手が居なくなったテーブル本体（10万行・約5MB）をここで削除する。
DROP TABLE IF EXISTS tranco_top_1m;
