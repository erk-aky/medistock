namespace QrBackend.Services
{
    public record Gs1Data(string? Gtin, string? SerialNo, string? BatchNo, DateTime? ExpiryDate);

    public static class Gs1Parser
    {
        private const char Gs = (char)29;
        private static readonly string[] SymbologyPrefixes = { "]d2", "]Q3", "]C1" };
        private static readonly Dictionary<string, int> FixedLengths = new()
        {
            ["00"] = 20, ["01"] = 16, ["02"] = 16, ["03"] = 16, ["04"] = 18,
            ["11"] = 8, ["12"] = 8, ["13"] = 8, ["14"] = 8, ["15"] = 8, ["16"] = 8, ["17"] = 8, ["18"] = 8, ["19"] = 8,
            ["20"] = 4,
            ["31"] = 10, ["32"] = 10, ["33"] = 10, ["34"] = 10, ["35"] = 10, ["36"] = 10,
            ["41"] = 16,
        };

        // Karekod metnini GTIN, seri no, parti no ve SKT alanlarına ayırır
        public static Gs1Data Parse(string raw)
        {
            var s = Normalize(raw);
            string? gtin = null, serial = null, batch = null;
            DateTime? expiry = null;

            var pos = 0;
            while (pos < s.Length)
            {
                if (s[pos] == Gs)
                {
                    pos++;
                    continue;
                }
                if (pos + 2 > s.Length) break;

                var ai = s.Substring(pos, 2);
                var start = pos + 2;

                if (ai == "01")
                {
                    if (!IsDigits(s, start, 14)) break;
                    var full = s.Substring(start, 14);
                    gtin = full.StartsWith('0') ? full.Substring(1) : full;
                    pos = start + 14;
                }
                else if (ai == "17")
                {
                    if (!IsDigits(s, start, 6)) break;
                    expiry = ParseExpiry(s.Substring(start, 6));
                    pos = start + 6;
                }
                else if (ai == "21" || ai == "10")
                {
                    var end = FindVariableEnd(s, start);
                    var value = s.Substring(start, end - start);
                    if (ai == "21") serial = value;
                    else batch = value;
                    pos = end;
                }
                else if (FixedLengths.TryGetValue(ai, out var length))
                {
                    if (pos + length > s.Length) break;
                    pos += length;
                }
                else
                {
                    var nextGs = s.IndexOf(Gs, pos);
                    if (nextGs == -1) break;
                    pos = nextGs + 1;
                }
            }

            return new Gs1Data(gtin, serial, batch, expiry);
        }

        // YYAAGG formatındaki SKT'yi tarihe çevirir, gün 00 ise ayın son günü kabul edilir
        public static DateTime? ParseExpiry(string yymmdd)
        {
            if (!IsDigits(yymmdd, 0, 6)) return null;
            var year = 2000 + int.Parse(yymmdd.Substring(0, 2));
            var month = int.Parse(yymmdd.Substring(2, 2));
            var day = int.Parse(yymmdd.Substring(4, 2));
            if (month < 1 || month > 12) return null;

            var lastDay = DateTime.DaysInMonth(year, month);
            if (day == 0) return new DateTime(year, month, lastDay);
            if (day > lastDay) return null;
            return new DateTime(year, month, day);
        }

        // Okuyucunun eklediği önekleri temizler ve boşlukları GS ayırıcısına çevirir
        private static string Normalize(string raw)
        {
            var s = (raw ?? "").Trim();
            foreach (var prefix in SymbologyPrefixes)
            {
                if (s.StartsWith(prefix))
                {
                    s = s.Substring(prefix.Length);
                    break;
                }
            }
            return s.Replace(' ', Gs);
        }

        // Değişken uzunluklu alanın bittiği yeri bulur, GS yoksa ardından SKT ve yeni alan gelen 17 aranır
        private static int FindVariableEnd(string s, int start)
        {
            var nextGs = s.IndexOf(Gs, start);
            if (nextGs != -1) return nextGs;

            for (var i = start + 1; i + 10 <= s.Length; i++)
            {
                if (string.CompareOrdinal(s, i, "17", 0, 2) == 0 &&
                    ParseExpiry(s.Substring(i + 2, 6)) != null &&
                    (string.CompareOrdinal(s, i + 8, "10", 0, 2) == 0 || string.CompareOrdinal(s, i + 8, "21", 0, 2) == 0))
                {
                    return i;
                }
            }
            return s.Length;
        }

        // Verilen aralığın tamamen rakam olup olmadığını kontrol eder
        private static bool IsDigits(string s, int start, int length)
        {
            if (start + length > s.Length) return false;
            for (var i = start; i < start + length; i++)
            {
                if (s[i] < '0' || s[i] > '9') return false;
            }
            return true;
        }
    }
}
