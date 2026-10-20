using Microsoft.AspNetCore.Mvc;
using QrBackend.Models;
using QrBackend.Services;

namespace QrBackend.Controllers
{
    [ApiController]
    [Route("api/auth")]
    public class AuthController : ControllerBase
    {
        private readonly AuthService _authService;

        public AuthController(AuthService authService)
        {
            _authService = authService;
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginRequest request)
        {
            try
            {
                var user = await _authService.LoginAsync(request.UsernameOrEmail, request.Password);

                if (user != null)
                {
                    return Ok(new { 
                        success = true, 
                        id = user.Id,
                        username = user.Username,
                        email = user.Email,
                        subscriptionStatus = user.SubscriptionStatus,
                        trialEndDate = user.TrialEndDate,
                        subscriptionEndDate = user.SubscriptionEndDate
                    });
                }

                return Unauthorized(new { success = false, message = "Kullanıcı adı veya şifre hatalı" });
            }
            catch (Exception ex)
            {
                // AuthService içindeki "Lütfen e-posta adresinizi onaylayın" hatasını yakalayıp döner
                return BadRequest(new { success = false, message = ex.Message });
            }
        }

        // ✅ YENİ: E-POSTA DOĞRULAMA ENDPOINT'İ
        [HttpPost("verify-email")]
        public async Task<IActionResult> VerifyEmail([FromBody] VerifyEmailRequest request)
        {
            try
            {
                var result = await _authService.VerifyEmailAsync(request.Ticket, request.Code);
                
                if (result.Success)
                {
                    return Ok(new { success = true, message = result.Message });
                }

                return BadRequest(new { success = false, message = result.Message });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Verify Email Error: {ex.Message}");
                return StatusCode(500, new { success = false, message = "Doğrulama sırasında hata oluştu" });
            }
        }

        [HttpGet("profile/{username}")]
        public async Task<IActionResult> GetProfile(string username)
        {
            try
            {
                var user = await _authService.GetUserByUsernameAsync(username);

                if (user != null)
                {
                    return Ok(new { 
                        success = true, 
                        username = user.Username,
                        email = user.Email,
                        subscriptionStatus = user.SubscriptionStatus,
                        trialEndDate = user.TrialEndDate,
                        subscriptionEndDate = user.SubscriptionEndDate
                    });
                }

                return NotFound(new { success = false, message = "Kullanıcı bulunamadı" });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Profile Error: {ex.Message}");
                return StatusCode(500, new { success = false, message = "Profil bilgileri alınırken hata oluştu" });
            }
        }

        [HttpPut("update-profile")]
        public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest request)
        {
            var result = await _authService.UpdateUserProfile(request);
            if (!result.Success)
                return BadRequest(new { success = false, message = result.Message });

            return Ok(new { success = true, message = result.Message });
        }

        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegisterRequest request)
        {
            try
            {
                var result = await _authService.RegisterAsync(request);

                if (result.Success)
                {
                    return Ok(new { success = true, message = result.Message, ticket = result.Ticket });
                }

                return BadRequest(new { success = false, message = result.Message });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Register Error: {ex.Message}");
                return StatusCode(500, new { success = false, message = "Kayıt sırasında bir hata oluştu" });
            }
        }

        [HttpPost("forgot-password")]
        public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
        {
            try
            {
                var result = await _authService.GenerateForgotPasswordCodeAsync(request.Email);
                
                if (result.Success)
                {
                    return Ok(new { success = true, message = result.Message });
                }

                return BadRequest(new { success = false, message = result.Message });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Forgot Password Error: {ex.Message}");
                return StatusCode(500, new { success = false, message = "İşlem sırasında bir hata oluştu" });
            }
        }

        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
        {
            try
            {
                var result = await _authService.ResetPasswordWithCodeAsync(request.Email, request.Code, request.NewPassword);
                
                if (result.Success)
                {
                    return Ok(new { success = true, message = result.Message });
                }

                return BadRequest(new { success = false, message = result.Message });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Reset Password Error: {ex.Message}");
                return StatusCode(500, new { success = false, message = "Şifre sıfırlama sırasında bir hata oluştu" });
            }
        }
    }

    // ✅ YENİ: Doğrulama isteği için model
    public class VerifyEmailRequest
    {
        public string Ticket { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
    }

    public class ForgotPasswordRequest
    {
        public string Email { get; set; } = string.Empty;
    }

    public class ResetPasswordRequest
    {
        public string Email { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
        public string NewPassword { get; set; } = string.Empty;
    }
}