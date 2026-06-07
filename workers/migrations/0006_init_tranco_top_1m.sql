-- Plan B Task 1.3 (L3 Tranco list).
-- Stores Tranco Top 1M domains (refreshed weekly by weekly-tranco-sync.yml).
-- New table only — no existing rows, no backfill needed.
CREATE TABLE tranco_top_1m (
  domain TEXT PRIMARY KEY,
  rank INTEGER NOT NULL,
  synced_at INTEGER NOT NULL
);
CREATE INDEX idx_tranco_synced_at ON tranco_top_1m(synced_at);
