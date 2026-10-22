using System.Security.Cryptography;
using Microsoft.AspNetCore.DataProtection;

namespace QrBackend.Services
{
    public record RegistrationTicketData(string Username, string Email, string PasswordHash, string Code, DateTimeOffset ExpiresAt) : ITicketData;

    public class RegistrationTicketService
    {
        public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(15);
        private readonly TicketProtector<RegistrationTicketData> _tickets;

        public RegistrationTicketService(IDataProtectionProvider provider)
        {
            _tickets = new TicketProtector<RegistrationTicketData>(provider, "QrBackend.RegistrationTicket.v1");
        }

        // Tahmin edilemeyen 6 haneli onay kodu üretir
        public static string GenerateCode()
        {
            return RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
        }

        // Kayıt bilgilerini şifreli ve imzalı bir bilete çevirir
        public string Create(string username, string email, string passwordHash, string code, DateTimeOffset now)
        {
            return _tickets.Protect(new RegistrationTicketData(username, email, passwordHash, code, now.Add(Lifetime)));
        }

        // Bileti çözer, değiştirilmiş veya süresi dolmuşsa durumunu bildirir
        public TicketStatus Read(string? ticket, DateTimeOffset now, out RegistrationTicketData? data)
        {
            return _tickets.Read(ticket, now, out data);
        }
    }
}
