namespace QrBackend.Models
{
    public class JwtOptions
    {
        public string Issuer { get; set; } = "QrBackend";
        public string Audience { get; set; } = "QrApp";
        public string SigningKey { get; set; } = string.Empty;
        public int AccessTokenMinutes { get; set; } = 1440;
        public int RefreshTokenDays { get; set; } = 60;
    }
}
