using System.Text;
using Asp.Versioning;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
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
builder.Services.AddSingleton<EmailChangeTicketService>();
builder.Services.AddSingleton<AttemptLimiter>();
builder.Services.AddSingleton<EmailCooldown>();

// --- OTURUM / TOKEN ---
builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection("Jwt"))
    .Validate(o => Encoding.UTF8.GetByteCount(o.SigningKey) >= 32, "Jwt:SigningKey ayarı eksik veya 32 karakterden kısa. appsettings.json içine uzun ve rastgele bir anahtar yazın.")
    .ValidateOnStart();

builder.Services.AddScoped<IRefreshTokenStore>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    return new RefreshTokenRepository(config.GetConnectionString("Default") ?? "");
});
builder.Services.AddScoped<TokenService>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<JwtOptions>>((options, jwt) =>
    {
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = jwt.Value.Issuer,
            ValidAudience = jwt.Value.Audience,
            IssuerSigningKey = TokenService.CreateSigningKey(jwt.Value),
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddScoped<AuthService>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var connString = config.GetConnectionString("Default") ?? "";
    var emailService = provider.GetRequiredService<EmailService>();
    var ticketService = provider.GetRequiredService<RegistrationTicketService>();
    var emailCooldown = provider.GetRequiredService<EmailCooldown>();
    var tokenService = provider.GetRequiredService<TokenService>();
    var emailChangeTickets = provider.GetRequiredService<EmailChangeTicketService>();
    var attemptLimiter = provider.GetRequiredService<AttemptLimiter>();
    return new AuthService(connString, emailService, ticketService, emailCooldown, tokenService, emailChangeTickets, attemptLimiter);
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
app.UseAuthentication();
app.UseAuthorization();

// --- ENDPOINTLER ---
app.MapGet("/", () => Results.Ok(new { success = true, message = "Backend JSON Modunda Calisiyor" }));

app.MapControllers();
app.Urls.Add("http://0.0.0.0:5289");
app.Run();

public partial class Program { }
