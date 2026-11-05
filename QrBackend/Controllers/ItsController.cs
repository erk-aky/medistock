using Microsoft.AspNetCore.Mvc;
using QrBackend.Middleware;
using QrBackend.Models;
using QrBackend.Services;

namespace QrBackend.Controllers
{
    public class ItsController : ApiControllerBase
    {
        private readonly IItsService _itsService;

        public ItsController(IItsService itsService)
        {
            _itsService = itsService;
        }

        // ITS sonuç kodunun okunabilir açıklamasını döner
        [HttpPost("resolve-code")]
        public async Task<IActionResult> ResolveCode([FromBody] ItsCodeRequest request)
        {
            if (string.IsNullOrEmpty(request.Code))
                return BadRequest(ApiResponses.Error("Kod boş olamaz."));

            var result = await _itsService.ResolveItsCodeAsync(request.Code);
            return Ok(result);
        }
    }
}
