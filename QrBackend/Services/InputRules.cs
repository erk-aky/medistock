using System.Text.RegularExpressions;

namespace QrBackend.Services
{
    public static class InputRules
    {
        public const int PasswordMinLength = 6;
        public const int UsernameMinLength = 3;
        public const int UsernameMaxLength = 50;
        public const int EmailMaxLength = 254;

        private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);
        private static readonly Regex UsernameAllowed = new(@"^[\p{L}\p{Nd}._-]+$", RegexOptions.Compiled);
        private static readonly Regex EmailPattern = new(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled);

        // Şifre kurala uymuyorsa hata mesajını, uyuyorsa null döner
        public static string? ValidatePassword(string? password)
        {
            if (string.IsNullOrEmpty(password) || password.Length < PasswordMinLength)
                return $"Şifre en az {PasswordMinLength} karakter olmalıdır.";
            return null;
        }

        // Kullanıcı adının baş ve sonundaki boşlukları siler, aradaki boşlukları alt çizgiye çevirir
        public static string NormalizeUsername(string? username)
        {
            return Whitespace.Replace((username ?? "").Trim(), "_");
        }

        // Temizlenmiş kullanıcı adı kurala uymuyorsa hata mesajını, uyuyorsa null döner
        public static string? ValidateUsername(string username)
        {
            if (username.Length < UsernameMinLength || username.Length > UsernameMaxLength)
                return $"Kullanıcı adı {UsernameMinLength} ile {UsernameMaxLength} karakter arasında olmalıdır.";
            if (!UsernameAllowed.IsMatch(username))
                return "Kullanıcı adı yalnızca harf, rakam, nokta, alt çizgi ve tire içerebilir.";
            return null;
        }

        // E-postanın baş ve sonundaki boşlukları siler ve küçük harfe çevirir
        public static string NormalizeEmail(string? email)
        {
            return (email ?? "").Trim().ToLowerInvariant();
        }

        // Temizlenmiş e-postanın biçimi geçersizse hata mesajını, geçerliyse null döner
        public static string? ValidateEmail(string email)
        {
            if (email.Length == 0 || email.Length > EmailMaxLength || !EmailPattern.IsMatch(email))
                return "Geçerli bir e-posta adresi giriniz.";
            return null;
        }
    }
}
