using System.Text.Json;
using QrBackend.Models;

namespace QrBackend.Services
{
    public class ItsService : IItsService
    {
        // Sabit dosya yolunu burada tanımlıyoruz
        private readonly string _filePath = @"C:\Users\Administrator\Desktop\QrSistem\its_codes.json";

        public async Task<ItsCodeResponse> ResolveItsCodeAsync(string code)
        {
            try
            {
                // Dosya var mı kontrol ediyoruz
                if (!File.Exists(_filePath))
                {
                    return new ItsCodeResponse 
                    { 
                        Code = code, 
                        Message = "Sistem Hatası: Hata sözlüğü dosyası belirtilen konumda bulunamadı.", 
                        Success = false 
                    };
                }

                // Dosyayı oku
                var jsonData = await File.ReadAllTextAsync(_filePath);
                var codes = JsonSerializer.Deserialize<Dictionary<string, string>>(jsonData);

                // Kodu sözlük içinde ara
                if (codes != null && codes.TryGetValue(code, out var message))
                {
                    return new ItsCodeResponse { Code = code, Message = message, Success = true };
                }

                // Kod bulunamazsa ham kodu ve uyarıyı dön
                return new ItsCodeResponse { Code = code, Message = $"Tanımlanamayan Kod: {code}", Success = false };
            }
            catch (Exception ex)
            {
                return new ItsCodeResponse { Code = code, Message = "Dosya okuma hatası: " + ex.Message, Success = false };
            }
        }
    }
}