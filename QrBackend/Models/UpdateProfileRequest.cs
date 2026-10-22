namespace QrBackend.Models
{
    public class UpdateProfileRequest
    {
        public string NewUsername { get; set; } = string.Empty;
        public string NewEmail { get; set; } = string.Empty;
    }
}
