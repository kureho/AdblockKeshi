-- spec rev4 §3 D1 schema: bans (4 段階自動 ban)
CREATE TABLE bans (
  identifier_hash TEXT PRIMARY KEY,
  identifier_type TEXT NOT NULL,                -- 'uuid' or 'ip'
  reason TEXT NOT NULL,
  abuse_count INTEGER NOT NULL DEFAULT 0,
  ban_level INTEGER NOT NULL DEFAULT 1,         -- 1=24h/2=7d/3=30d/4=permanent
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  notes TEXT                                    -- 自動判定根拠
);
CREATE INDEX idx_bans_expires ON bans(expires_at);
