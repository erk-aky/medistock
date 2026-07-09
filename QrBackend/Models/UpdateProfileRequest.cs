namespace QrBackend.Models
{
    public class UpdateProfileRequest
    {
        public string NewUsername { get; set; }
        public string NewEmail { get; set; }
        // Mevcut kullanıcıyı ID üzerinden bulacağız (JWT'den veya parametreden)
        public int UserId { get; set; } 
    }
}