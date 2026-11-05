using Microsoft.Extensions.Logging.Abstractions;
using QrBackend.Services;

namespace QrBackend.Tests
{
    public class ItsServiceTests
    {
        private static ItsService Create(string path) => new(path, NullLogger<ItsService>.Instance);

        private static string WriteTempFile(string content)
        {
            var path = Path.Combine(Path.GetTempPath(), $"its_{Guid.NewGuid():N}.json");
            File.WriteAllText(path, content);
            return path;
        }

        [Fact]
        public async Task GercekSozlukDosyasi_DerlemeCiktisindaVeOkunabilir()
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Data", "its_codes.json");
            Assert.True(File.Exists(path));

            var result = await Create(path).ResolveItsCodeAsync("00000");
            Assert.True(result.Success);
            Assert.StartsWith("Ürün üzerinde", result.Message);
        }

        [Fact]
        public async Task BilinenKod_AciklamasiDoner()
        {
            var path = WriteTempFile("{\"10202\": \"Ürünün Son Kullanma Tarihi Geçmistir.\"}");
            var result = await Create(path).ResolveItsCodeAsync("10202");
            Assert.True(result.Success);
            Assert.Equal("Ürünün Son Kullanma Tarihi Geçmistir.", result.Message);
        }

        [Fact]
        public async Task BilinmeyenKod_TanimlanamayanKodDoner()
        {
            var path = WriteTempFile("{\"10202\": \"x\"}");
            var result = await Create(path).ResolveItsCodeAsync("99999");
            Assert.False(result.Success);
            Assert.Equal("Tanımlanamayan Kod: 99999", result.Message);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("{bozuk json")]
        public async Task DosyaYokVeyaBozuk_AnlasilirMesajDonerYoluSizdirmaz(string? content)
        {
            var path = content == null
                ? Path.Combine(Path.GetTempPath(), $"olmayan_{Guid.NewGuid():N}.json")
                : WriteTempFile(content);

            var result = await Create(path).ResolveItsCodeAsync("00000");
            Assert.False(result.Success);
            Assert.Equal("ITS hata açıklamaları şu an yüklenemedi, lütfen daha sonra tekrar deneyin.", result.Message);
            Assert.DoesNotContain(Path.GetTempPath(), result.Message);
        }

        [Fact]
        public async Task Sozluk_BirKezOkunupBellekteTutulur()
        {
            var path = WriteTempFile("{\"00000\": \"ilk\"}");
            var service = Create(path);
            Assert.Equal("ilk", (await service.ResolveItsCodeAsync("00000")).Message);

            File.WriteAllText(path, "{\"00000\": \"degisti\"}");
            Assert.Equal("ilk", (await service.ResolveItsCodeAsync("00000")).Message);
        }

        [Fact]
        public async Task DosyaSonradanEklenirse_TekrarDenenir()
        {
            var path = Path.Combine(Path.GetTempPath(), $"sonra_{Guid.NewGuid():N}.json");
            var service = Create(path);
            Assert.False((await service.ResolveItsCodeAsync("00000")).Success);

            File.WriteAllText(path, "{\"00000\": \"tamam\"}");
            Assert.True((await service.ResolveItsCodeAsync("00000")).Success);
        }
    }
}
