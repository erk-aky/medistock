using Microsoft.AspNetCore.Mvc;

namespace QrBackend.Controllers
{
    [ApiController]
    [Route("api/v{version:apiVersion}/[controller]")]
    public abstract class ApiControllerBase : ControllerBase
    {
    }
}
