using Microsoft.AspNetCore.Mvc;
using QrBackend.Middleware;
using QrBackend.Services;

namespace QrBackend.Controllers
{
    public class QrController : ApiControllerBase
    {
        private readonly QrLookupService _lookupService;
        private readonly DrugRepository _drugRepository;

        public QrController(QrLookupService lookupService, DrugRepository drugRepository)
        {
            _lookupService = lookupService;
            _drugRepository = drugRepository;
        }

        // Fotoğraftaki karekodları okuyup ilaç bilgileriyle birlikte döner
        [HttpPost("lookup")]
        public async Task<IActionResult> Lookup()
        {
            var stepSw = System.Diagnostics.Stopwatch.StartNew();
            Console.WriteLine($"\n[{DateTime.Now:HH:mm:ss.fff}] >>> [1] İSTEK ALINDI");

            if (!Request.HasFormContentType) return BadRequest(ApiResponses.Error("Fotoğraf form verisi olarak gönderilmelidir."));

            var form = await Request.ReadFormAsync();
            var file = form.Files["image"];
            if (file == null || file.Length == 0) return BadRequest(ApiResponses.Error("Fotoğraf bulunamadı."));

            using var msInput = new MemoryStream();
            await file.CopyToAsync(msInput);
            byte[] imageBytes = msInput.ToArray();
            Console.WriteLine($"[{DateTime.Now:HH:mm:ss.fff}] [2] RAM'E ALMA: {stepSw.ElapsedMilliseconds}ms");

            var outcome = await _lookupService.LookupAsync(imageBytes);
            if (outcome.DecoderUnavailable)
                return StatusCode(StatusCodes.Status503ServiceUnavailable, ApiResponses.Error("Karekod okuma servisi şu an çalışmıyor, lütfen daha sonra tekrar deneyin."));

            return Ok(new { success = true, results = outcome.Results });
        }

        // Telefondaki offline veritabanının güncel olup olmadığını anlamak için son liste sürümünü döner
        [HttpGet("db-version")]
        public async Task<IActionResult> DbVersion()
        {
            var (version, updatedAt) = await _drugRepository.GetLatestVersionAsync();
            return Ok(new { success = true, version, updatedAt });
        }

        // Telefondaki offline veritabanını doldurmak için bütün ilaç listesini döner
        [HttpGet("db-export")]
        public async Task<IActionResult> DbExport()
        {
            var items = await _drugRepository.GetAllDrugsAsync();
            return Ok(new { success = true, items });
        }
    }
}
