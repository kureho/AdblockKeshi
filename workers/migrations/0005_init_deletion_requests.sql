-- spec rev4 §3 D1 schema: deletion_requests (1h SLA で自動削除処理)
CREATE TABLE deletion_requests (
  id TEXT PRIMARY KEY,
  uuid_hash TEXT NOT NULL,
  url_path_hash TEXT,                           -- 特定 URL の削除指定 (任意、NULL なら全削除)
  requested_at INTEGER NOT NULL,
  processed_at INTEGER,
  status TEXT NOT NULL DEFAULT 'pending'        -- pending/completed
);
