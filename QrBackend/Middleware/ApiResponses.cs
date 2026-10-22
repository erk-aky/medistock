namespace QrBackend.Middleware
{
    public static class ApiResponses
    {
        public const string InvalidRequestMessage = "Geçersiz istek biçimi.";
        public const string SessionExpiredMessage = "Oturumunuzun süresi doldu, lütfen tekrar giriş yapın.";

        // Hata cevabını ortak biçimde oluşturur, istenirse teknik detayı da ekler
        public static object Error(string message, string? detail = null, bool includeDetail = false)
        {
            if (includeDetail && !string.IsNullOrEmpty(detail))
                return new { success = false, message, detail };
            return new { success = false, message };
        }

        // Gövdesiz dönen hata kodları için kullanıcıya gösterilecek mesajı seçer
        public static string MessageForStatus(int statusCode) => statusCode switch
        {
            StatusCodes.Status400BadRequest => InvalidRequestMessage,
            StatusCodes.Status401Unauthorized => SessionExpiredMessage,
            StatusCodes.Status404NotFound => "İstenen adres bulunamadı.",
            StatusCodes.Status405MethodNotAllowed => "Bu adres bu istek türünü desteklemiyor.",
            StatusCodes.Status413PayloadTooLarge => "Gönderilen dosya çok büyük.",
            StatusCodes.Status415UnsupportedMediaType => InvalidRequestMessage,
            _ => "İstek işlenemedi."
        };
    }
}
