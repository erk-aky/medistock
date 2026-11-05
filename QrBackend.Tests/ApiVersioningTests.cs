using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace QrBackend.Tests
{
    public class ApiVersioningTests : IClassFixture<TestApiFactory>
    {
        private const string UnsupportedVersionMessage = "Bu API sürümü desteklenmiyor, lütfen uygulamayı güncelleyin.";
        private const string NotFoundMessage = "İstenen adres bulunamadı.";

        private readonly HttpClient _client;

        public ApiVersioningTests(TestApiFactory factory)
        {
            _client = factory.CreateClient("Production", authorized: true);
        }

        private static async Task<string?> MessageAsync(HttpResponseMessage response)
        {
            var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
            return json.GetProperty("message").GetString();
        }

        [Fact]
        public async Task V1Adresi_CalisirVeDesteklenenSurumleriBildirir()
        {
            var response = await _client.PostAsJsonAsync("/api/v1/auth/verify-email", new { ticket = "uydurma", code = "123456" });
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal("Geçersiz istek, lütfen kayıt işlemini yeniden başlatın.", await MessageAsync(response));
            Assert.True(response.Headers.TryGetValues("api-supported-versions", out var versions));
            Assert.Contains("1.0", versions!.Single());
        }

        [Theory]
        [InlineData("GET", "/api/v2/qr/db-version")]
        [InlineData("POST", "/api/v9/auth/verify-email")]
        [InlineData("POST", "/api/v2.0/its/resolve-code")]
        public async Task DesteklenmeyenSurum_GuncellemeMesajiDoner(string method, string path)
        {
            var request = new HttpRequestMessage(new HttpMethod(method), path) { Content = JsonContent.Create(new { }) };
            var response = await _client.SendAsync(request);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.Equal(UnsupportedVersionMessage, await MessageAsync(response));
        }

        [Theory]
        [InlineData("/api/qr/db-version")]
        [InlineData("/api/auth/login")]
        [InlineData("/api/v1/olmayan")]
        public async Task SurumsuzVeyaOlmayanAdres_AdresBulunamadiDoner(string path)
        {
            var response = await _client.GetAsync(path);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.Equal(NotFoundMessage, await MessageAsync(response));
        }

        [Fact]
        public async Task AdminEndpoint_CanlidaKapali()
        {
            var response = await _client.PostAsync("/api/v1/admin/titck-sync/run", null);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.Equal(NotFoundMessage, await MessageAsync(response));
        }

        [Fact]
        public async Task SaglikKontrolu_SurumsuzKalir()
        {
            var response = await _client.GetAsync("/");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
    }
}
