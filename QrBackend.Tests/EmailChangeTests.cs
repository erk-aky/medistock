using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.DependencyInjection;
using QrBackend.Services;

namespace QrBackend.Tests
{
    public class EmailChangeTicketTests
    {
        private static readonly DateTimeOffset Now = new(2026, 10, 22, 12, 0, 0, TimeSpan.Zero);
        private readonly EphemeralDataProtectionProvider _provider = new();

        [Fact]
        public void GecerliBilet_BilgileriAynenGeriVerir()
        {
            var tickets = new EmailChangeTicketService(_provider);
            var ticket = tickets.Create(7, "eski@test.com", "yeni@test.com", "123456", Now);

            Assert.Equal(TicketStatus.Valid, tickets.Read(ticket, Now.AddMinutes(10), out var data));
            Assert.Equal(7, data!.UserId);
            Assert.Equal("eski@test.com", data.OldEmail);
            Assert.Equal("yeni@test.com", data.NewEmail);
            Assert.Equal("123456", data.Code);
        }

        [Fact]
        public void SuresiDolmusBilet_Reddedilir()
        {
            var tickets = new EmailChangeTicketService(_provider);
            var ticket = tickets.Create(7, "eski@test.com", "yeni@test.com", "123456", Now);
            Assert.Equal(TicketStatus.Expired, tickets.Read(ticket, Now.AddMinutes(15), out _));
        }

        [Fact]
        public void DegistirilmisBilet_Reddedilir()
        {
            var tickets = new EmailChangeTicketService(_provider);
            var ticket = tickets.Create(7, "eski@test.com", "yeni@test.com", "123456", Now);
            var tampered = ticket.Substring(0, ticket.Length - 2) + (ticket.EndsWith("AA") ? "BB" : "AA");
            Assert.Equal(TicketStatus.Invalid, tickets.Read(tampered, Now, out _));
            Assert.Equal(TicketStatus.Invalid, tickets.Read("", Now, out _));
        }

        [Fact]
        public void KayitBileti_EpostaDegisikligiBiletiYerineKullanilamaz()
        {
            var registration = new RegistrationTicketService(_provider);
            var ticket = registration.Create("ali", "ali@test.com", "hash", "123456", Now);

            Assert.Equal(TicketStatus.Invalid, new EmailChangeTicketService(_provider).Read(ticket, Now, out _));
        }
    }

    public class EmailChangeEndpointTests : IClassFixture<TestApiFactory>
    {
        private readonly TestApiFactory _factory;
        private readonly HttpClient _client;

        public EmailChangeEndpointTests(TestApiFactory factory)
        {
            _factory = factory;
            _client = factory.CreateClient("Production", authorized: false);
        }

        private async Task<(HttpStatusCode Status, string? Message)> PostAsync(string path, object body, int? userId)
        {
            var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = JsonContent.Create(body) };
            if (userId != null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _factory.CreateAccessToken(userId.Value));
            var response = await _client.SendAsync(request);
            var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
            return (response.StatusCode, json.GetProperty("message").GetString());
        }

        // Uygulamanın kendi servisiyle verilen kullanıcı için e-posta değişikliği bileti üretir
        private string CreateTicket(int userId, string code)
        {
            using var scope = _factory.Services.CreateScope();
            return scope.ServiceProvider.GetRequiredService<EmailChangeTicketService>().Create(userId, "eski@test.com", "yeni@test.com", code, DateTimeOffset.UtcNow);
        }

        [Theory]
        [InlineData("/api/v1/auth/change-email/request")]
        [InlineData("/api/v1/auth/change-email/confirm")]
        public async Task TokensizIstek_Reddedilir(string path)
        {
            var (status, _) = await PostAsync(path, new { newEmail = "yeni@test.com", ticket = "x", code = "123456" }, null);
            Assert.Equal(HttpStatusCode.Unauthorized, status);
        }

        [Fact]
        public async Task GecersizEposta_Reddedilir()
        {
            var (status, message) = await PostAsync("/api/v1/auth/change-email/request", new { newEmail = "gecersiz" }, 1);
            Assert.Equal(HttpStatusCode.BadRequest, status);
            Assert.Equal("Geçerli bir e-posta adresi giriniz.", message);
        }

        [Fact]
        public async Task UydurmaBilet_Reddedilir()
        {
            var (status, message) = await PostAsync("/api/v1/auth/change-email/confirm", new { ticket = "uydurma", code = "123456" }, 1);
            Assert.Equal(HttpStatusCode.BadRequest, status);
            Assert.Equal("Geçersiz istek, lütfen e-posta değişikliğini yeniden başlatın.", message);
        }

        [Fact]
        public async Task BaskaKullanicininBileti_Reddedilir()
        {
            var othersTicket = CreateTicket(2, "123456");
            var (status, message) = await PostAsync("/api/v1/auth/change-email/confirm", new { ticket = othersTicket, code = "123456" }, 1);
            Assert.Equal(HttpStatusCode.BadRequest, status);
            Assert.Equal("Geçersiz istek, lütfen e-posta değişikliğini yeniden başlatın.", message);
        }

        [Fact]
        public async Task YanlisKod_Reddedilir()
        {
            var ticket = CreateTicket(1, "123456");
            var (status, message) = await PostAsync("/api/v1/auth/change-email/confirm", new { ticket, code = "654321" }, 1);
            Assert.Equal(HttpStatusCode.BadRequest, status);
            Assert.Equal("Doğrulama kodu hatalı.", message);
        }
    }
}
