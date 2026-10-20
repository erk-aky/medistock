using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;

namespace QrBackend.Services
{
    public record RegistrationTicketData(string Username, string Email, string PasswordHash, string Code, DateTimeOffset ExpiresAt);

    public enum TicketStatus { Valid, Invalid, Expired }

    public class RegistrationTicketService
    {
        public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(15);
        private readonly IDataProtector _protector;

        public RegistrationTicketService(IDataProtectionProvider provider)
        {
            _protector = provider.CreateProtector("QrBackend.RegistrationTicket.v1");
        }

        // Tahmin edilemeyen 6 haneli onay kodu üretir
        public static string GenerateCode()
        {
            return RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
        }

        // Kayıt bilgilerini şifreli ve imzalı bir bilete çevirir
        public string Create(string username, string email, string passwordHash, string code, DateTimeOffset now)
        {
            var data = new RegistrationTicketData(username, email, passwordHash, code, now.Add(Lifetime));
            return _protector.Protect(JsonSerializer.Serialize(data));
        }

        // Bileti çözer, değiştirilmiş veya süresi dolmuşsa durumunu bildirir
        public TicketStatus Read(string? ticket, DateTimeOffset now, out RegistrationTicketData? data)
        {
            data = null;
            if (string.IsNullOrEmpty(ticket)) return TicketStatus.Invalid;

            try
            {
                data = JsonSerializer.Deserialize<RegistrationTicketData>(_protector.Unprotect(ticket));
            }
            catch (Exception)
            {
                return TicketStatus.Invalid;
            }

            if (data == null) return TicketStatus.Invalid;
            if (data.ExpiresAt <= now) return TicketStatus.Expired;
            return TicketStatus.Valid;
        }
    }
}
