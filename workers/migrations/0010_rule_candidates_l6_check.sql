-- Plan B Task 2.2 (L6 Playwright validation) schema fix.
-- scripts/validation/playwright-validate.ts writes `l6_check` in its UPDATE,
-- but 0002 only created l3_check/l4_check/l5_check. The column was never added,
-- so the first candidate that passes Playwright validation would throw
-- "no such column: l6_check" and crash the whole daily-validation run.
-- Nullable (pass/fail TEXT) like l3/l4/l5_check; existing rows load fine.
ALTER TABLE rule_candidates ADD COLUMN l6_check TEXT;
