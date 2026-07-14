-- ================================================================
-- init_sync_tables.sql
-- TİTCK haftalık senkron özelliği için gereken tabloları oluşturur.
-- Bu proje EF Core / migration aracı kullanmıyor; bu script'i hedef
-- Postgres veritabanına elle bir kez çalıştırın (örn. psql veya pgAdmin ile).
-- Tekrar çalıştırmak güvenlidir (IF NOT EXISTS koruması var).
--
-- qrcodes gerçek şeması (pgAdmin'den teyit edildi):
--   id        integer, PK, nextval('qrcodes_id_seq')
--   barkod    character varying(20)  -- NOT unique/PK, tekrar edebilir
--   urun_adi  text
--
-- ✅ ÇALIŞTIRILDI: 2026-07-14 tarihinde uzak (prod) veritabanında
-- pgAdmin üzerinden başarıyla çalıştırıldı, sync_log ve qrcodes_copy
-- tabloları oluşturuldu. Yanlışlıkla tekrar çalıştırılmasını önlemek
-- için aşağıdaki komutlar tamamen yorum satırına alınmıştır.
-- Yeni bir ortamda (örn. test/staging DB) bu tabloları yeniden kurman
-- gerekirse, aşağıdaki /* */ bloğunu kaldırıp çalıştırabilirsin.
-- ================================================================

/*

CREATE TABLE IF NOT EXISTS sync_log (
    id                  BIGSERIAL PRIMARY KEY,
    started_at          TIMESTAMPTZ NOT NULL,
    finished_at         TIMESTAMPTZ,
    status              TEXT NOT NULL,              -- 'success' | 'failed'
    source_url          TEXT NOT NULL,               -- bu çalıştırmada kullanılan .xlsx URL'i
    row_count           INTEGER,                     -- kaynaktan ayrıştırılan satır sayısı (parse'a ulaşamadan hata olduysa null)
    rows_added          INTEGER,                     -- INSERT edilen satır sayısı (başarısızlıkta null)
    rows_updated        INTEGER,                     -- UPDATE edilen satır sayısı (başarısızlıkta null)
    failed_step         TEXT,                        -- 'DownloadPage','DownloadExcel','ParseExcel','AnomalyCheck','BackupCopy','DiffTransaction','Unknown'
    error_message       TEXT,                        -- hata mesajı / anomali detayı
    duration_ms         INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Anomali korumasının "son başarılı çalıştırma" sorgusunu hızlandırır.
CREATE INDEX IF NOT EXISTS ix_sync_log_status_started_at
    ON sync_log (status, started_at DESC);

-- Basit yedek tablo: her senkron çalıştırmasından önce mevcut
-- qrcodes içeriğinin bir kopyası buraya alınır (view/atomic-swap
-- mekanizması DEĞİL, sadece düz bir yedek).
CREATE TABLE IF NOT EXISTS qrcodes_copy (
    id                  INTEGER,
    barkod              VARCHAR(20),
    urun_adi            TEXT,
    copied_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

*/

-- ================================================================
-- YENİ: titck_staging (2026-07-14, ikinci ekleme — bunu ÇALIŞTIR)
-- İlk denemede geçici (TEMP) tablo kullanılmıştı ama uzak sunucuda
-- "relation titck_staging does not exist" hatası alındı (muhtemelen
-- bağlantı havuzlama/proxy nedeniyle oturum garantisi bozuluyor).
-- Bunun yerine kalıcı bir staging tablosu kullanılıyor; her senkron
-- çalıştırmasının başında TRUNCATE edilip yeniden doldurulur.
-- ================================================================
CREATE TABLE IF NOT EXISTS titck_staging (
    barkod              TEXT,
    urun_adi            TEXT
);
