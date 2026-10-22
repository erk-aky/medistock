using Npgsql;

namespace QrBackend.Services
{
    public class RefreshTokenRepository : IRefreshTokenStore
    {
        private readonly string _connectionString;

        public RefreshTokenRepository(string connectionString)
        {
            _connectionString = connectionString;
        }

        // Yeni yenileme token'ını kaydeder, kullanıcının süresi geçmiş eski kayıtlarını da temizler
        public async Task AddAsync(int userId, string tokenHash, DateTimeOffset expiresAt, DateTimeOffset now)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = @"
                DELETE FROM refresh_token WHERE user_id = @userId AND expires_at < @now;
                INSERT INTO refresh_token (user_id, token_hash, expires_at, created_at)
                VALUES (@userId, @tokenHash, @expiresAt, @now);";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@userId", userId);
            cmd.Parameters.AddWithValue("@tokenHash", tokenHash);
            cmd.Parameters.AddWithValue("@expiresAt", expiresAt.UtcDateTime);
            cmd.Parameters.AddWithValue("@now", now.UtcDateTime);
            await cmd.ExecuteNonQueryAsync();
        }

        // Hash'i verilen yenileme token'ının kaydını döner, yoksa null döner
        public async Task<RefreshTokenRecord?> FindAsync(string tokenHash)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "SELECT id, user_id, expires_at, revoked_at FROM refresh_token WHERE token_hash = @tokenHash LIMIT 1;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@tokenHash", tokenHash);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return null;

            return new RefreshTokenRecord(
                reader.GetInt64(0),
                reader.GetInt32(1),
                new DateTimeOffset(reader.GetDateTime(2), TimeSpan.Zero),
                reader.IsDBNull(3) ? null : new DateTimeOffset(reader.GetDateTime(3), TimeSpan.Zero));
        }

        // Token henüz iptal edilmemişse iptal eder, bu çağrı iptal ettiyse true döner
        public async Task<bool> RevokeAsync(long id, DateTimeOffset now)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "UPDATE refresh_token SET revoked_at = @now WHERE id = @id AND revoked_at IS NULL;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@now", now.UtcDateTime);
            cmd.Parameters.AddWithValue("@id", id);
            return await cmd.ExecuteNonQueryAsync() == 1;
        }

        // Kullanıcının açık olan bütün oturumlarını kapatır
        public async Task RevokeAllForUserAsync(int userId, DateTimeOffset now)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "UPDATE refresh_token SET revoked_at = @now WHERE user_id = @userId AND revoked_at IS NULL;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@now", now.UtcDateTime);
            cmd.Parameters.AddWithValue("@userId", userId);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
