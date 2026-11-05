using ClosedXML.Excel;

namespace QrBackend.Services
{
    public record TitckDrugRow(string Barkod, string UrunAdi);

    public class TitckExcelParser
    {
        private const int FirstDataRow = 3; // satır 1 = başlık, satır 2 = header
        private const int BarkodColumn = 2;  // B
        private const int UrunAdiColumn = 3; // C

        public List<TitckDrugRow> Parse(byte[] xlsxBytes)
        {
            using var stream = new MemoryStream(xlsxBytes);
            using var workbook = new XLWorkbook(stream);
            var sheet = workbook.Worksheet(1);

            var lastRow = sheet.LastRowUsed()?.RowNumber() ?? 0;
            var rows = new List<TitckDrugRow>();

            for (var rowNum = FirstDataRow; rowNum <= lastRow; rowNum++)
            {
                var barkod = sheet.Cell(rowNum, BarkodColumn).GetString().Trim();
                var urunAdi = sheet.Cell(rowNum, UrunAdiColumn).GetString().Trim();

                if (string.IsNullOrEmpty(barkod))
                    continue;

                rows.Add(new TitckDrugRow(barkod, urunAdi));
            }

            return rows;
        }
    }
}
