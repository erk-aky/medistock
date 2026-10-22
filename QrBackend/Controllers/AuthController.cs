using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using QrBackend.Middleware;
using QrBackend.Models;
using QrBackend.Services;

namespace QrBackend.Controllers
{
    public class AuthController : ApiControllerBase
    {
        private readonly AuthService _authService;
        private readonly TokenService _tokenService;

        public AuthController(AuthService authService, TokenService tokenService)
        {
            _authService = authService;
            _tokenService = tokenService;
        }

        [AllowAnonymous]
        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginRequest request)
        {
            var (status, user) = await _authService.LoginAsync(request.UsernameOrEmail, request.Password);

            if (status == LoginStatus.EmailNotConfirmed)
                return StatusCode(403, new { success = false, message = "Lütfen e-posta adresinizi onaylayın." });

            if (status != LoginStatus.Success || user == null)
                return Unauthorized(new { success = false, message = "Kullanıcı adı veya şifre hatalı" });

            var tokens = await _tokenService.IssueAsync(user.Id, DateTimeOffset.UtcNow);

            return Ok(new {
                success = true,
                accessToken = tokens.AccessToken,
                refreshToken = tokens.RefreshToken,
                id = user.Id,
                username = user.Username,
                email = user.Email,
                subscriptionStatus = user.SubscriptionStatus,
                trialEndDate = user.TrialEndDate,
                subscriptionEndDate = user.SubscriptionEndDate
            });
        }

        // Yenileme token'ı geçerliyse yeni bir token çifti verir
        [AllowAnonymous]
        [HttpPost("refresh")]
        public async Task<IActionResult> Refresh([FromBody] RefreshTokenRequest request)
        {
            var (status, tokens) = await _tokenService.RefreshAsync(request.RefreshToken, DateTimeOffset.UtcNow);
            if (status != RefreshStatus.Success || tokens == null)
                return Unauthorized(ApiResponses.Error(ApiResponses.SessionExpiredMessage));

            return Ok(new { success = true, accessToken = tokens.AccessToken, refreshToken = tokens.RefreshToken });
        }

        // Çıkış yapılınca telefondaki yenileme token'ını iptal eder
        [AllowAnonymous]
        [HttpPost("logout")]
        public async Task<IActionResult> Logout([FromBody] RefreshTokenRequest request)
        {
            await _tokenService.RevokeAsync(request.RefreshToken, DateTimeOffset.UtcNow);
            return Ok(new { success = true, message = "Çıkış yapıldı." });
        }

        [AllowAnonymous]
        [HttpPost("verify-email")]
        public async Task<IActionResult> VerifyEmail([FromBody] VerifyEmailRequest request)
        {
            var result = await _authService.VerifyEmailAsync(request.Ticket, request.Code);

            if (result.Success)
            {
                return Ok(new { success = true, message = result.Message });
            }

            return BadRequest(new { success = false, message = result.Message });
        }

        // Token sahibinin profil bilgilerini döner
        [HttpGet("me")]
        public async Task<IActionResult> GetProfile()
        {
            var user = await _authService.GetUserByIdAsync(CurrentUserId);

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

            return NotFound(new { success = false, message = "Kullanıcı bulunamadı" });
        }

        [HttpPut("update-profile")]
        public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest request)
        {
            var result = await _authService.UpdateUserProfile(CurrentUserId, request);
            if (!result.Success)
                return BadRequest(new { success = false, message = result.Message });

            return Ok(new { success = true, message = result.Message });
        }

        // Yeni e-posta adresine onay kodu gönderir
        [HttpPost("change-email/request")]
        public async Task<IActionResult> RequestEmailChange([FromBody] ChangeEmailRequest request)
        {
            var result = await _authService.RequestEmailChangeAsync(CurrentUserId, request.NewEmail);
            if (!result.Success)
                return BadRequest(new { success = false, message = result.Message });

            return Ok(new { success = true, message = result.Message, ticket = result.Ticket });
        }

        // Kod doğruysa e-posta adresini değiştirir
        [HttpPost("change-email/confirm")]
        public async Task<IActionResult> ConfirmEmailChange([FromBody] VerifyEmailRequest request)
        {
            var result = await _authService.ConfirmEmailChangeAsync(CurrentUserId, request.Ticket, request.Code);
            if (!result.Success)
                return BadRequest(new { success = false, message = result.Message });

            return Ok(new { success = true, message = result.Message });
        }

        [AllowAnonymous]
        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegisterRequest request)
        {
            var result = await _authService.RegisterAsync(request);

            if (result.Success)
            {
                return Ok(new { success = true, message = result.Message, ticket = result.Ticket });
            }

            return BadRequest(new { success = false, message = result.Message });
        }

        [AllowAnonymous]
        [HttpPost("forgot-password")]
        public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
        {
            var result = await _authService.GenerateForgotPasswordCodeAsync(request.Email);

            if (result.Success)
            {
                return Ok(new { success = true, message = result.Message });
            }

            return BadRequest(new { success = false, message = result.Message });
        }

        [AllowAnonymous]
        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
        {
            var result = await _authService.ResetPasswordWithCodeAsync(request.Email, request.Code, request.NewPassword);

            if (result.Success)
            {
                return Ok(new { success = true, message = result.Message });
            }

            return BadRequest(new { success = false, message = result.Message });
        }
    }

    public class RefreshTokenRequest
    {
        public string RefreshToken { get; set; } = string.Empty;
    }

    public class ChangeEmailRequest
    {
        public string NewEmail { get; set; } = string.Empty;
    }

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