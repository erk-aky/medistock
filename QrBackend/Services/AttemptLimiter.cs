using System.Collections.Concurrent;

namespace QrBackend.Services
{
    public enum CodeFlow { Register, ResetPassword, EmailChange }

    public record LoginFailure(int RemainingAttempts, TimeSpan? LockedFor);

    public record CodeFailure(int RemainingAttempts, bool Blocked);

    public class AttemptLimiter
    {
        public const int LoginAttempts = 5;
        public const int LoginAttemptsAfterLock = 3;
        public static readonly TimeSpan FirstLoginLock = TimeSpan.FromMinutes(15);
        public static readonly TimeSpan SecondLoginLock = TimeSpan.FromHours(24);

        public const int CodeAttempts = 3;
        public const int MaxCodes = 4;
        public static readonly TimeSpan CodeBlock = TimeSpan.FromHours(24);
        public static readonly TimeSpan CodeWindow = TimeSpan.FromHours(24);

        private class LoginState
        {
            public int Failures;
            public bool HadFirstLock;
            public DateTimeOffset? LockedUntil;
            public DateTimeOffset LastSeen;
        }

        private class CodeState
        {
            public int CodesSent;
            public int WrongAttempts;
            public DateTimeOffset WindowStart;
            public DateTimeOffset? BlockedUntil;
        }

        private readonly ConcurrentDictionary<string, LoginState> _logins = new();
        private readonly ConcurrentDictionary<string, CodeState> _codes = new();

        // Hesap kilitliyse kalan kilit süresini, değilse null döner
        public TimeSpan? LoginLockRemaining(string key, DateTimeOffset now)
        {
            if (!_logins.TryGetValue(Normalize(key), out var state)) return null;
            lock (state)
            {
                return state.LockedUntil > now ? state.LockedUntil - now : null;
            }
        }

        // Yanlış şifreyi sayar, sınır dolduysa hesabı önce 15 dakika sonra 24 saat kilitler
        public LoginFailure RegisterLoginFailure(string key, DateTimeOffset now)
        {
            CleanUp(now);
            var state = _logins.GetOrAdd(Normalize(key), _ => new LoginState());
            lock (state)
            {
                var notLocked = state.LockedUntil == null || state.LockedUntil <= now;
                var secondLockEnded = state.LockedUntil != null && state.HadFirstLock && state.Failures >= LoginAttemptsAfterLock;
                if (notLocked && (secondLockEnded || now - state.LastSeen > SecondLoginLock))
                {
                    state.Failures = 0;
                    state.HadFirstLock = false;
                }
                state.LockedUntil = state.LockedUntil > now ? state.LockedUntil : null;
                state.LastSeen = now;
                state.Failures++;

                var limit = state.HadFirstLock ? LoginAttemptsAfterLock : LoginAttempts;
                if (state.Failures < limit) return new LoginFailure(limit - state.Failures, null);

                var lockFor = state.HadFirstLock ? SecondLoginLock : FirstLoginLock;
                state.LockedUntil = now + lockFor;
                if (!state.HadFirstLock)
                {
                    state.HadFirstLock = true;
                    state.Failures = 0;
                }
                return new LoginFailure(0, lockFor);
            }
        }

        // Başarılı girişte hesabın sayacını sıfırlar
        public void ResetLogin(string key) => _logins.TryRemove(Normalize(key), out _);

        // Bu akış için yeni kod gönderilemiyorsa kullanıcıya gösterilecek mesajı, gönderilebiliyorsa null döner
        public string? CodeSendBlockedMessage(CodeFlow flow, string key, DateTimeOffset now)
        {
            if (!_codes.TryGetValue(CodeKey(flow, key), out var state)) return null;
            lock (state)
            {
                ResetExpiredWindow(state, now);
                if (state.BlockedUntil > now) return BlockedMessage(state.BlockedUntil.Value - now);
                if (state.CodesSent >= MaxCodes) return BlockedMessage(state.WindowStart + CodeWindow - now);
                return null;
            }
        }

        // Kod gönderildiğinde sayar ve yeni kod için yanlış deneme hakkını yeniler
        public void RegisterCodeSent(CodeFlow flow, string key, DateTimeOffset now)
        {
            CleanUp(now);
            var state = _codes.GetOrAdd(CodeKey(flow, key), _ => new CodeState { WindowStart = now });
            lock (state)
            {
                ResetExpiredWindow(state, now);
                if (state.CodesSent == 0) state.WindowStart = now;
                state.CodesSent++;
                state.WrongAttempts = 0;
            }
        }

        // Kod denenebiliyorsa null, akış kapalıysa ya da kodun hakkı bittiyse mesajı döner
        public string? CodeVerifyBlockedMessage(CodeFlow flow, string key, DateTimeOffset now)
        {
            if (!_codes.TryGetValue(CodeKey(flow, key), out var state)) return null;
            lock (state)
            {
                if (state.BlockedUntil > now) return BlockedMessage(state.BlockedUntil.Value - now);
                if (state.WrongAttempts >= CodeAttempts) return CodeUsedUpMessage;
                return null;
            }
        }

        // Yanlış kodu sayar, son kodun hakları da bittiyse akışı 24 saat kapatır
        public CodeFailure RegisterWrongCode(CodeFlow flow, string key, DateTimeOffset now)
        {
            var state = _codes.GetOrAdd(CodeKey(flow, key), _ => new CodeState { WindowStart = now, CodesSent = 1 });
            lock (state)
            {
                state.WrongAttempts++;
                var remaining = Math.Max(0, CodeAttempts - state.WrongAttempts);
                var blocked = remaining == 0 && state.CodesSent >= MaxCodes;
                if (blocked) state.BlockedUntil = now + CodeBlock;
                return new CodeFailure(remaining, blocked);
            }
        }

        // Başarılı doğrulamada akışın sayacını sıfırlar
        public void ResetCode(CodeFlow flow, string key) => _codes.TryRemove(CodeKey(flow, key), out _);

        public const string CodeUsedUpMessage = "Kod 3 kez yanlış girildi, lütfen yeni kod isteyin.";

        // Kalan süreyi saat veya dakika olarak yazan engel mesajını oluşturur
        public static string BlockedMessage(TimeSpan remaining) =>
            $"Çok fazla yanlış deneme yaptınız, {FormatDuration(remaining)} sonra tekrar deneyin.";

        // Süreyi kullanıcının okuyacağı şekilde saat veya dakika olarak yazar
        public static string FormatDuration(TimeSpan duration)
        {
            if (duration.TotalMinutes > 60) return $"{(int)Math.Ceiling(duration.TotalHours)} saat";
            return $"{Math.Max(1, (int)Math.Ceiling(duration.TotalMinutes))} dakika";
        }

        // 24 saatlik pencere dolduysa ve engel yoksa kod sayacını sıfırlar
        private static void ResetExpiredWindow(CodeState state, DateTimeOffset now)
        {
            if (state.BlockedUntil > now) return;
            if (state.BlockedUntil != null || now - state.WindowStart >= CodeWindow)
            {
                state.CodesSent = 0;
                state.WrongAttempts = 0;
                state.BlockedUntil = null;
                state.WindowStart = now;
            }
        }

        // Sözlük büyüdüğünde artık işe yaramayan eski kayıtları siler
        private void CleanUp(DateTimeOffset now)
        {
            if (_logins.Count > 1000)
            {
                foreach (var entry in _logins.Where(e => e.Value.LockedUntil == null || e.Value.LockedUntil <= now).Where(e => now - e.Value.LastSeen > SecondLoginLock).ToList())
                    _logins.TryRemove(entry.Key, out _);
            }
            if (_codes.Count > 1000)
            {
                foreach (var entry in _codes.Where(e => (e.Value.BlockedUntil == null || e.Value.BlockedUntil <= now) && now - e.Value.WindowStart > CodeWindow).ToList())
                    _codes.TryRemove(entry.Key, out _);
            }
        }

        private static string CodeKey(CodeFlow flow, string key) => $"{flow}:{Normalize(key)}";

        // Anahtarı büyük küçük harf ve boşluktan bağımsız hale getirir
        private static string Normalize(string key) => (key ?? "").Trim().ToLowerInvariant();
    }
}
