using Microsoft.AspNetCore.Mvc;
using QrBackend.Services;

namespace QrBackend.Controllers
{
    public class AdminController : ApiControllerBase
    {
        private readonly TitckSyncService _syncService;
        private readonly IHostEnvironment _environment;

        public AdminController(TitckSyncService syncService, IHostEnvironment environment)
        {
            _syncService = syncService;
            _environment = environment;
        }

        // Haftalık TİTCK senkronunu beklemeden elle tetikler, sadece geliştirme ortamında açıktır
        [HttpPost("titck-sync/run")]
        public async Task<IActionResult> RunTitckSync()
        {
            if (!_environment.IsDevelopment()) return NotFound();

            var result = await _syncService.RunOnceAsync(CancellationToken.None);
            return Ok(result);
        }
    }
}
