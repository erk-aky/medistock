using Microsoft.AspNetCore.DataProtection;

namespace QrBackend.Services
{
    public record EmailChangeTicketData(int UserId, string OldEmail, string NewEmail, string Code, DateTimeOffset ExpiresAt) : ITicketData;

    public class EmailChangeTicketService
    {
        public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(15);
        private readonly TicketProtector<EmailChangeTicketData> _tickets;

        public EmailChangeTicketService(IDataProtectionProvider provider)
        {
            _tickets = new TicketProtector<EmailChangeTicketData>(provider, "QrBackend.EmailChangeTicket.v1");
        }

        // Kullanıcının eski ve yeni e-posta adresini ve onay kodunu şifreli bilete çevirir
        public string Create(int userId, string oldEmail, string newEmail, string code, DateTimeOffset now)
        {
            return _tickets.Protect(new EmailChangeTicketData(userId, oldEmail, newEmail, code, now.Add(Lifetime)));
        }

        // Bileti çözer, değiştirilmiş veya süresi dolmuşsa durumunu bildirir
        public TicketStatus Read(string? ticket, DateTimeOffset now, out EmailChangeTicketData? data)
        {
            return _tickets.Read(ticket, now, out data);
        }
    }
}
