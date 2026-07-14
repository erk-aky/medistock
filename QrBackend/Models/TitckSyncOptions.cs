namespace QrBackend.Models
{
    public class TitckSyncOptions
    {
        public string ListingPageUrl { get; set; } = "https://www.titck.gov.tr/dinamikmodul/85";
        public string DayOfWeek { get; set; } = "Monday";
        public string TimeOfDay { get; set; } = "03:00";
        public double AnomalyDropThresholdPercent { get; set; } = 20.0;
        public double UpdatePercentAnomalyThreshold { get; set; } = 30.0;
        public string NotifyEmail { get; set; } = "";
        public int HttpTimeoutSeconds { get; set; } = 120;
    }
}
