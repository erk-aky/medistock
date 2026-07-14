using System.Text.RegularExpressions;

namespace QrBackend.Services
{
    public class TitckExcelDownloader
    {
        private static readonly Regex XlsxHrefRegex = new(
            "href=\"(?<url>[^\"]+\\.xlsx)\"",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public async Task<string> ResolveLatestXlsxUrlAsync(HttpClient client, string listingPageUrl, CancellationToken ct)
        {
            var html = await client.GetStringAsync(listingPageUrl, ct);
            var match = XlsxHrefRegex.Match(html);
            if (!match.Success)
                throw new InvalidOperationException($"'{listingPageUrl}' sayfasında .xlsx uzantılı bir bağlantı bulunamadı.");

            var url = match.Groups["url"].Value;
            if (!Uri.TryCreate(url, UriKind.Absolute, out var absoluteUri))
            {
                var baseUri = new Uri(listingPageUrl);
                absoluteUri = new Uri(baseUri, url);
            }

            return absoluteUri.ToString();
        }

        public async Task<byte[]> DownloadExcelAsync(HttpClient client, string xlsxUrl, CancellationToken ct)
        {
            return await client.GetByteArrayAsync(xlsxUrl, ct);
        }
    }
}
