namespace QrBackend.Models
{
    public class User
    {
        public int Id { get; set; }

        public string Username { get; set; } = string.Empty;

        public string Password { get; set; } = string.Empty;

        public string Email { get; set; } = string.Empty;

        // --- 🆕 EMAIL DOĞRULAMA ALANLARI ---

        // Kullanıcı mailini onayladı mı?
        public bool IsEmailConfirmed { get; set; } = false;

        // Mailine gönderilen 6 haneli doğrulama kodu
        public string? EmailConfirmationCode { get; set; }

        // --- 🆕 ABONELİK ALANLARI ---

        // Abonelik durumu: "None", "Trialing", "Active"
        public string SubscriptionStatus { get; set; } = "None";

        // Deneme süresinin biteceği tarih
        public DateTime? TrialEndDate { get; set; }

        // Ücretli aboneliğin biteceği tarih
        public DateTime? SubscriptionEndDate { get; set; }
        
        // Kayıt tarihi
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}