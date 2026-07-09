namespace QrBackend.Models;

public class QrLookupResult
{
    // Flutter tarafı 'value' bekliyor (Okunan ham karekod metni)
    public string Value { get; set; } = string.Empty;

    // Flutter tarafı 'found' bekliyor
    public bool Found { get; set; }

    // Koordinat alanları (ML Kit'ten gelen çerçeve bilgileri)
    public int X { get; set; }
    public int Y { get; set; }
    public int W { get; set; }
    public int H { get; set; }

    // DB'den gelen ilaç detaylarını 'data' altında topluyoruz
    public QrData? Data { get; set; }
}

public class QrData
{
    public string Gtin { get; set; } = string.Empty;
    public string SerialNo { get; set; } = string.Empty;
    public string BatchNo { get; set; } = string.Empty;
    public DateTime? ExpiryDate { get; set; }
    
    // ✅ YENİ EKLENEN ALAN: Veritabanındaki 'urun_adi' buraya dolacak
    public string? ProductName { get; set; }

    // Miadı yakın kontrolü için yardımcı özellik
    public bool IsExpirySoon => ExpiryDate.HasValue && 
                                ExpiryDate.Value < DateTime.Now.AddMonths(3);
}