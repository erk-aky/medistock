using ClosedXML.Excel;
using MailKit.Net.Smtp;
using MimeKit;
using Microsoft.Extensions.Options;
using QrBackend.Models;

namespace QrBackend.Services
{
    public class EmailService
    {
        private readonly SmtpOptions _smtp;

        public EmailService(IOptions<SmtpOptions> smtpOptions)
        {
            _smtp = smtpOptions.Value;
        }

        // Mevcut Şifre Sıfırlama Metodu (Dokunulmadı)
        public async Task SendResetEmailAsync(string toEmail, string code)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromAddress));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "Şifre Sıfırlama Kodu";

            email.Body = new TextPart(MimeKit.Text.TextFormat.Html)
            {
                Text = $@"<h3>Şifre Sıfırlama Kodunuz:</h3>
                          <h1 style='color:blue;'>{code}</h1>
                          <p>Bu kod 15 dakika geçerlidir.</p>"
            };

            await SendAsync(email);
        }

        // ✅ YENİ: Kayıt Onay Kodu Gönderme Metodu
        public async Task SendConfirmationEmailAsync(string toEmail, string code)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromAddress));
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

            await SendAsync(email);
        }

        // E-posta değişikliği için onay kodunu yeni adrese gönderir
        public async Task SendEmailChangeCodeAsync(string toEmail, string code)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromAddress));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "E-posta Değişikliği Onay Kodu";

            email.Body = new TextPart(MimeKit.Text.TextFormat.Html)
            {
                Text = $@"<h3>E-posta adresinizi değiştirmek için onay kodunuz:</h3>
                          <h1 style='color:green; letter-spacing: 5px;'>{code}</h1>
                          <p>Bu kod 15 dakika geçerlidir.</p>
                          <br>
                          <p>Eğer bu değişikliği siz istemediyseniz bu maili dikkate almayınız.</p>"
            };

            await SendAsync(email);
        }

        // E-posta değiştirilince eski adrese bilgilendirme maili gönderir
        public async Task SendEmailChangedNoticeAsync(string toEmail, string newEmail)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromAddress));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "E-posta Adresiniz Değiştirildi";

            email.Body = new TextPart(MimeKit.Text.TextFormat.Html)
            {
                Text = $@"<h3>Hesabınızın e-posta adresi değiştirildi</h3>
                          <p>Hesabınız artık <b>{System.Net.WebUtility.HtmlEncode(newEmail)}</b> adresine bağlı.</p>
                          <p>Bu değişikliği siz yapmadıysanız lütfen bizimle iletişime geçin.</p>"
            };

            await SendAsync(email);
        }

        public async Task SendTitckSyncSuccessEmailAsync(string toEmail, string sourceUrl, int rowCount, List<TitckDrugRow> added, int updated, TimeSpan duration)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromAddress));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "İlaç Listesi Güncellemesi Tamamlandı";

            var hasChange = added.Count > 0 || updated > 0;
            var changeSummary = hasChange
                ? $"<p>Bu hafta <strong>{added.Count}</strong> yeni ilaç eklendi ve <strong>{updated}</strong> ilacın ismi güncellendi.</p>"
                : "<p>Bu hafta kaynak listede herhangi bir değişiklik yoktu, ilaç veritabanı zaten güncel.</p>";

            var attachmentNote = added.Count > 0
                ? "<p>Eklenen ilaçların listesi bu maile dosya olarak eklenmiştir.</p>"
                : "";

            var builder = new BodyBuilder
            {
                HtmlBody = $@"<h3>✅ Haftalık ilaç listesi güncellemesi başarıyla tamamlandı</h3>
                          <p>Kontrol edilen kaynak dosya: <a href='{sourceUrl}'>{GetFileNameFromUrl(sourceUrl)}</a></p>
                          {changeSummary}
                          {attachmentNote}
                          <p style='color:#666; font-size: 13px;'>
                            Kontrol edilen toplam ilaç sayısı: {rowCount}<br>
                            İşlem süresi: {duration.TotalSeconds:F0} saniye
                          </p>"
            };

            if (added.Count > 0)
            {
                builder.Attachments.Add(
                    "eklenen_ilaclar.xlsx",
                    BuildDrugListExcel(added),
                    ContentType.Parse("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"));
            }

            email.Body = builder.ToMessageBody();

            await SendAsync(email);
        }

        public async Task SendTitckSyncFailureEmailAsync(string toEmail, string sourceUrl, string failedStep, string errorMessage)
        {
            var email = new MimeMessage();
            email.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromAddress));
            email.To.Add(MailboxAddress.Parse(toEmail));
            email.Subject = "İlaç Listesi Güncellemesi Başarısız";

            var reason = DescribeFailedStep(failedStep);
            var sourceInfo = string.IsNullOrEmpty(sourceUrl)
                ? ""
                : $"<p>Kontrol edilmeye çalışılan kaynak dosya: <a href='{sourceUrl}'>{GetFileNameFromUrl(sourceUrl)}</a></p>";

            email.Body = new TextPart(MimeKit.Text.TextFormat.Html)
            {
                Text = $@"<h3 style='color:#c0392b;'>⚠️ Haftalık ilaç listesi güncellemesi başarısız oldu</h3>
                          <p>{reason}</p>
                          {sourceInfo}
                          <p><strong>Önemli:</strong> Herhangi bir değişiklik uygulanmadı, mevcut ilaç veritabanı olduğu gibi korundu. Herhangi bir işlem yapmanıza gerek yok, bir sonraki denemede sorun otomatik olarak yeniden kontrol edilecek.</p>
                          <p style='color:#666; font-size: 13px;'>Teknik detay: {errorMessage}</p>"
            };

            await SendAsync(email);
        }

        private static string GetFileNameFromUrl(string url)
        {
            if (string.IsNullOrEmpty(url)) return "bilinmiyor";
            return Uri.TryCreate(url, UriKind.Absolute, out var uri)
                ? System.IO.Path.GetFileName(uri.LocalPath)
                : url;
        }

        private static byte[] BuildDrugListExcel(List<TitckDrugRow> rows)
        {
            using var workbook = new XLWorkbook();
            var sheet = workbook.Worksheets.Add("Eklenen İlaçlar");

            sheet.Cell(1, 1).Value = "Barkod";
            sheet.Cell(1, 2).Value = "Ürün Adı";
            sheet.Row(1).Style.Font.Bold = true;

            for (var i = 0; i < rows.Count; i++)
            {
                sheet.Cell(i + 2, 1).Value = rows[i].Barkod;
                sheet.Cell(i + 2, 2).Value = rows[i].UrunAdi;
            }

            sheet.Columns().AdjustToContents();

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            return stream.ToArray();
        }

        private static string DescribeFailedStep(string failedStep) => failedStep switch
        {
            "DownloadPage" => "TİTCK'nin ilaç listesi sayfasına ulaşılamadı.",
            "DownloadExcel" => "TİTCK'nin ilaç listesi dosyası indirilemedi.",
            "ParseExcel" => "İndirilen dosya okunamadı, beklenen formatta değildi.",
            "AnomalyCheck" => "Kaynak listedeki ilaç sayısında beklenmedik bir düşüş tespit edildi, güvenlik amacıyla işlem durduruldu.",
            "UpdateAnomalyCheck" => "Beklenenden çok daha fazla ilaç isminde değişiklik tespit edildi, kaynak dosyanın hatalı olma ihtimaline karşı işlem durduruldu.",
            "BackupCopy" => "Güncellemeden önce alınması gereken yedek oluşturulamadı.",
            "DiffTransaction" => "Veritabanı güncellenirken bir hata oluştu.",
            _ => "Beklenmeyen bir hata oluştu."
        };

        private async Task SendAsync(MimeMessage email)
        {
            using var smtp = new SmtpClient();
            await smtp.ConnectAsync(_smtp.Host, _smtp.Port, MailKit.Security.SecureSocketOptions.StartTls);
            await smtp.AuthenticateAsync(_smtp.Username, _smtp.Password);
            await smtp.SendAsync(email);
            await smtp.DisconnectAsync(true);
        }
    }
}
