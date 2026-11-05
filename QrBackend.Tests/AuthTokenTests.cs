using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace QrBackend.Tests
{
    public class AuthTokenTests : IClassFixture<TestApiFactory>
    {
        private const string SessionExpiredMessage = "Oturumunuzun süresi doldu, lütfen tekrar giriş yapın.";

        private readonly TestApiFactory _factory;
        private readonly HttpClient _client;

        public AuthTokenTests(TestApiFactory factory)
        {
            _factory = factory;
            _client = factory.CreateClient("Production", authorized: false);
        }

        private static async Task<JsonElement> ReadJsonAsync(HttpResponseMessage response) =>
            JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

        private Task<HttpResponseMessage> SendAsync(string method, string path, string? token = null, object? body = null)
        {
            var request = new HttpRequestMessage(new HttpMethod(method), path) { Content = JsonContent.Create(body ?? new { }) };
            if (token != null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            return _client.SendAsync(request);
        }

        private static async Task AssertSessionExpiredAsync(HttpResponseMessage response)
        {
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
            Assert.False(json.GetProperty("success").GetBoolean());
            Assert.Equal(SessionExpiredMessage, json.GetProperty("message").GetString());
        }

        [Theory]
        [InlineData("GET", "/api/v1/qr/db-version")]
        [InlineData("GET", "/api/v1/qr/db-export")]
        [InlineData("POST", "/api/v1/its/resolve-code")]
        [InlineData("GET", "/api/v1/auth/me")]
        [InlineData("PUT", "/api/v1/auth/update-profile")]
        [InlineData("POST", "/api/v1/admin/titck-sync/run")]
        public async Task KorunanAdres_TokensizIstegi401IleReddeder(string method, string path)
        {
            await AssertSessionExpiredAsync(await SendAsync(method, path));
        }

        [Fact]
        public async Task SahteToken_Reddedilir()
        {
            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/its/resolve-code", "abc.def.ghi"));
        }

        [Fact]
        public async Task SuresiDolmusToken_Reddedilir()
        {
            var expired = _factory.CreateAccessToken(1, DateTimeOffset.UtcNow.AddDays(-2));
            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/its/resolve-code", expired));
        }

        [Fact]
        public async Task BaskaAnahtarlaImzalanmisToken_Reddedilir()
        {
            var descriptor = new SecurityTokenDescriptor
            {
                Issuer = "QrBackend",
                Audience = "QrApp",
                Subject = new ClaimsIdentity(new[] { new Claim(JwtRegisteredClaimNames.Sub, "1") }),
                Expires = DateTime.UtcNow.AddHours(1),
                SigningCredentials = new SigningCredentials(
                    new SymmetricSecurityKey(Encoding.UTF8.GetBytes("saldirganin-kendi-anahtari-otuz-iki-karakterden-uzun")),
                    SecurityAlgorithms.HmacSha256)
            };
            var forged = new JsonWebTokenHandler().CreateToken(descriptor);

            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/its/resolve-code", forged));
        }

        [Fact]
        public async Task GecerliToken_KorunanAdreseUlasir()
        {
            var response = await SendAsync("POST", "/api/v1/its/resolve-code", _factory.CreateAccessToken(1), new { code = "" });
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal("Kod boş olamaz.", json.GetProperty("message").GetString());
        }

        [Theory]
        [InlineData("/api/v1/auth/verify-email", "Geçersiz istek, lütfen kayıt işlemini yeniden başlatın.")]
        [InlineData("/api/v1/auth/forgot-password", "Geçerli bir e-posta adresi giriniz.")]
        [InlineData("/api/v1/auth/reset-password", "Şifre en az 6 karakter olmalıdır.")]
        public async Task GirisOncesiAdresler_TokensizCalisir(string path, string expectedMessage)
        {
            var response = await SendAsync("POST", path, body: new { ticket = "uydurma", code = "123456", email = "", newPassword = "" });
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal(expectedMessage, json.GetProperty("message").GetString());
        }

        [Fact]
        public async Task Yenileme_YeniTokenVerirVeYeniTokenCalisir()
        {
            var tokens = await _factory.IssueTokensAsync(10);

            var response = await SendAsync("POST", "/api/v1/auth/refresh", body: new { refreshToken = tokens.RefreshToken });
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.True(json.GetProperty("success").GetBoolean());

            var newAccess = json.GetProperty("accessToken").GetString();
            var check = await SendAsync("POST", "/api/v1/its/resolve-code", newAccess, new { code = "" });
            Assert.Equal(HttpStatusCode.BadRequest, check.StatusCode);
        }

        [Fact]
        public async Task KullanilmisYenilemeTokeni_401DonerVeYeniTokeniDeKapatir()
        {
            var tokens = await _factory.IssueTokensAsync(11);
            var first = await ReadJsonAsync(await SendAsync("POST", "/api/v1/auth/refresh", body: new { refreshToken = tokens.RefreshToken }));
            var renewed = first.GetProperty("refreshToken").GetString();

            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/auth/refresh", body: new { refreshToken = tokens.RefreshToken }));
            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/auth/refresh", body: new { refreshToken = renewed }));
        }

        [Fact]
        public async Task CikisSonrasi_YenilemeReddedilir()
        {
            var tokens = await _factory.IssueTokensAsync(12);

            var logout = await SendAsync("POST", "/api/v1/auth/logout", body: new { refreshToken = tokens.RefreshToken });
            Assert.Equal(HttpStatusCode.OK, logout.StatusCode);

            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/auth/refresh", body: new { refreshToken = tokens.RefreshToken }));
        }

        [Fact]
        public async Task UydurmaYenilemeTokeni_401Doner()
        {
            await AssertSessionExpiredAsync(await SendAsync("POST", "/api/v1/auth/refresh", body: new { refreshToken = "uydurma" }));
        }
    }
}
