using System.Diagnostics;
using System.Net.Sockets;
using System.Text;

namespace QrBackend.Services
{
    public class QrDetection
    {
        public string Value { get; set; } = "";
        public int X { get; set; } public int Y { get; set; }
        public int W { get; set; } public int H { get; set; }
    }

    public record QrLookupData(string? Gtin, string? SerialNo, string? BatchNo, string? ExpiryDate, string? ProductName);

    public record QrLookupItem(string Value, bool Found, QrLookupData Data, int X, int Y, int W, int H);

    public record QrLookupOutcome(bool DecoderUnavailable, List<QrLookupItem> Results);

    public class QrLookupService
    {
        private const string DecoderHost = "127.0.0.1";
        private const int DecoderPort = 8888;

        private readonly DrugRepository _drugRepository;

        public QrLookupService(DrugRepository drugRepository)
        {
            _drugRepository = drugRepository;
        }

        // Fotoğrafı C++ servisine okutur, karekodları ayrıştırır ve ilaç adlarını bulur
        public async Task<QrLookupOutcome> LookupAsync(byte[] imageBytes)
        {
            var totalSw = Stopwatch.StartNew();
            var stepSw = Stopwatch.StartNew();

            // 2. C++ Servis İletişimi
            string cPlusPlusOutput = "";
            try
            {
                using var client = new TcpClient(DecoderHost, DecoderPort);
                using var stream = client.GetStream();

                byte[] sizeHeader = BitConverter.GetBytes(imageBytes.Length);
                await stream.WriteAsync(sizeHeader, 0, sizeHeader.Length);
                await stream.WriteAsync(imageBytes, 0, imageBytes.Length);
                await stream.FlushAsync();

                byte[] buffer = new byte[65536];
                int bytesRead = await stream.ReadAsync(buffer, 0, buffer.Length);
                cPlusPlusOutput = Encoding.UTF8.GetString(buffer, 0, bytesRead);
                Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [3] C++ CEVAP ALINDI: {stepSw.ElapsedMilliseconds}ms");
                stepSw.Restart();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HATA] C++ Servis: {ex.Message}");
                return new QrLookupOutcome(true, new List<QrLookupItem>());
            }

            // 3. Ayrıştırma ve DB Sorgusu
            var detections = new List<QrDetection>();
            var rawLines = cPlusPlusOutput.Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var line in rawLines.Where(l => l.StartsWith("QR_DATA")))
            {
                try {
                    var parts = line.Split('|');
                    var val = parts[0].Split(':')[1].Trim();
                    var coords = parts[1].Split(':')[1].Trim().Split(',').Select(int.Parse).ToArray();
                    detections.Add(new QrDetection { Value = val, X = coords[0], Y = coords[1], W = coords[2], H = coords[3] });
                } catch { }
            }

            var finalResults = new List<QrLookupItem>();
            if (detections.Any())
            {
                foreach (var det in detections)
                {
                    var parsed = Gs1Parser.Parse(det.Value);
                    var gtin = parsed.Gtin;

                    // --- YENİ DB SORGUSU (Sadece GTIN ile) ---
                    string? productName = null;
                    bool foundInDb = false;

                    if (!string.IsNullOrEmpty(gtin))
                    {
                        try {
                            productName = await _drugRepository.FindProductNameAsync(gtin);
                            foundInDb = productName != null;
                        } catch (Exception ex) { Console.WriteLine($"[DB HATA]: {ex.Message}"); }
                    }

                    finalResults.Add(new QrLookupItem(
                        det.Value,
                        foundInDb,
                        new QrLookupData(gtin, parsed.SerialNo, parsed.BatchNo, parsed.ExpiryDate?.ToString("yyyy-MM-dd"), productName),
                        det.X, det.Y, det.W, det.H));
                }
                Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [4] DB KONTROL BİTTİ: {stepSw.ElapsedMilliseconds}ms");
            }

            totalSw.Stop();
            Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [5] TOPLAM SÜRE: {totalSw.ElapsedMilliseconds}ms\n---------------------------------");

            return new QrLookupOutcome(false, finalResults);
        }
    }
}
