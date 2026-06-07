-- Plan B Task 2.2 (L6 Playwright validation).
-- Add `url` to rule_candidates so L6 can navigate the original page.
-- Nullable so existing aggregating rows (created before this migration) load fine.
ALTER TABLE rule_candidates ADD COLUMN url TEXT;
CREATE INDEX idx_rc_url ON rule_candidates(url);
