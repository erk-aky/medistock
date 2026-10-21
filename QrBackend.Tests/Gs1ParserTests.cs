using QrBackend.Services;

namespace QrBackend.Tests
{
    public class Gs1ParserTests
    {
        private const string Gs = "\u001D";

        [Fact]
        public void StandartKarekod_TumAlanlarDogruAyrilir()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "21ABC123" + Gs + "17260331" + "10LOT55");
            Assert.Equal("8699123456789", r.Gtin);
            Assert.Equal("ABC123", r.SerialNo);
            Assert.Equal(new DateTime(2026, 3, 31), r.ExpiryDate);
            Assert.Equal("LOT55", r.BatchNo);
        }

        [Fact]
        public void Gun00_AyinSonGunuAlinir()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "21ABC123" + Gs + "17260200" + "10LOT55");
            Assert.Equal(new DateTime(2026, 2, 28), r.ExpiryDate);
        }

        [Fact]
        public void SeriNoIcinde17_Kesilmez()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "21ABC1745XY" + Gs + "17260331" + "10LOT55");
            Assert.Equal("ABC1745XY", r.SerialNo);
            Assert.Equal(new DateTime(2026, 3, 31), r.ExpiryDate);
        }

        [Fact]
        public void PartiNoIcinde10ve17_Bozulmaz()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "21ABC123" + Gs + "17260331" + "10AB1017");
            Assert.Equal("AB1017", r.BatchNo);
        }

        [Fact]
        public void GsOlmayanKarekod_TahminleAyrilir()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "21ABC1745XY" + "17260331" + "10LOT55");
            Assert.Equal("ABC1745XY", r.SerialNo);
            Assert.Equal(new DateTime(2026, 3, 31), r.ExpiryDate);
            Assert.Equal("LOT55", r.BatchNo);
        }

        [Fact]
        public void GecersizTarih_BosKalirDigerAlanlarOkunur()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "21ABC123" + Gs + "17260230" + "10LOT55");
            Assert.Null(r.ExpiryDate);
            Assert.Equal("8699123456789", r.Gtin);
            Assert.Equal("ABC123", r.SerialNo);
            Assert.Equal("LOT55", r.BatchNo);
        }

        [Fact]
        public void FarkliAlanSirasi_DogruAyrilir()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "17260331" + "10LOT55" + Gs + "21ABC123");
            Assert.Equal("8699123456789", r.Gtin);
            Assert.Equal(new DateTime(2026, 3, 31), r.ExpiryDate);
            Assert.Equal("LOT55", r.BatchNo);
            Assert.Equal("ABC123", r.SerialNo);
        }

        [Fact]
        public void BilinenSabitUzunlukluAlanlar_AtlanipDevamEdilir()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "11250101" + "3103000500" + "17260331" + "10LOT55" + Gs + "21ABC123");
            Assert.Equal("8699123456789", r.Gtin);
            Assert.Equal(new DateTime(2026, 3, 31), r.ExpiryDate);
            Assert.Equal("LOT55", r.BatchNo);
            Assert.Equal("ABC123", r.SerialNo);
        }

        [Fact]
        public void BilinmeyenDegiskenUzunlukluAlan_GsIleAtlanir()
        {
            var r = Gs1Parser.Parse("0108699123456789" + "240XYZ" + Gs + "21ABC123" + Gs + "17260331");
            Assert.Equal("ABC123", r.SerialNo);
            Assert.Equal(new DateTime(2026, 3, 31), r.ExpiryDate);
        }

        [Theory]
        [InlineData("010869968009034421I01001000766908617290831102502730009", "I010010007669086", 2029, 8, 31)]
        [InlineData("010869968009034421I01001000766876517290831102502730009", "I010010007668765", 2029, 8, 31)]
        [InlineData("010869968009034421I01001000766909417290831102502730009", "I010010007669094", 2029, 8, 31)]
        [InlineData("010869968009034421I01001000766909017290831102502730009", "I010010007669090", 2029, 8, 31)]
        [InlineData("010869968009034421I01001000766876917290831102502730009", "I010010007668769", 2029, 8, 31)]
        [InlineData("010869968009034421I01001000766343417260531102502730009", "I010010007663434", 2026, 5, 31)]
        public void GercekGsSizIlacKarekodlari_DogruAyrilir(string raw, string serial, int year, int month, int day)
        {
            var r = Gs1Parser.Parse(raw);
            Assert.Equal("8699680090344", r.Gtin);
            Assert.Equal(serial, r.SerialNo);
            Assert.Equal(new DateTime(year, month, day), r.ExpiryDate);
            Assert.Equal("2502730009", r.BatchNo);
        }

        [Theory]
        [InlineData("")]
        [InlineData("   ")]
        [InlineData("merhaba")]
        [InlineData("01123")]
        [InlineData("17")]
        [InlineData("\u001D")]
        public void BosVeyaAnlamsizMetin_HataVermez(string raw)
        {
            var r = Gs1Parser.Parse(raw);
            Assert.Null(r.Gtin);
            Assert.Null(r.ExpiryDate);
        }
    }
}
