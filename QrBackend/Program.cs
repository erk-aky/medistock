using Asp.Versioning;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc;
using QrBackend.Middleware;
using QrBackend.Services; // Senin orijinal namespace'in
using QrBackend.Models;   // Senin orijinal namespace'in

var builder = WebApplication.CreateBuilder(args);

// --- SERVİS KAYITLARI ---
builder.Services.AddControllers().ConfigureApiBehaviorOptions(options =>
{
    options.SuppressMapClientErrors = true;
    options.InvalidModelStateResponseFactory = context =>
    {
        var detail = string.Join(" | ", context.ModelState
            .Where(e => e.Value?.Errors.Count > 0)
            .SelectMany(e => e.Value!.Errors.Select(err => $"{e.Key}: {err.ErrorMessage}")));
        var isDevelopment = context.HttpContext.RequestServices.GetRequiredService<IHostEnvironment>().IsDevelopment();
        return new BadRequestObjectResult(ApiResponses.Error(ApiResponses.InvalidRequestMessage, detail, isDevelopment));
    };
});
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.ReportApiVersions = true;
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
}).AddMvc();
builder.Logging.AddFilter("Microsoft.AspNetCore.Diagnostics.ExceptionHandlerMiddleware", LogLevel.None);
builder.Services.AddExceptionHandler<ApiExceptionHandler>();
builder.Services.AddProblemDetails();
builder.Services.AddScoped<EmailService>();
// YENİ: ItsService Kaydı eklendi
builder.Services.AddSingleton<IItsService>(provider =>
{
    var configuredPath = builder.Configuration["Its:CodesFilePath"];
    var filePath = string.IsNullOrWhiteSpace(configuredPath)
        ? Path.Combine(AppContext.BaseDirectory, "Data", "its_codes.json")
        : configuredPath;
    return new ItsService(filePath, provider.GetRequiredService<ILogger<ItsService>>());
});

builder.Services.AddDataProtection().SetApplicationName("QrBackend");
builder.Services.AddSingleton<RegistrationTicketService>();
builder.Services.AddSingleton<EmailCooldown>();

builder.Services.AddScoped<AuthService>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var connString = config.GetConnectionString("Default") ?? "";
    var emailService = provider.GetRequiredService<EmailService>();
    var ticketService = provider.GetRequiredService<RegistrationTicketService>();
    var emailCooldown = provider.GetRequiredService<EmailCooldown>();
    return new AuthService(connString, emailService, ticketService, emailCooldown);
});

builder.Services.AddScoped<DrugRepository>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    return new DrugRepository(config.GetConnectionString("Default") ?? "");
});
builder.Services.AddScoped<QrLookupService>();

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

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages(StatusCodeResponseWriter.WriteAsync);

// --- ENDPOINTLER ---
app.MapGet("/", () => Results.Ok(new { success = true, message = "Backend JSON Modunda Calisiyor" }));

app.MapControllers();
app.Urls.Add("http://0.0.0.0:5289");
app.Run();

public partial class Program { }
