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
            int statusCode;
            string message;

            if (exception is BadHttpRequestException badRequest)
            {
                _logger.LogWarning(exception, "Hatalı istek: {Method} {Path}", context.Request.Method, context.Request.Path);
                statusCode = badRequest.StatusCode;
                message = ApiResponses.MessageForStatus(statusCode);
            }
            else
            {
                _logger.LogError(exception, "İşlenmeyen hata: {Method} {Path}", context.Request.Method, context.Request.Path);

                var isDatabaseUnreachable = exception is NpgsqlException && exception is not PostgresException;
                statusCode = isDatabaseUnreachable
                    ? StatusCodes.Status503ServiceUnavailable
                    : StatusCodes.Status500InternalServerError;

                message = isDatabaseUnreachable
                    ? "Sunucu şu an veritabanına ulaşamıyor, lütfen daha sonra tekrar deneyin."
                    : "Beklenmeyen bir hata oluştu.";
            }

            context.Response.StatusCode = statusCode;
            var body = ApiResponses.Error(message, DescribeException(exception), _environment.IsDevelopment());
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
