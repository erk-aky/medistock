using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using QrBackend.Models;
using QrBackend.Services;

namespace QrBackend.Tests
{
    public class TokenServiceTests
    {
        private static readonly DateTimeOffset Now = new(2026, 10, 22, 12, 0, 0, TimeSpan.Zero);
        private readonly InMemoryRefreshTokenStore _store = new();
        private readonly TokenService _service;

        public TokenServiceTests()
        {
            _service = new TokenService(Options.Create(new JwtOptions { SigningKey = TestApiFactory.SigningKey }), _store);
        }

        [Fact]
        public void GirisTokeni_KullaniciIdsiniVeBirGunlukSureyiTasir()
        {
            var token = new JsonWebTokenHandler().ReadJsonWebToken(_service.CreateAccessToken(42, Now));

            Assert.Equal("42", token.Subject);
            Assert.Equal(Now.AddDays(1).UtcDateTime, token.ValidTo);
            Assert.Equal("QrBackend", token.Issuer);
        }

        [Fact]
        public async Task YenilemeTokeni_VeritabanindaAcikMetinOlarakTutulmaz()
        {
            var tokens = await _service.IssueAsync(1, Now);

            Assert.DoesNotContain(tokens.RefreshToken, _store.StoredHashes);
            Assert.Contains(TokenService.Hash(tokens.RefreshToken), _store.StoredHashes);
        }

        [Fact]
        public async Task GecerliYenileme_YeniTokenVerirVeSureyiBastanBaslatir()
        {
            var first = await _service.IssueAsync(1, Now);
            var later = Now.AddDays(59);

            var (status, second) = await _service.RefreshAsync(first.RefreshToken, later);

            Assert.Equal(RefreshStatus.Success, status);
            Assert.NotEqual(first.RefreshToken, second!.RefreshToken);
            var record = await _store.FindAsync(TokenService.Hash(second.RefreshToken));
            Assert.Equal(later.AddDays(60), record!.ExpiresAt);
        }

        [Fact]
        public async Task SuresiDolmusYenileme_Reddedilir()
        {
            var tokens = await _service.IssueAsync(1, Now);
            var (status, _) = await _service.RefreshAsync(tokens.RefreshToken, Now.AddDays(60));
            Assert.Equal(RefreshStatus.Invalid, status);
        }

        [Theory]
        [InlineData("")]
        [InlineData("uydurma-token")]
        public async Task BilinmeyenYenileme_Reddedilir(string refreshToken)
        {
            var (status, _) = await _service.RefreshAsync(refreshToken, Now);
            Assert.Equal(RefreshStatus.Invalid, status);
        }

        [Fact]
        public async Task KullanilmisTokenTekrarGelirse_ButunOturumlarKapanir()
        {
            var phone = await _service.IssueAsync(1, Now);
            var otherPhone = await _service.IssueAsync(1, Now);
            var (_, renewed) = await _service.RefreshAsync(phone.RefreshToken, Now.AddHours(1));

            var (status, _) = await _service.RefreshAsync(phone.RefreshToken, Now.AddHours(2));

            Assert.Equal(RefreshStatus.Reused, status);
            Assert.NotEqual(RefreshStatus.Success, (await _service.RefreshAsync(renewed!.RefreshToken, Now.AddHours(3))).Status);
            Assert.NotEqual(RefreshStatus.Success, (await _service.RefreshAsync(otherPhone.RefreshToken, Now.AddHours(3))).Status);
        }

        [Fact]
        public async Task KullanilmisToken_BaskaKullanicininOturumunuEtkilemez()
        {
            var ali = await _service.IssueAsync(1, Now);
            var ayse = await _service.IssueAsync(2, Now);
            await _service.RefreshAsync(ali.RefreshToken, Now);
            await _service.RefreshAsync(ali.RefreshToken, Now);

            var (status, _) = await _service.RefreshAsync(ayse.RefreshToken, Now);
            Assert.Equal(RefreshStatus.Success, status);
        }

        [Fact]
        public async Task CikisYapilinca_YenilemeTokeniCalismaz()
        {
            var tokens = await _service.IssueAsync(1, Now);
            await _service.RevokeAsync(tokens.RefreshToken, Now);

            var (status, _) = await _service.RefreshAsync(tokens.RefreshToken, Now);
            Assert.NotEqual(RefreshStatus.Success, status);
        }

        [Fact]
        public async Task ButunOturumlarKapatilinca_HicbirCihazYenileyemez()
        {
            var phone = await _service.IssueAsync(1, Now);
            var otherPhone = await _service.IssueAsync(1, Now);
            await _service.RevokeAllAsync(1, Now);

            Assert.NotEqual(RefreshStatus.Success, (await _service.RefreshAsync(phone.RefreshToken, Now)).Status);
            Assert.NotEqual(RefreshStatus.Success, (await _service.RefreshAsync(otherPhone.RefreshToken, Now)).Status);
        }
    }
}
