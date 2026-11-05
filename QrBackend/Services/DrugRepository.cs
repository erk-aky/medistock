using Npgsql;

namespace QrBackend.Services
{
    public record DrugItem(string Barkod, string UrunAdi);

    public class DrugRepository
    {
        private readonly string _connectionString;

        public DrugRepository(string connectionString)
        {
            _connectionString = connectionString;
        }

        // Son başarılı TİTCK senkronunun numarasını ve zamanını döner, hiç yoksa 0 döner
        public async Task<(long Version, DateTimeOffset? UpdatedAt)> GetLatestVersionAsync()
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string query = "SELECT id, started_at FROM sync_log WHERE status = 'success' ORDER BY started_at DESC LIMIT 1;";
            await using var cmd = new NpgsqlCommand(query, conn);
            await using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync())
                return (0, null);

            return (reader.GetInt64(0), reader.GetFieldValue<DateTimeOffset>(1));
        }

        // Telefondaki offline veritabanı için bütün ilaç listesini döner
        public async Task<List<DrugItem>> GetAllDrugsAsync()
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string query = "SELECT barkod, urun_adi FROM qrcodes ORDER BY barkod;";
            await using var cmd = new NpgsqlCommand(query, conn);
            await using var reader = await cmd.ExecuteReaderAsync();

            var rows = new List<DrugItem>();
            while (await reader.ReadAsync())
            {
                rows.Add(new DrugItem(reader.GetString(0), reader.IsDBNull(1) ? "" : reader.GetString(1)));
            }
            return rows;
        }
    }
}
