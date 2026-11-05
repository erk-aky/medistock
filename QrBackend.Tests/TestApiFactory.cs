using System.Net.Http.Headers;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using QrBackend.Services;

namespace QrBackend.Tests
{
    public class TestApiFactory : WebApplicationFactory<Program>
    {
        public const string SigningKey = "test-imza-anahtari-en-az-otuz-iki-karakter-uzunlugunda";

        public InMemoryRefreshTokenStore Store { get; } = new();

        // Testlerde sabit imza anahtarı ve bellekteki token deposuyla çalışır
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?> { ["Jwt:SigningKey"] = SigningKey }));
            builder.ConfigureTestServices(services => services.AddSingleton<IRefreshTokenStore>(Store));
        }

        // Verilen ortamda çalışan, istenirse token'lı istemci döner
        public HttpClient CreateClient(string environment, bool authorized)
        {
            var client = WithWebHostBuilder(b => b.UseEnvironment(environment)).CreateClient();
            if (authorized)
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", CreateAccessToken(1));
            return client;
        }

        // Uygulamanın kendi servisiyle giriş token'ı üretir
        public string CreateAccessToken(int userId, DateTimeOffset? now = null)
        {
            using var scope = Services.CreateScope();
            return scope.ServiceProvider.GetRequiredService<TokenService>().CreateAccessToken(userId, now ?? DateTimeOffset.UtcNow);
        }

        // Uygulamanın kendi servisiyle bellekteki depoya kayıtlı token çifti üretir
        public async Task<TokenPair> IssueTokensAsync(int userId)
        {
            using var scope = Services.CreateScope();
            return await scope.ServiceProvider.GetRequiredService<TokenService>().IssueAsync(userId, DateTimeOffset.UtcNow);
        }
    }
}
