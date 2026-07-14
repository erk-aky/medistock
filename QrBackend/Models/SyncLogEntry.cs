namespace QrBackend.Models
{
    public class SyncLogEntry
    {
        public DateTimeOffset StartedAt { get; set; }
        public DateTimeOffset? FinishedAt { get; set; }
        public string Status { get; set; } = "failed"; // "success" | "failed"
        public string SourceUrl { get; set; } = "";
        public int? RowCount { get; set; }
        public int? RowsAdded { get; set; }
        public int? RowsUpdated { get; set; }
        public string? FailedStep { get; set; }
        public string? ErrorMessage { get; set; }
        public int DurationMs { get; set; }
    }
}
