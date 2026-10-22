-- ================================================================
-- create_refresh_token.sql
-- Oturum yenileme token'larını tutan tabloyu oluşturur.
-- Hedef Postgres veritabanında elle bir kez çalıştırın (psql veya pgAdmin ile).
-- Tekrar çalıştırmak güvenlidir (IF NOT EXISTS koruması var).
-- Token'ın kendisi değil, SHA-256 özeti saklanır.
-- ================================================================

CREATE TABLE IF NOT EXISTS refresh_token (
    id          BIGSERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_refresh_token_user_id ON refresh_token (user_id);
