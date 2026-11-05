using Microsoft.AspNetCore.Mvc;
using QrBackend.Middleware;
using QrBackend.Services;

namespace QrBackend.Controllers
{
    public class QrController : ApiControllerBase
    {
        private readonly DrugRepository _drugRepository;

        public QrController(DrugRepository drugRepository)
        {
            _drugRepository = drugRepository;
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
