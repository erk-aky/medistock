using QrBackend.Services;

namespace QrBackend.Tests
{
    public class InMemoryRefreshTokenStore : IRefreshTokenStore
    {
        private class Row
        {
            public long Id;
            public int UserId;
            public string TokenHash = string.Empty;
            public DateTimeOffset ExpiresAt;
            public DateTimeOffset? RevokedAt;
        }

        private readonly List<Row> _rows = new();
        private long _nextId = 1;

        public IReadOnlyList<string> StoredHashes
        {
            get { lock (_rows) return _rows.Select(r => r.TokenHash).ToList(); }
        }

        // Testlerde veritabanı yerine token kaydını bellekte tutar
        public Task AddAsync(int userId, string tokenHash, DateTimeOffset expiresAt, DateTimeOffset now)
        {
            lock (_rows) _rows.Add(new Row { Id = _nextId++, UserId = userId, TokenHash = tokenHash, ExpiresAt = expiresAt });
            return Task.CompletedTask;
        }

        // Hash'i verilen kaydı bellekten bulur
        public Task<RefreshTokenRecord?> FindAsync(string tokenHash)
        {
            lock (_rows)
            {
                var row = _rows.FirstOrDefault(r => r.TokenHash == tokenHash);
                return Task.FromResult(row == null ? null : new RefreshTokenRecord(row.Id, row.UserId, row.ExpiresAt, row.RevokedAt));
            }
        }

        // Kayıt henüz iptal edilmemişse iptal eder
        public Task<bool> RevokeAsync(long id, DateTimeOffset now)
        {
            lock (_rows)
            {
                var row = _rows.FirstOrDefault(r => r.Id == id && r.RevokedAt == null);
                if (row == null) return Task.FromResult(false);
                row.RevokedAt = now;
                return Task.FromResult(true);
            }
        }

        // Kullanıcının açık bütün kayıtlarını iptal eder
        public Task RevokeAllForUserAsync(int userId, DateTimeOffset now)
        {
            lock (_rows)
            {
                foreach (var row in _rows.Where(r => r.UserId == userId && r.RevokedAt == null)) row.RevokedAt = now;
            }
            return Task.CompletedTask;
        }
    }
}
