using Microsoft.AspNetCore.Http;
using Npgsql;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text.RegularExpressions; // Regex için eklendi
using QrBackend.Services; // Senin orijinal namespace'in
using QrBackend.Models;   // Senin orijinal namespace'in

var builder = WebApplication.CreateBuilder(args);

// --- SERVİS KAYITLARI ---
builder.Services.AddControllers();
builder.Services.AddScoped<EmailService>();
// YENİ: ItsService Kaydı eklendi
builder.Services.AddScoped<IItsService, ItsService>(); 

builder.Services.AddScoped<AuthService>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var connString = config.GetConnectionString("Default") ?? "";
    var emailService = provider.GetRequiredService<EmailService>();
    return new AuthService(connString, emailService);
});

// --- TİTCK HAFTALIK SENKRON ---
builder.Services.Configure<TitckSyncOptions>(builder.Configuration.GetSection("TitckSync"));
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection("Smtp"));

builder.Services.AddHttpClient("titck");

builder.Services.AddSingleton<TitckExcelDownloader>();
builder.Services.AddSingleton<TitckExcelParser>();

builder.Services.AddScoped<TitckSyncRepository>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var connString = config.GetConnectionString("Default") ?? "";
    return new TitckSyncRepository(connString);
});

builder.Services.AddSingleton<TitckSyncService>();
builder.Services.AddHostedService(provider => provider.GetRequiredService<TitckSyncService>());

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod());
});

var app = builder.Build();
app.UseCors();

// --- ENDPOINTLER ---
app.MapGet("/", () => "Backend JSON Modunda Calisiyor");

// YENİ: İTS Hata Kodu Çözümleme Endpoint'i
app.MapPost("/api/its/resolve-code", async (ItsCodeRequest request, IItsService itsService) =>
{
    if (string.IsNullOrEmpty(request.Code)) 
        return Results.BadRequest(new { message = "Kod boş olamaz" });

    var result = await itsService.ResolveItsCodeAsync(request.Code);
    return Results.Ok(result);
});

app.MapPost("/api/qr/lookup", async (HttpRequest request, IConfiguration config) =>
{
    var totalSw = Stopwatch.StartNew();
    var stepSw = Stopwatch.StartNew();
    
    Console.WriteLine($"\n[{DateTime.Now:HH:mm:ss.fff}] >>> [1] İSTEK ALINDI");

    if (!request.HasFormContentType) return Results.BadRequest("Form-data bekleniyor");

    var form = await request.ReadFormAsync();
    var file = form.Files["image"];
    if (file == null || file.Length == 0) return Results.BadRequest("Image bulunamadi");

    // 1. Veri Okuma
    using var msInput = new MemoryStream();
    await file.CopyToAsync(msInput);
    byte[] imageBytes = msInput.ToArray();
    Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [2] RAM'E ALMA: {stepSw.ElapsedMilliseconds}ms");
    stepSw.Restart();

    // 2. C++ Servis İletişimi
    string cPlusPlusOutput = "";
    try 
    {
        using var client = new TcpClient("127.0.0.1", 8888);
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
        return Results.Problem("C++ QR Servisi yanıt vermiyor!");
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

    var finalResults = new List<object>();
    if (detections.Any())
    {
        var connStr = config.GetConnectionString("Default");

        foreach (var det in detections)
        {
            // --- FLUTTER'DAKİ AYNI PARÇALAMA MANTIĞI ---
            string v = det.Value.Replace(((char)29).ToString(), " ");
            var segments = v.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries).ToList();

            string? gtin = null, serial = null, batch = null;
            DateTime? expiry = null;

            foreach (var segment in segments)
            {
                if (segment.StartsWith("01") && segment.Length >= 16)
                {
                    string fullGtin = segment.Substring(2, 14);
                    gtin = fullGtin.StartsWith("0") ? fullGtin.Substring(1) : fullGtin;

                    if (segment.Length > 16)
                    {
                        ParseSegment(segment.Substring(16), ref serial, ref batch, ref expiry);
                    }
                }
                else
                {
                    ParseSegment(segment, ref serial, ref batch, ref expiry);
                }
            }

            // --- YENİ DB SORGUSU (Sadece GTIN ile) ---
            string? productName = null;
            bool foundInDb = false;

            if (!string.IsNullOrEmpty(gtin))
            {
                try {
                    await using var conn = new NpgsqlConnection(connStr);
                    await conn.OpenAsync();
                    // Yeni tablo: 'barkod' kolonunda ara, 'urun_adi' çek
                    string query = "SELECT urun_adi FROM qrcodes WHERE barkod = @gtin LIMIT 1";
                    await using var cmd = new NpgsqlCommand(query, conn);
                    cmd.Parameters.AddWithValue("gtin", gtin);

                    var result = await cmd.ExecuteScalarAsync();
                    if (result != null)
                    {
                        productName = result.ToString();
                        foundInDb = true;
                    }
                } catch (Exception ex) { Console.WriteLine($"[DB HATA]: {ex.Message}"); }
            }

            finalResults.Add(new {
                value = det.Value,
                found = foundInDb,
                data = new {
                    gtin = gtin,
                    serialNo = serial,
                    batchNo = batch,
                    expiryDate = expiry?.ToString("yyyy-MM-dd"),
                    productName = productName
                },
                x = det.X, y = det.Y, w = det.W, h = det.H 
            });
        }
        Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [4] DB KONTROL BİTTİ: {stepSw.ElapsedMilliseconds}ms");
    }

    totalSw.Stop();
    Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [5] TOPLAM SÜRE: {totalSw.ElapsedMilliseconds}ms\n---------------------------------");

    return Results.Ok(new { results = finalResults });
});

// Mobil uygulamanın offline SQLite'ının güncel olup olmadığını kontrol etmesi için.
app.MapGet("/api/qr/db-version", async (IConfiguration config) =>
{
    var connStr = config.GetConnectionString("Default");
    await using var conn = new NpgsqlConnection(connStr);
    await conn.OpenAsync();

    const string query = "SELECT id, started_at FROM sync_log WHERE status = 'success' ORDER BY started_at DESC LIMIT 1;";
    await using var cmd = new NpgsqlCommand(query, conn);
    await using var reader = await cmd.ExecuteReaderAsync();

    if (!await reader.ReadAsync())
        return Results.Ok(new { version = 0, updatedAt = (DateTimeOffset?)null });

    return Results.Ok(new { version = reader.GetInt64(0), updatedAt = reader.GetFieldValue<DateTimeOffset>(1) });
});

// Mobil uygulamanın offline SQLite'ını yeniden doldurmak için tüm ilaç listesini döner.
app.MapGet("/api/qr/db-export", async (IConfiguration config) =>
{
    var connStr = config.GetConnectionString("Default");
    await using var conn = new NpgsqlConnection(connStr);
    await conn.OpenAsync();

    const string query = "SELECT barkod, urun_adi FROM qrcodes ORDER BY barkod;";
    await using var cmd = new NpgsqlCommand(query, conn);
    await using var reader = await cmd.ExecuteReaderAsync();

    var rows = new List<object>();
    while (await reader.ReadAsync())
    {
        rows.Add(new { barkod = reader.GetString(0), urunAdi = reader.IsDBNull(1) ? "" : reader.GetString(1) });
    }

    return Results.Ok(rows);
});

// --- YARDIMCI FONKSİYONLAR ---

void ParseSegment(string s, ref string? serial, ref string? batch, ref DateTime? expiry)
{
    // Son Kullanma (17)
    if (s.Contains("17"))
    {
        int idx = s.IndexOf("17");
        if (s.Length >= idx + 8)
        {
            string datePart = s.Substring(idx + 2, 6);
            if (Regex.IsMatch(datePart, @"^\d{6}$"))
            {
                int yy = int.Parse(datePart.Substring(0, 2));
                int mm = int.Parse(datePart.Substring(2, 2));
                int dd = int.Parse(datePart.Substring(4, 2));
                if (mm >= 1 && mm <= 12)
                    expiry = new DateTime(2000 + yy, mm, dd == 0 ? 1 : dd);
            }
        }
    }
    // Seri No (21)
    if (s.Contains("21"))
    {
        int idx = s.IndexOf("21");
        string rest = s.Substring(idx + 2);
        serial = Regex.Split(rest, "17|10")[0];
    }
    // Parti No (10)
    if (s.Contains("10"))
    {
        int idx = s.IndexOf("10");
        string rest = s.Substring(idx + 2);
        batch = Regex.Split(rest, "17|21")[0];
    }
}

if (app.Environment.IsDevelopment())
{
    // Dev-only: haftalık TİTCK senkronunu bir hafta beklemeden manuel tetiklemek için
    app.MapPost("/api/admin/titck-sync/run", async (TitckSyncService syncService) =>
    {
        var result = await syncService.RunOnceAsync(CancellationToken.None);
        return Results.Ok(result);
    });
}

app.MapControllers();
app.Urls.Add("http://0.0.0.0:5289");
app.Run();

public class QrDetection {
    public string Value { get; set; } = "";
    public int X { get; set; } public int Y { get; set; }
    public int W { get; set; } public int H { get; set; }
}
public class LoginRequest {
    public string UsernameOrEmail { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}