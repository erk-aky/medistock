using System.Collections.Concurrent;

namespace QrBackend.Services
{
    public class EmailCooldown
    {
        public static readonly TimeSpan Period = TimeSpan.FromSeconds(60);
        private readonly ConcurrentDictionary<string, DateTimeOffset> _lastSent = new();

        // Bu e-postaya şimdi mail gönderilebiliyorsa hakkı alır, değilse kalan saniyeyi döner
        public bool TryAcquire(string email, DateTimeOffset now, out int remainingSeconds)
        {
            var key = Normalize(email);
            remainingSeconds = 0;

            if (_lastSent.Count > 1000)
            {
                foreach (var entry in _lastSent.Where(e => now - e.Value >= Period).ToList())
                    _lastSent.TryRemove(entry.Key, out _);
            }

            while (true)
            {
                if (_lastSent.TryGetValue(key, out var last))
                {
                    var elapsed = now - last;
                    if (elapsed < Period)
                    {
                        remainingSeconds = (int)Math.Ceiling((Period - elapsed).TotalSeconds);
                        return false;
                    }
                    if (_lastSent.TryUpdate(key, now, last)) return true;
                }
                else if (_lastSent.TryAdd(key, now))
                {
                    return true;
                }
            }
        }

        // Mail gönderilemediğinde hakkı geri verir ki kullanıcı hemen tekrar deneyebilsin
        public void Release(string email)
        {
            _lastSent.TryRemove(Normalize(email), out _);
        }

        // E-postayı büyük küçük harf ve boşluktan bağımsız anahtara çevirir
        private static string Normalize(string email)
        {
            return (email ?? "").Trim().ToLowerInvariant();
        }
    }
}
