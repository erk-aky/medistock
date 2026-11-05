using System.Text.RegularExpressions;
using Asp.Versioning;
using Microsoft.AspNetCore.Diagnostics;

namespace QrBackend.Middleware
{
    public static class StatusCodeResponseWriter
    {
        public const string UnsupportedVersionMessage = "Bu API sürümü desteklenmiyor, lütfen uygulamayı güncelleyin.";

        private static readonly Regex VersionInPath = new(@"^/api/v(?<version>[^/]+)/", RegexOptions.Compiled | RegexOptions.IgnoreCase);

        // Gövdesiz dönen hata cevaplarını ortak biçimde yazar, desteklenmeyen sürümü ayrıca belirtir
        public static async Task WriteAsync(StatusCodeContext statusContext)
        {
            var httpContext = statusContext.HttpContext;
            var response = httpContext.Response;

            var message = response.StatusCode == StatusCodes.Status404NotFound && IsUnsupportedApiVersion(httpContext)
                ? UnsupportedVersionMessage
                : ApiResponses.MessageForStatus(response.StatusCode);

            await response.WriteAsJsonAsync(ApiResponses.Error(message));
        }

        // Adresteki API sürümü uygulamadaki hiçbir controller tarafından desteklenmiyorsa true döner
        private static bool IsUnsupportedApiVersion(HttpContext httpContext)
        {
            var match = VersionInPath.Match(httpContext.Request.Path.Value ?? "");
            if (!match.Success || !ApiVersionParser.Default.TryParse(match.Groups["version"].Value, out var requested) || requested == null)
                return false;

            var endpoints = httpContext.RequestServices.GetRequiredService<EndpointDataSource>().Endpoints;
            var supported = endpoints
                .Select(e => e.Metadata.GetMetadata<ApiVersionMetadata>())
                .Where(m => m != null)
                .SelectMany(m => m!.Map(ApiVersionMapping.Explicit | ApiVersionMapping.Implicit).SupportedApiVersions);

            return !supported.Contains(requested);
        }
    }
}
