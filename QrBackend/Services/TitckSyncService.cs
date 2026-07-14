using System.Diagnostics;
using Microsoft.Extensions.Options;
using QrBackend.Models;

namespace QrBackend.Services
{
    public record SyncRunResult(
        bool Success,
        string? FailedStep,
        string? ErrorMessage,
        int? RowCount,
        int? RowsAdded,
        int? RowsUpdated);

    public class TitckSyncService : BackgroundService
    {
        private readonly IServiceScopeFactory _scopeFactory;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly TitckSyncOptions _options;
        private readonly TitckExcelDownloader _downloader;
        private readonly TitckExcelParser _parser;
        private readonly ILogger<TitckSyncService> _logger;

        public TitckSyncService(
            IServiceScopeFactory scopeFactory,
            IHttpClientFactory httpClientFactory,
            IOptions<TitckSyncOptions> options,
            TitckExcelDownloader downloader,
            TitckExcelParser parser,
            ILogger<TitckSyncService> logger)
        {
            _scopeFactory = scopeFactory;
            _httpClientFactory = httpClientFactory;
            _options = options.Value;
            _downloader = downloader;
            _parser = parser;
            _logger = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var delay = GetDelayUntilNextRun(DateTimeOffset.Now, _options.DayOfWeek, _options.TimeOfDay);
                _logger.LogInformation("TİTCK senkron bir sonraki çalışmaya kadar bekliyor: {Delay}", delay);

                try
                {
                    await Task.Delay(delay, stoppingToken);
                }
                catch (TaskCanceledException)
                {
                    break;
                }

                if (stoppingToken.IsCancellationRequested) break;

                await RunOnceAsync(stoppingToken);
            }
        }

        public async Task<SyncRunResult> RunOnceAsync(CancellationToken ct)
        {
            var startedAt = DateTimeOffset.UtcNow;
            var sw = Stopwatch.StartNew();

            using var scope = _scopeFactory.CreateScope();
            var repository = scope.ServiceProvider.GetRequiredService<TitckSyncRepository>();
            var emailService = scope.ServiceProvider.GetRequiredService<EmailService>();

            string sourceUrl = "";
            int? rowCount = null;
            List<TitckDrugRow>? addedRows = null;
            int? rowsUpdated = null;
            string? failedStep = null;
            string? errorMessage = null;

            try
            {
                var httpClient = _httpClientFactory.CreateClient("titck");
                httpClient.Timeout = TimeSpan.FromSeconds(_options.HttpTimeoutSeconds);

                try
                {
                    sourceUrl = await _downloader.ResolveLatestXlsxUrlAsync(httpClient, _options.ListingPageUrl, ct);
                }
                catch (Exception ex)
                {
                    failedStep = "DownloadPage";
                    errorMessage = ex.Message;
                    throw;
                }

                byte[] excelBytes;
                try
                {
                    excelBytes = await _downloader.DownloadExcelAsync(httpClient, sourceUrl, ct);
                }
                catch (Exception ex)
                {
                    failedStep = "DownloadExcel";
                    errorMessage = ex.Message;
                    throw;
                }

                List<TitckDrugRow> rows;
                try
                {
                    rows = _parser.Parse(excelBytes);
                    rowCount = rows.Count;
                }
                catch (Exception ex)
                {
                    failedStep = "ParseExcel";
                    errorMessage = ex.Message;
                    throw;
                }

                try
                {
                    var lastSuccessCount = await repository.GetLastSuccessfulRowCountAsync(ct);
                    if (lastSuccessCount.HasValue && lastSuccessCount.Value > 0)
                    {
                        var dropPct = (lastSuccessCount.Value - rowCount.Value) / (double)lastSuccessCount.Value * 100;
                        if (dropPct > _options.AnomalyDropThresholdPercent)
                        {
                            throw new InvalidOperationException(
                                $"Satır sayısı %{dropPct:F1} düştü ({rowCount} vs son başarılı {lastSuccessCount}).");
                        }
                    }
                }
                catch (Exception ex)
                {
                    failedStep = "AnomalyCheck";
                    errorMessage = ex.Message;
                    throw;
                }

                try
                {
                    await repository.BackupQrcodesToCopyAsync(ct);
                }
                catch (Exception ex)
                {
                    failedStep = "BackupCopy";
                    errorMessage = ex.Message;
                    throw;
                }

                try
                {
                    (addedRows, rowsUpdated) = await repository.LoadAndDiffAsync(
                        rows, _options.UpdatePercentAnomalyThreshold, ct);
                }
                catch (InvalidOperationException ex)
                {
                    failedStep = "UpdateAnomalyCheck";
                    errorMessage = ex.Message;
                    throw;
                }
                catch (Exception ex)
                {
                    failedStep = "DiffTransaction";
                    errorMessage = ex.Message;
                    throw;
                }

                sw.Stop();

                await SafeInsertLogAsync(repository, new SyncLogEntry
                {
                    StartedAt = startedAt,
                    FinishedAt = DateTimeOffset.UtcNow,
                    Status = "success",
                    SourceUrl = sourceUrl,
                    RowCount = rowCount,
                    RowsAdded = addedRows!.Count,
                    RowsUpdated = rowsUpdated,
                    DurationMs = (int)sw.ElapsedMilliseconds
                }, ct);

                await SafeSendEmailAsync(async () =>
                    await emailService.SendTitckSyncSuccessEmailAsync(
                        _options.NotifyEmail, sourceUrl, rowCount!.Value, addedRows, rowsUpdated!.Value, sw.Elapsed));

                return new SyncRunResult(true, null, null, rowCount, addedRows.Count, rowsUpdated);
            }
            catch (Exception ex)
            {
                sw.Stop();
                failedStep ??= "Unknown";
                errorMessage ??= ex.Message;

                _logger.LogError(ex, "TİTCK senkron başarısız oldu. Adım: {Step}", failedStep);

                await SafeInsertLogAsync(repository, new SyncLogEntry
                {
                    StartedAt = startedAt,
                    FinishedAt = DateTimeOffset.UtcNow,
                    Status = "failed",
                    SourceUrl = sourceUrl,
                    RowCount = rowCount,
                    FailedStep = failedStep,
                    ErrorMessage = errorMessage,
                    DurationMs = (int)sw.ElapsedMilliseconds
                }, ct);

                await SafeSendEmailAsync(async () =>
                    await emailService.SendTitckSyncFailureEmailAsync(_options.NotifyEmail, sourceUrl, failedStep, errorMessage));

                return new SyncRunResult(false, failedStep, errorMessage, rowCount, null, null);
            }
        }

        private async Task SafeInsertLogAsync(TitckSyncRepository repository, SyncLogEntry entry, CancellationToken ct)
        {
            try
            {
                await repository.InsertSyncLogAsync(entry, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "sync_log kaydı yazılamadı.");
            }
        }

        private async Task SafeSendEmailAsync(Func<Task> send)
        {
            try
            {
                await send();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "TİTCK senkron bildirim e-postası gönderilemedi.");
            }
        }

        internal static TimeSpan GetDelayUntilNextRun(DateTimeOffset now, string dayOfWeekName, string timeOfDay)
        {
            var targetDay = Enum.Parse<DayOfWeek>(dayOfWeekName, ignoreCase: true);
            var timeParts = timeOfDay.Split(':');
            var targetHour = int.Parse(timeParts[0]);
            var targetMinute = int.Parse(timeParts[1]);

            var candidate = new DateTimeOffset(now.Year, now.Month, now.Day, targetHour, targetMinute, 0, now.Offset);

            var daysUntilTarget = ((int)targetDay - (int)candidate.DayOfWeek + 7) % 7;
            candidate = candidate.AddDays(daysUntilTarget);

            if (candidate <= now)
                candidate = candidate.AddDays(7);

            return candidate - now;
        }
    }
}
