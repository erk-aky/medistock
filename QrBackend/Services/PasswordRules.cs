namespace QrBackend.Services
{
    public static class PasswordRules
    {
        public const int MinLength = 6;

        // Şifre kurala uymuyorsa hata mesajını, uyuyorsa null döner
        public static string? Validate(string? password)
        {
            if (string.IsNullOrEmpty(password) || password.Length < MinLength)
                return $"Şifre en az {MinLength} karakter olmalıdır.";
            return null;
        }
    }
}
