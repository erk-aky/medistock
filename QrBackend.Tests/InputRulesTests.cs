using QrBackend.Services;

namespace QrBackend.Tests
{
    public class InputRulesTests
    {
        [Theory]
        [InlineData("  Ayşe Nur  ", "Ayşe_Nur")]
        [InlineData("Ayşe   Nur Yılmaz", "Ayşe_Nur_Yılmaz")]
        [InlineData("ali", "ali")]
        [InlineData(null, "")]
        public void KullaniciAdi_BosluklarTemizlenirAradakilerAltCizgiOlur(string? raw, string expected)
        {
            Assert.Equal(expected, InputRules.NormalizeUsername(raw));
        }

        [Theory]
        [InlineData("Çağrı.Şen-1_", true)]
        [InlineData("ali", true)]
        [InlineData("ab", false)]
        [InlineData("", false)]
        [InlineData("ali@veli", false)]
        [InlineData("ali!", false)]
        public void KullaniciAdi_KuralKontrolu(string username, bool valid)
        {
            Assert.Equal(valid, InputRules.ValidateUsername(username) == null);
        }

        [Fact]
        public void KullaniciAdi_En50Karakter()
        {
            Assert.Null(InputRules.ValidateUsername(new string('a', 50)));
            Assert.NotNull(InputRules.ValidateUsername(new string('a', 51)));
        }

        [Theory]
        [InlineData("  Ali@Test.COM ", "ali@test.com")]
        [InlineData(null, "")]
        public void Eposta_BosluklarSilinirKucukHarfeCevrilir(string? raw, string expected)
        {
            Assert.Equal(expected, InputRules.NormalizeEmail(raw));
        }

        [Theory]
        [InlineData("ali@test.com", true)]
        [InlineData("ali.veli@eczane.com.tr", true)]
        [InlineData("abc", false)]
        [InlineData("ali@test", false)]
        [InlineData("ali @test.com", false)]
        [InlineData("", false)]
        public void Eposta_BicimKontrolu(string email, bool valid)
        {
            Assert.Equal(valid, InputRules.ValidateEmail(email) == null);
        }
    }
}
