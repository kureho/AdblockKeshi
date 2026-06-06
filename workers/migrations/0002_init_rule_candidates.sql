-- spec rev4 §3 D1 schema: rule_candidates (集計済みルール候補)
CREATE TABLE rule_candidates (
  id TEXT PRIMARY KEY,
  domain TEXT NOT NULL,
  selector TEXT,                                -- CSS selector or NULL
  rule_text TEXT NOT NULL,                      -- Content Blocker JSON 形式
  unique_uuid_count INTEGER NOT NULL,
  unique_ip_count INTEGER NOT NULL,
  first_reported_at INTEGER NOT NULL,
  last_reported_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'aggregating',   -- aggregating/validating/beta/stable/rejected/rejected_rollback
  beta_started_at INTEGER,
  stable_started_at INTEGER,
  complaint_count INTEGER NOT NULL DEFAULT 0,
  cooldown_until INTEGER,                       -- rollback 後 30 日
  validation_score REAL,                        -- L6 Playwright スコア (0-1)
  l3_check TEXT,                                -- pass/fail (Tranco)
  l4_check TEXT,                                -- pass/fail (selector scope)
  l5_check TEXT                                 -- pass/fail (CDN protection)
);
CREATE INDEX idx_rc_status ON rule_candidates(status);
CREATE INDEX idx_rc_cooldown ON rule_candidates(cooldown_until);
