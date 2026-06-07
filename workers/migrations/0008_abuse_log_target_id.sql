-- Plan B Task 2.4 (L8 broken-site complaints).
-- Adds target_id so abuse_log can reference the rule_candidate the complaint
-- is about (and dedupe complaints per uuid_hash × target_id).
ALTER TABLE abuse_log ADD COLUMN target_id TEXT;
CREATE INDEX idx_abuse_target ON abuse_log(target_id, reason);
