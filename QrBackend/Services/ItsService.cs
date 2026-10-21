using System.Text.Json;
using QrBackend.Models;

namespace QrBackend.Services
{
    public class ItsService : IItsService
    {
        private readonly string _filePath;
        private readonly ILogger<ItsService> _logger;
        private readonly object _lock = new();
        private Dictionary<string, string>? _codes;

        public ItsService(string filePath, ILogger<ItsService> logger)
        {
            _filePath = filePath;
            _logger = logger;
        }

        // ITS sonuç kodunun açıklamasını sözlükten bulup döner
        public Task<ItsCodeResponse> ResolveItsCodeAsync(string code)
        {
            var codes = GetCodes();
            if (codes == null)
            {
                return Task.FromResult(new ItsCodeResponse
                {
                    Code = code,
                    Message = "ITS hata açıklamaları şu an yüklenemedi, lütfen daha sonra tekrar deneyin.",
                    Success = false
                });
            }

            if (codes.TryGetValue(code, out var message))
                return Task.FromResult(new ItsCodeResponse { Code = code, Message = message, Success = true });

            return Task.FromResult(new ItsCodeResponse { Code = code, Message = $"Tanımlanamayan Kod: {code}", Success = false });
        }

        // Sözlüğü ilk istekte dosyadan okuyup bellekte tutar, okunamazsa loga yazıp null döner
        private Dictionary<string, string>? GetCodes()
        {
            if (_codes != null) return _codes;

            lock (_lock)
            {
                if (_codes != null) return _codes;

                try
                {
                    var json = File.ReadAllText(_filePath);
                    _codes = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
                    _logger.LogInformation("ITS hata sözlüğü yüklendi: {Count} kod, {Path}", _codes?.Count ?? 0, _filePath);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "ITS hata sözlüğü okunamadı: {Path}", _filePath);
                }

                return _codes;
            }
        }
    }
}
