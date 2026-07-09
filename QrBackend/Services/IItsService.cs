using QrBackend.Models;

namespace QrBackend.Services
{
    public interface IItsService
    {
        Task<ItsCodeResponse> ResolveItsCodeAsync(string code);
    }
}