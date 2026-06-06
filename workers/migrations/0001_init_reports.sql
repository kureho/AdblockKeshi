-- spec rev4 §3 D1 schema: reports (個別報告)
CREATE TABLE reports (
  id TEXT PRIMARY KEY,                          -- UUID v4
  uuid_hash TEXT NOT NULL,                      -- SHA-256(端末UUID + server_salt)
  ip_hash TEXT NOT NULL,                        -- SHA-256(IP + server_salt)
  domain TEXT NOT NULL,                         -- example.com
  url TEXT NOT NULL,                            -- 完全 URL
  url_path_hash TEXT NOT NULL,                  -- SHA-256(URL) 重複検出
  memo TEXT,                                    -- 200 字以内、PII redact 通過後
  status TEXT NOT NULL DEFAULT 'pending',       -- pending/validating/approved/rejected_*/beta
  created_at INTEGER NOT NULL,                  -- Unix sec
  validated_at INTEGER,
  beta_started_at INTEGER,                      -- L7 β tier 開始
  applied_at INTEGER,                           -- stable 昇格
  detected_selector TEXT,                       -- Playwright 検出結果
  rejection_reason TEXT                         -- reject 理由 (status='rejected_*' 時)
);
CREATE INDEX idx_reports_status_created ON reports(status, created_at);
CREATE INDEX idx_reports_uuid_hash ON reports(uuid_hash, created_at DESC);
CREATE INDEX idx_reports_domain_url_path ON reports(domain, url_path_hash);
CREATE INDEX idx_reports_beta_started ON reports(beta_started_at) WHERE status='beta';
