using MailKit.Net.Smtp;
using MimeKit;

namespace QrBackend.Services
{
    public class EmailService
    {
        private readonly IConfiguration _config;

        public EmailService(IConfiguration config)
        {
            _config = config;
        }

        // Mevcut Şifre Sıfırlama Metodu (Dokunulmadı)
        public async Task SendResetEmailAsync(string toEmail, string code)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress("MediStock Support", "uygulama_mailin@gmail.com"));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "Şifre Sıfırlama Kodu";

            email.Body = new TextPart(MimeKit.Text.TextFormat.Html)
            {
                Text = $@"<h3>Şifre Sıfırlama Kodunuz:</h3>
                          <h1 style='color:blue;'>{code}</h1>
                          <p>Bu kod 15 dakika geçerlidir.</p>"
            };

            using var smtp = new SmtpClient();
            await smtp.ConnectAsync("smtp.gmail.com", 587, MailKit.Security.SecureSocketOptions.StartTls);
            await smtp.AuthenticateAsync("thalasjewerly@gmail.com", "njcj tfuq bvux sfjw"); // Uygulama Şifreniz buraya
            await smtp.SendAsync(email);
            await smtp.DisconnectAsync(true);
        }

        // ✅ YENİ: Kayıt Onay Kodu Gönderme Metodu
        public async Task SendConfirmationEmailAsync(string toEmail, string code)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress("MediStock Support", "uygulama_mailin@gmail.com"));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "Hesap Onaylama Kodu";

            email.Body = new TextPart(MimeKit.Text.TextFormat.Html)
            {
                Text = $@"<h3>Hoş Geldiniz!</h3>
                          <p>Hesabınızı doğrulamak ve kullanmaya başlamak için onay kodunuz:</p>
                          <h1 style='color:green; letter-spacing: 5px;'>{code}</h1>
                          <p>Lütfen bu kodu uygulamadaki onay ekranına giriniz.</p>
                          <br>
                          <p>Eğer bu hesabı siz oluşturmadıysanız bu maili dikkate almayınız.</p>"
            };

            using var smtp = new SmtpClient();
            await smtp.ConnectAsync("smtp.gmail.com", 587, MailKit.Security.SecureSocketOptions.StartTls);
            await smtp.AuthenticateAsync("thalasjewerly@gmail.com", "njcj tfuq bvux sfjw"); // Uygulama Şifreniz buraya
            await smtp.SendAsync(email);
            await smtp.DisconnectAsync(true);
        }
    }
}