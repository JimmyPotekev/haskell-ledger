-- Ledger schema. Run this once against the ledger database.
-- Everything is BIGINT because this is money and nobody wants
-- to find out their IDs ran out after a few billion rows.

CREATE TABLE IF NOT EXISTS accounts (
  id   BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS transactions (
  id              BIGSERIAL PRIMARY KEY,
  idempotency_key TEXT UNIQUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS entries (
  id             BIGSERIAL PRIMARY KEY,
  transaction_id BIGINT NOT NULL REFERENCES transactions(id),
  account_id     BIGINT NOT NULL REFERENCES accounts(id),
  amount_cents   BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS entries_account_id_idx ON entries(account_id);