namespace QrBackend.Services
{
    public record RefreshTokenRecord(long Id, int UserId, DateTimeOffset ExpiresAt, DateTimeOffset? RevokedAt);

    public interface IRefreshTokenStore
    {
        Task AddAsync(int userId, string tokenHash, DateTimeOffset expiresAt, DateTimeOffset now);
        Task<RefreshTokenRecord?> FindAsync(string tokenHash);
        Task<bool> RevokeAsync(long id, DateTimeOffset now);
        Task RevokeAllForUserAsync(int userId, DateTimeOffset now);
    }
}
