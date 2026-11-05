using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;

namespace QrBackend.Services
{
    public enum TicketStatus { Valid, Invalid, Expired }

    public interface ITicketData
    {
        DateTimeOffset ExpiresAt { get; }
    }

    public class TicketProtector<T> where T : class, ITicketData
    {
        private readonly IDataProtector _protector;

        public TicketProtector(IDataProtectionProvider provider, string purpose)
        {
            _protector = provider.CreateProtector(purpose);
        }

        // Bilgileri şifreli ve imzalı bir bilete çevirir
        public string Protect(T data) => _protector.Protect(JsonSerializer.Serialize(data));

        // Bileti çözer, değiştirilmiş veya süresi dolmuşsa durumunu bildirir
        public TicketStatus Read(string? ticket, DateTimeOffset now, out T? data)
        {
            data = null;
            if (string.IsNullOrEmpty(ticket)) return TicketStatus.Invalid;

            try
            {
                data = JsonSerializer.Deserialize<T>(_protector.Unprotect(ticket));
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
