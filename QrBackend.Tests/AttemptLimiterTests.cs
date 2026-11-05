using QrBackend.Services;

namespace QrBackend.Tests
{
    public class AttemptLimiterTests
    {
        private static readonly DateTimeOffset Now = new(2026, 10, 22, 12, 0, 0, TimeSpan.Zero);
        private readonly AttemptLimiter _limiter = new();

        private LoginFailure Fail(int times, DateTimeOffset at)
        {
            LoginFailure last = null!;
            for (var i = 0; i < times; i++) last = _limiter.RegisterLoginFailure("ali", at);
            return last;
        }

        [Fact]
        public void YanlisSifre_KalanHakkiAzaltir()
        {
            Assert.Equal(4, _limiter.RegisterLoginFailure("ali", Now).RemainingAttempts);
            Assert.Equal(3, _limiter.RegisterLoginFailure("ali", Now).RemainingAttempts);
            Assert.Null(_limiter.LoginLockRemaining("ali", Now));
        }

        [Fact]
        public void BesYanlis_15DakikaKilitler()
        {
            var last = Fail(5, Now);

            Assert.Equal(AttemptLimiter.FirstLoginLock, last.LockedFor);
            Assert.Equal(TimeSpan.FromMinutes(15), _limiter.LoginLockRemaining("ali", Now));
            Assert.Null(_limiter.LoginLockRemaining("ali", Now.AddMinutes(15)));
        }

        [Fact]
        public void KilittenSonraUcYanlis_24SaatKilitler()
        {
            Fail(5, Now);
            var afterLock = Now.AddMinutes(16);

            Assert.Equal(2, _limiter.RegisterLoginFailure("ali", afterLock).RemainingAttempts);
            Assert.Equal(1, _limiter.RegisterLoginFailure("ali", afterLock).RemainingAttempts);
            var last = _limiter.RegisterLoginFailure("ali", afterLock);

            Assert.Equal(AttemptLimiter.SecondLoginLock, last.LockedFor);
            Assert.Equal(TimeSpan.FromHours(24), _limiter.LoginLockRemaining("ali", afterLock));
        }

        [Fact]
        public void YirmiDortSaatlikKilitBitince_HaklarBastanBaslar()
        {
            Fail(5, Now);
            var afterFirst = Now.AddMinutes(16);
            for (var i = 0; i < 3; i++) _limiter.RegisterLoginFailure("ali", afterFirst);

            var afterSecond = afterFirst.AddHours(24);
            Assert.Equal(4, _limiter.RegisterLoginFailure("ali", afterSecond).RemainingAttempts);
        }

        [Fact]
        public void DogruGiris_SayaciSifirlar()
        {
            Fail(4, Now);
            _limiter.ResetLogin("ali");
            Assert.Equal(4, _limiter.RegisterLoginFailure("ali", Now).RemainingAttempts);
        }

        [Fact]
        public void EskiYanlislar_BirGunSonraUnutulur()
        {
            Fail(4, Now);
            Assert.Equal(4, _limiter.RegisterLoginFailure("ali", Now.AddHours(25)).RemainingAttempts);
        }

        [Fact]
        public void HesaplarBirbirindenBagimsizdir()
        {
            Fail(5, Now);
            Assert.Null(_limiter.LoginLockRemaining("ayse", Now));
            Assert.NotNull(_limiter.LoginLockRemaining(" ALI ", Now));
        }

        [Fact]
        public void KodUcKezYanlisGirilince_DenemeKapanir()
        {
            _limiter.RegisterCodeSent(CodeFlow.ResetPassword, "ali@test.com", Now);

            Assert.Equal(2, _limiter.RegisterWrongCode(CodeFlow.ResetPassword, "ali@test.com", Now).RemainingAttempts);
            Assert.Equal(1, _limiter.RegisterWrongCode(CodeFlow.ResetPassword, "ali@test.com", Now).RemainingAttempts);
            var last = _limiter.RegisterWrongCode(CodeFlow.ResetPassword, "ali@test.com", Now);

            Assert.Equal(0, last.RemainingAttempts);
            Assert.False(last.Blocked);
            Assert.Equal(AttemptLimiter.CodeUsedUpMessage, _limiter.CodeVerifyBlockedMessage(CodeFlow.ResetPassword, "ali@test.com", Now));
        }

        [Fact]
        public void YeniKod_DenemeHakkiniYeniler()
        {
            _limiter.RegisterCodeSent(CodeFlow.ResetPassword, "ali@test.com", Now);
            for (var i = 0; i < 3; i++) _limiter.RegisterWrongCode(CodeFlow.ResetPassword, "ali@test.com", Now);

            Assert.Null(_limiter.CodeSendBlockedMessage(CodeFlow.ResetPassword, "ali@test.com", Now));
            _limiter.RegisterCodeSent(CodeFlow.ResetPassword, "ali@test.com", Now);

            Assert.Null(_limiter.CodeVerifyBlockedMessage(CodeFlow.ResetPassword, "ali@test.com", Now));
            Assert.Equal(2, _limiter.RegisterWrongCode(CodeFlow.ResetPassword, "ali@test.com", Now).RemainingAttempts);
        }

        [Fact]
        public void SonKodunHaklariBitince_Akis24SaatKapanir()
        {
            for (var code = 0; code < AttemptLimiter.MaxCodes; code++)
            {
                Assert.Null(_limiter.CodeSendBlockedMessage(CodeFlow.Register, "ali@test.com", Now));
                _limiter.RegisterCodeSent(CodeFlow.Register, "ali@test.com", Now);
                for (var i = 0; i < 2; i++) _limiter.RegisterWrongCode(CodeFlow.Register, "ali@test.com", Now);
                var third = _limiter.RegisterWrongCode(CodeFlow.Register, "ali@test.com", Now);
                Assert.Equal(code == AttemptLimiter.MaxCodes - 1, third.Blocked);
            }

            Assert.Contains("24 saat", _limiter.CodeSendBlockedMessage(CodeFlow.Register, "ali@test.com", Now));
            Assert.Contains("24 saat", _limiter.CodeVerifyBlockedMessage(CodeFlow.Register, "ali@test.com", Now));
            Assert.Null(_limiter.CodeSendBlockedMessage(CodeFlow.Register, "ali@test.com", Now.AddHours(24)));
        }

        [Fact]
        public void DortKodGonderildiyse_BesinciGonderilmez()
        {
            for (var i = 0; i < AttemptLimiter.MaxCodes; i++) _limiter.RegisterCodeSent(CodeFlow.EmailChange, "7", Now);

            Assert.NotNull(_limiter.CodeSendBlockedMessage(CodeFlow.EmailChange, "7", Now));
            Assert.Null(_limiter.CodeSendBlockedMessage(CodeFlow.EmailChange, "7", Now.AddHours(24)));
        }

        [Fact]
        public void BasariliDogrulama_KodSayaciniSifirlar()
        {
            for (var i = 0; i < AttemptLimiter.MaxCodes; i++) _limiter.RegisterCodeSent(CodeFlow.Register, "ali@test.com", Now);
            _limiter.ResetCode(CodeFlow.Register, "ali@test.com");
            Assert.Null(_limiter.CodeSendBlockedMessage(CodeFlow.Register, "ali@test.com", Now));
        }

        [Fact]
        public void AkislarBirbirindenBagimsizdir()
        {
            for (var i = 0; i < AttemptLimiter.MaxCodes; i++) _limiter.RegisterCodeSent(CodeFlow.Register, "ali@test.com", Now);
            Assert.Null(_limiter.CodeSendBlockedMessage(CodeFlow.ResetPassword, "ali@test.com", Now));
        }

        [Theory]
        [InlineData(30, "30 dakika")]
        [InlineData(0.2, "1 dakika")]
        [InlineData(60, "60 dakika")]
        [InlineData(61, "2 saat")]
        [InlineData(1440, "24 saat")]
        public void SureMetni_OkunurBicimdedir(double minutes, string expected)
        {
            Assert.Equal(expected, AttemptLimiter.FormatDuration(TimeSpan.FromMinutes(minutes)));
        }
    }
}
