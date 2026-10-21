using Microsoft.AspNetCore.Diagnostics;
using Npgsql;

namespace QrBackend.Middleware
{
    public class ApiExceptionHandler : IExceptionHandler
    {
        private readonly ILogger<ApiExceptionHandler> _logger;
        private readonly IHostEnvironment _environment;

        public ApiExceptionHandler(ILogger<ApiExceptionHandler> logger, IHostEnvironment environment)
        {
            _logger = logger;
            _environment = environment;
        }

        // Yakalanmayan hatayı loga yazar, kullanıcıya anlaşılır mesaj döner, geliştirmede teknik detayı da ekliyor
        public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken cancellationToken)
        {
            _logger.LogError(exception, "İşlenmeyen hata: {Method} {Path}", context.Request.Method, context.Request.Path);

            var isDatabaseUnreachable = exception is NpgsqlException && exception is not PostgresException;
            context.Response.StatusCode = isDatabaseUnreachable
                ? StatusCodes.Status503ServiceUnavailable
                : StatusCodes.Status500InternalServerError;

            var message = isDatabaseUnreachable
                ? "Sunucu şu an veritabanına ulaşamıyor, lütfen daha sonra tekrar deneyin."
                : "Beklenmeyen bir hata oluştu.";

            object body = _environment.IsDevelopment()
                ? new { success = false, message, detail = DescribeException(exception) }
                : new { success = false, message };

            await context.Response.WriteAsJsonAsync(body, cancellationToken);
            return true;
        }

        // Hatanın türünü ve mesajını iç hatasıyla birlikte tek satırda özetler
        private static string DescribeException(Exception exception)
        {
            var detail = $"{exception.GetType().Name}: {exception.Message}";
            if (exception.InnerException != null)
                detail += $" | {exception.InnerException.GetType().Name}: {exception.InnerException.Message}";
            return detail;
        }
    }
}
