using Npgsql;
using NpgsqlTypes;
using QrBackend.Models;

namespace QrBackend.Services
{
    public class TitckSyncRepository
    {
        private readonly string _connectionString;

        public TitckSyncRepository(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int?> GetLastSuccessfulRowCountAsync(CancellationToken ct)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync(ct);

            const string sql = "SELECT row_count FROM sync_log WHERE status = 'success' ORDER BY started_at DESC LIMIT 1;";
            await using var cmd = new NpgsqlCommand(sql, conn);
            var result = await cmd.ExecuteScalarAsync(ct);

            if (result == null || result == DBNull.Value) return null;
            return Convert.ToInt32(result);
        }

        public async Task BackupQrcodesToCopyAsync(CancellationToken ct)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync(ct);

            await using var truncateCmd = new NpgsqlCommand("TRUNCATE qrcodes_copy;", conn);
            await truncateCmd.ExecuteNonQueryAsync(ct);

            await using var insertCmd = new NpgsqlCommand(
                "INSERT INTO qrcodes_copy (id, barkod, urun_adi, copied_at) SELECT id, barkod, urun_adi, now() FROM qrcodes;", conn);
            await insertCmd.ExecuteNonQueryAsync(ct);
        }

        public async Task<(List<TitckDrugRow> Added, int Updated)> LoadAndDiffAsync(List<TitckDrugRow> rows, double updatePercentAnomalyThreshold, CancellationToken ct)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync(ct);

            await using var truncateStagingCmd = new NpgsqlCommand("TRUNCATE titck_staging;", conn);
            await truncateStagingCmd.ExecuteNonQueryAsync(ct);

            await using (var writer = await conn.BeginBinaryImportAsync(
                "COPY titck_staging (barkod, urun_adi) FROM STDIN (FORMAT BINARY)", ct))
            {
                foreach (var row in rows)
                {
                    await writer.StartRowAsync(ct);
                    await writer.WriteAsync(row.Barkod, NpgsqlDbType.Text, ct);
                    await writer.WriteAsync(row.UrunAdi, NpgsqlDbType.Text, ct);
                }
                await writer.CompleteAsync(ct);
            }

            await using var tx = await conn.BeginTransactionAsync(ct);

            await using var insertCmd = new NpgsqlCommand(
                @"INSERT INTO qrcodes (barkod, urun_adi)
                  SELECT s.barkod, s.urun_adi
                  FROM titck_staging s
                  LEFT JOIN qrcodes q ON q.barkod = s.barkod
                  WHERE q.barkod IS NULL
                  RETURNING barkod, urun_adi;", conn, tx);

            var added = new List<TitckDrugRow>();
            await using (var reader = await insertCmd.ExecuteReaderAsync(ct))
            {
                while (await reader.ReadAsync(ct))
                {
                    added.Add(new TitckDrugRow(reader.GetString(0), reader.IsDBNull(1) ? "" : reader.GetString(1)));
                }
            }

            await using var updateCmd = new NpgsqlCommand(
                @"UPDATE qrcodes q
                  SET urun_adi = s.urun_adi
                  FROM titck_staging s
                  WHERE q.barkod = s.barkod
                    AND q.urun_adi IS DISTINCT FROM s.urun_adi;", conn, tx);
            var updated = await updateCmd.ExecuteNonQueryAsync(ct);

            if (rows.Count > 0)
            {
                var updatedPct = updated / (double)rows.Count * 100;
                if (updatedPct > updatePercentAnomalyThreshold)
                {
                    await tx.RollbackAsync(ct);
                    throw new InvalidOperationException(
                        $"Güncellenen satır oranı %{updatedPct:F1} eşiği (%{updatePercentAnomalyThreshold}) aştı ({updated}/{rows.Count}). Kaynak dosya bozuk olabilir, hiçbir değişiklik uygulanmadı.");
                }
            }

            await tx.CommitAsync(ct);

            return (added, updated);
        }

        public async Task<long> InsertSyncLogAsync(SyncLogEntry entry, CancellationToken ct)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync(ct);

            const string sql = @"
                INSERT INTO sync_log
                    (started_at, finished_at, status, source_url, row_count, rows_added, rows_updated, failed_step, error_message, duration_ms)
                VALUES
                    (@started_at, @finished_at, @status, @source_url, @row_count, @rows_added, @rows_updated, @failed_step, @error_message, @duration_ms)
                RETURNING id;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@started_at", entry.StartedAt);
            cmd.Parameters.AddWithValue("@finished_at", (object?)entry.FinishedAt ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@status", entry.Status);
            cmd.Parameters.AddWithValue("@source_url", entry.SourceUrl);
            cmd.Parameters.AddWithValue("@row_count", (object?)entry.RowCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@rows_added", (object?)entry.RowsAdded ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@rows_updated", (object?)entry.RowsUpdated ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@failed_step", (object?)entry.FailedStep ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@error_message", (object?)entry.ErrorMessage ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@duration_ms", entry.DurationMs);

            var id = await cmd.ExecuteScalarAsync(ct);
            return Convert.ToInt64(id);
        }
    }
}
