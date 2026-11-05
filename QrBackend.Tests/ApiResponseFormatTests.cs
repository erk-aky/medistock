using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace QrBackend.Tests
{
    public class ApiResponseFormatTests : IClassFixture<TestApiFactory>
    {
        private readonly TestApiFactory _factory;

        public ApiResponseFormatTests(TestApiFactory factory)
        {
            _factory = factory;
        }

        private HttpClient CreateClient(string environment) => _factory.CreateClient(environment, authorized: true);

        private static async Task<JsonElement> ReadJsonAsync(HttpResponseMessage response)
        {
            var text = await response.Content.ReadAsStringAsync();
            return JsonDocument.Parse(text).RootElement;
        }

        private static StringContent Json(string body) => new(body, Encoding.UTF8, "application/json");

        [Fact]
        public async Task AnaAdres_SuccessTrueDoner()
        {
            var response = await CreateClient("Development").GetAsync("/");
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.True(json.GetProperty("success").GetBoolean());
        }

        [Theory]
        [InlineData("Development")]
        [InlineData("Production")]
        public async Task OlmayanAdres_404VeOrtakBicim(string environment)
        {
            var response = await CreateClient(environment).GetAsync("/olmayan-adres");
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.False(json.GetProperty("success").GetBoolean());
            Assert.Equal("İstenen adres bulunamadı.", json.GetProperty("message").GetString());
        }

        [Fact]
        public async Task YanlisIstekTuru_405VeOrtakBicim()
        {
            var response = await CreateClient("Production").GetAsync("/api/v1/auth/login");
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
            Assert.False(json.GetProperty("success").GetBoolean());
        }

        [Fact]
        public async Task ControllerBozukJson_GelistirmedeDetayliDoner()
        {
            var response = await CreateClient("Development").PostAsync("/api/v1/auth/login", Json("{\"usernameOrEmail\": 5"));
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal("Geçersiz istek biçimi.", json.GetProperty("message").GetString());
            Assert.True(json.TryGetProperty("detail", out _));
        }

        [Fact]
        public async Task ControllerBozukJson_CanlidaDetaysizDoner()
        {
            var response = await CreateClient("Production").PostAsync("/api/v1/auth/login", Json("{\"usernameOrEmail\": 5"));
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal("Geçersiz istek biçimi.", json.GetProperty("message").GetString());
            Assert.False(json.TryGetProperty("detail", out _));
        }

        [Theory]
        [InlineData("Development", true)]
        [InlineData("Production", false)]
        public async Task QrEndpointBozukJson_400VeOrtakBicim(string environment, bool hasDetail)
        {
            var response = await CreateClient(environment).PostAsync("/api/v1/its/resolve-code", Json("{bozuk"));
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.False(json.GetProperty("success").GetBoolean());
            Assert.Equal("Geçersiz istek biçimi.", json.GetProperty("message").GetString());
            Assert.Equal(hasDetail, json.TryGetProperty("detail", out _));
        }

        [Fact]
        public async Task ItsBosKod_400VeOrtakBicim()
        {
            var response = await CreateClient("Production").PostAsJsonAsync("/api/v1/its/resolve-code", new { code = "" });
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.False(json.GetProperty("success").GetBoolean());
            Assert.Equal("Kod boş olamaz.", json.GetProperty("message").GetString());
        }

        [Fact]
        public async Task OnayHataliBilet_400VeOrtakBicim()
        {
            var response = await CreateClient("Production").PostAsJsonAsync("/api/v1/auth/verify-email", new { ticket = "uydurma", code = "123456" });
            var json = await ReadJsonAsync(response);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.False(json.GetProperty("success").GetBoolean());
            Assert.Equal("Geçersiz istek, lütfen kayıt işlemini yeniden başlatın.", json.GetProperty("message").GetString());
        }
    }
}
