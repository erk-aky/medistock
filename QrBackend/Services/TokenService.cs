using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using QrBackend.Models;

namespace QrBackend.Services
{
    public record TokenPair(string AccessToken, string RefreshToken);

    public enum RefreshStatus { Success, Invalid, Reused }

    public class TokenService
    {
        private readonly JwtOptions _options;
        private readonly IRefreshTokenStore _store;

        public TokenService(IOptions<JwtOptions> options, IRefreshTokenStore store)
        {
            _options = options.Value;
            _store = store;
        }

        // Ayarlardaki imza anahtarını token imzalamak ve doğrulamak için hazırlar
        public static SymmetricSecurityKey CreateSigningKey(JwtOptions options) =>
            new(Encoding.UTF8.GetBytes(options.SigningKey));

        // Kullanıcı id'sini taşıyan, imzalı ve kısa ömürlü giriş token'ını üretir
        public string CreateAccessToken(int userId, DateTimeOffset now)
        {
            var descriptor = new SecurityTokenDescriptor
            {
                Issuer = _options.Issuer,
                Audience = _options.Audience,
                Subject = new ClaimsIdentity(new[] { new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()) }),
                IssuedAt = now.UtcDateTime,
                NotBefore = now.UtcDateTime,
                Expires = now.AddMinutes(_options.AccessTokenMinutes).UtcDateTime,
                SigningCredentials = new SigningCredentials(CreateSigningKey(_options), SecurityAlgorithms.HmacSha256)
            };
            return new JsonWebTokenHandler().CreateToken(descriptor);
        }

        // Giriş yapan kullanıcıya yeni bir giriş ve yenileme token'ı verir
        public async Task<TokenPair> IssueAsync(int userId, DateTimeOffset now)
        {
            var refreshToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                .TrimEnd('=').Replace('+', '-').Replace('/', '_');

            await _store.AddAsync(userId, Hash(refreshToken), now.AddDays(_options.RefreshTokenDays), now);
            return new TokenPair(CreateAccessToken(userId, now), refreshToken);
        }

        // Yenileme token'ı geçerliyse iptal edip yerine yenisini verir, iptal edilmiş token tekrar gelirse bütün oturumları kapatır
        public async Task<(RefreshStatus Status, TokenPair? Tokens)> RefreshAsync(string refreshToken, DateTimeOffset now)
        {
            if (string.IsNullOrWhiteSpace(refreshToken)) return (RefreshStatus.Invalid, null);

            var record = await _store.FindAsync(Hash(refreshToken));
            if (record == null || record.ExpiresAt <= now) return (RefreshStatus.Invalid, null);

            if (record.RevokedAt != null || !await _store.RevokeAsync(record.Id, now))
            {
                await _store.RevokeAllForUserAsync(record.UserId, now);
                return (RefreshStatus.Reused, null);
            }

            return (RefreshStatus.Success, await IssueAsync(record.UserId, now));
        }

        // Çıkış yapılınca verilen yenileme token'ını iptal eder
        public async Task RevokeAsync(string refreshToken, DateTimeOffset now)
        {
            if (string.IsNullOrWhiteSpace(refreshToken)) return;

            var record = await _store.FindAsync(Hash(refreshToken));
            if (record != null) await _store.RevokeAsync(record.Id, now);
        }

        // Kullanıcının bütün cihazlardaki oturumlarını kapatır
        public Task RevokeAllAsync(int userId, DateTimeOffset now) => _store.RevokeAllForUserAsync(userId, now);

        // Token'ın veritabanında saklanacak SHA-256 özetini döner
        public static string Hash(string token) =>
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    }
}
