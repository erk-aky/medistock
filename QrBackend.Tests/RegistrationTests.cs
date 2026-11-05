using Microsoft.AspNetCore.DataProtection;
using QrBackend.Services;

namespace QrBackend.Tests
{
    public class RegistrationTests
    {
        private static readonly DateTimeOffset Now = new(2026, 10, 20, 12, 0, 0, TimeSpan.Zero);
        private readonly RegistrationTicketService _tickets = new(new EphemeralDataProtectionProvider());

        [Fact]
        public void GecerliBilet_BilgileriAynenGeriVerir()
        {
            var ticket = _tickets.Create("ali", "ali@test.com", "hash", "123456", Now);
            var status = _tickets.Read(ticket, Now.AddMinutes(5), out var data);

            Assert.Equal(TicketStatus.Valid, status);
            Assert.Equal("ali", data!.Username);
            Assert.Equal("ali@test.com", data.Email);
            Assert.Equal("hash", data.PasswordHash);
            Assert.Equal("123456", data.Code);
        }

        [Fact]
        public void Bilet_KoduAcikMetinOlarakIcermez()
        {
            var ticket = _tickets.Create("ali", "ali@test.com", "hash", "123456", Now);
            Assert.DoesNotContain("123456", ticket);
            Assert.DoesNotContain("ali@test.com", ticket);
        }

        [Fact]
        public void SuresiDolmusBilet_Reddedilir()
        {
            var ticket = _tickets.Create("ali", "ali@test.com", "hash", "123456", Now);
            var status = _tickets.Read(ticket, Now.AddMinutes(15), out _);
            Assert.Equal(TicketStatus.Expired, status);
        }

        [Fact]
        public void DegistirilmisBilet_Reddedilir()
        {
            var ticket = _tickets.Create("ali", "ali@test.com", "hash", "123456", Now);
            var tampered = ticket.Substring(0, ticket.Length - 2) + (ticket.EndsWith("AA") ? "BB" : "AA");
            Assert.Equal(TicketStatus.Invalid, _tickets.Read(tampered, Now, out _));
            Assert.Equal(TicketStatus.Invalid, _tickets.Read("", Now, out _));
            Assert.Equal(TicketStatus.Invalid, _tickets.Read("uydurma", Now, out _));
        }

        [Fact]
        public void BaskaAnahtarlaUretilenBilet_Reddedilir()
        {
            var other = new RegistrationTicketService(new EphemeralDataProtectionProvider());
            var ticket = other.Create("ali", "ali@test.com", "hash", "123456", Now);
            Assert.Equal(TicketStatus.Invalid, _tickets.Read(ticket, Now, out _));
        }

        [Fact]
        public void UretilenKod_AltiHaneliRakamdir()
        {
            for (var i = 0; i < 100; i++)
            {
                var code = RegistrationTicketService.GenerateCode();
                Assert.Equal(6, code.Length);
                Assert.True(code.All(char.IsDigit));
            }
        }

        [Fact]
        public void AyniEposta_60SaniyeDolmadanTekrarGonderilemez()
        {
            var cooldown = new EmailCooldown();
            Assert.True(cooldown.TryAcquire("Ali@Test.com", Now, out _));
            Assert.False(cooldown.TryAcquire("ali@test.com ", Now.AddSeconds(30), out var remaining));
            Assert.Equal(30, remaining);
            Assert.True(cooldown.TryAcquire("ali@test.com", Now.AddSeconds(60), out _));
        }

        [Fact]
        public void MailGonderilemezse_HakGeriVerilir()
        {
            var cooldown = new EmailCooldown();
            Assert.True(cooldown.TryAcquire("ali@test.com", Now, out _));
            cooldown.Release("ali@test.com");
            Assert.True(cooldown.TryAcquire("ali@test.com", Now.AddSeconds(1), out _));
        }

        [Fact]
        public void FarkliEpostalar_BirbiriniEngellemez()
        {
            var cooldown = new EmailCooldown();
            Assert.True(cooldown.TryAcquire("ali@test.com", Now, out _));
            Assert.True(cooldown.TryAcquire("ayse@test.com", Now, out _));
        }

        [Theory]
        [InlineData(null, false)]
        [InlineData("", false)]
        [InlineData("12345", false)]
        [InlineData("123456", true)]
        public void SifreKurali_EnAz6Karakter(string? password, bool valid)
        {
            Assert.Equal(valid, InputRules.ValidatePassword(password) == null);
        }
    }
}
