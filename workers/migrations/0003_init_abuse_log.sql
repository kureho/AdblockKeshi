-- spec rev4 §3 D1 schema: abuse_log (不正報告記録)
CREATE TABLE abuse_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  identifier_hash TEXT NOT NULL,                -- uuid_hash or ip_hash
  identifier_type TEXT NOT NULL,                -- 'uuid' or 'ip'
  reason TEXT NOT NULL,                         -- 'rate_limit'/'invalid_url'/'spam_memo'/'pii_redacted'/'critical_domain'
  url TEXT,                                     -- 該当 URL (検証用)
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_abuse_identifier ON abuse_log(identifier_hash, created_at);
