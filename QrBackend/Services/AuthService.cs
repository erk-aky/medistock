using Npgsql;
using QrBackend.Models;
using BCrypt.Net;

namespace QrBackend.Services
{
    public enum LoginStatus { Success, InvalidCredentials, EmailNotConfirmed, JustLocked, Locked }

    public record LoginResult(LoginStatus Status, User? User, int RemainingAttempts = 0, TimeSpan? LockedFor = null);

    public record CodeResult(bool Success, string Message, int? RemainingAttempts = null, bool TooManyAttempts = false);

    public class AuthService
    {
        private readonly string _connectionString;
        private readonly EmailService _emailService;
        private readonly RegistrationTicketService _ticketService;
        private readonly EmailCooldown _emailCooldown;
        private readonly TokenService _tokenService;
        private readonly EmailChangeTicketService _emailChangeTickets;
        private readonly AttemptLimiter _attemptLimiter;

        public AuthService(string connectionString, EmailService emailService, RegistrationTicketService ticketService, EmailCooldown emailCooldown, TokenService tokenService, EmailChangeTicketService emailChangeTickets, AttemptLimiter attemptLimiter)
        {
            _connectionString = connectionString;
            _emailService = emailService;
            _ticketService = ticketService;
            _emailCooldown = emailCooldown;
            _tokenService = tokenService;
            _emailChangeTickets = emailChangeTickets;
            _attemptLimiter = attemptLimiter;
        }

        // Token'dan gelen id ile kullanıcıyı bulur, yoksa null döner
        public async Task<User?> GetUserByIdAsync(int userId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "SELECT id, username, password, email, subscription_status, trial_end_date, subscription_end_date, is_email_confirmed FROM app_user WHERE id = @id LIMIT 1;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@id", userId);

            await using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;

            return new User
            {
                Id = reader.GetInt32(0),
                Username = reader.GetString(1),
                Password = reader.GetString(2),
                Email = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                SubscriptionStatus = reader.IsDBNull(4) ? "None" : reader.GetString(4),
                TrialEndDate = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                SubscriptionEndDate = reader.IsDBNull(6) ? null : reader.GetDateTime(6),
                IsEmailConfirmed = reader.GetBoolean(7)
            };
        }

        // Kullanıcı adı veya e-posta ile girişi kontrol eder, yanlış denemeleri sayıp gerekirse hesabı geçici kilitler
        public async Task<LoginResult> LoginAsync(string usernameOrEmail, string password)
        {
            var input = InputRules.NormalizeUsername(usernameOrEmail);
            var now = DateTimeOffset.UtcNow;

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "SELECT id, username, password, email, subscription_status, trial_end_date, subscription_end_date, is_email_confirmed FROM app_user WHERE LOWER(username) = LOWER(@value) OR LOWER(email) = LOWER(@value) LIMIT 1;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@value", input);

            User? user = null;
            await using (var reader = await cmd.ExecuteReaderAsync())
            {
                if (await reader.ReadAsync())
                {
                    user = new User
                    {
                        Id = reader.GetInt32(0),
                        Username = reader.GetString(1),
                        Password = reader.GetString(2),
                        Email = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                        SubscriptionStatus = reader.IsDBNull(4) ? "None" : reader.GetString(4),
                        TrialEndDate = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                        SubscriptionEndDate = reader.IsDBNull(6) ? null : reader.GetDateTime(6),
                        IsEmailConfirmed = reader.GetBoolean(7)
                    };
                }
            }

            var limiterKey = user != null ? $"user:{user.Id}" : $"input:{input}";

            var lockRemaining = _attemptLimiter.LoginLockRemaining(limiterKey, now);
            if (lockRemaining != null) return new LoginResult(LoginStatus.Locked, null, LockedFor: lockRemaining);

            if (user == null || !BCrypt.Net.BCrypt.Verify(password, user.Password))
            {
                var failure = _attemptLimiter.RegisterLoginFailure(limiterKey, now);
                return failure.LockedFor != null
                    ? new LoginResult(LoginStatus.JustLocked, null, LockedFor: failure.LockedFor)
                    : new LoginResult(LoginStatus.InvalidCredentials, null, RemainingAttempts: failure.RemainingAttempts);
            }

            _attemptLimiter.ResetLogin(limiterKey);
            if (!user.IsEmailConfirmed) return new LoginResult(LoginStatus.EmailNotConfirmed, null);

            return new LoginResult(LoginStatus.Success, user);
        }

        // Kullanıcıyı kaydetmeden onay kodunu mail atar ve onay için gereken bileti döner
        public async Task<(bool Success, string Message, string? Ticket)> RegisterAsync(RegisterRequest request)
        {
            var username = InputRules.NormalizeUsername(request.Username);
            var email = InputRules.NormalizeEmail(request.Email);

            var inputError = InputRules.ValidateUsername(username)
                ?? InputRules.ValidateEmail(email)
                ?? InputRules.ValidatePassword(request.Password);
            if (inputError != null) return (false, inputError, null);

            await using (var conn = new NpgsqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                var takenMessage = await CheckUsernameAndEmailTakenAsync(conn, username, email);
                if (takenMessage != null) return (false, takenMessage, null);
            }

            var sendBlocked = _attemptLimiter.CodeSendBlockedMessage(CodeFlow.Register, email, DateTimeOffset.UtcNow);
            if (sendBlocked != null) return (false, sendBlocked, null);

            if (!_emailCooldown.TryAcquire(email, DateTimeOffset.UtcNow, out var remaining))
                return (false, $"Yeni kod için lütfen {remaining} saniye bekleyin.", null);

            string code = RegistrationTicketService.GenerateCode();
            try
            {
                await _emailService.SendConfirmationEmailAsync(email, code);
                _attemptLimiter.RegisterCodeSent(CodeFlow.Register, email, DateTimeOffset.UtcNow);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Onay Maili Hatası: {ex.Message}");
                _emailCooldown.Release(email);
                return (false, "Onay kodu gönderilemedi, lütfen e-posta adresinizi kontrol edip tekrar deneyin.", null);
            }

            string passwordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);
            string ticket = _ticketService.Create(username, email, passwordHash, code, DateTimeOffset.UtcNow);

            return (true, "Onay kodu e-postanıza gönderildi.", ticket);
        }

        // Bilet ve kod doğruysa kullanıcıyı ancak bu anda onaylı olarak kaydeder
        public async Task<CodeResult> VerifyEmailAsync(string ticket, string code)
        {
            var now = DateTimeOffset.UtcNow;
            var status = _ticketService.Read(ticket, now, out var data);
            if (status == TicketStatus.Expired)
                return new CodeResult(false, "Kodun süresi doldu, lütfen yeni kod isteyin.");
            if (status == TicketStatus.Invalid || data == null)
                return new CodeResult(false, "Geçersiz istek, lütfen kayıt işlemini yeniden başlatın.");

            var blocked = CodeVerifyBlocked(CodeFlow.Register, data.Email, now);
            if (blocked != null) return blocked;
            if (data.Code != code)
                return WrongCode(CodeFlow.Register, data.Email, now, "Doğrulama kodu hatalı.");

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            var takenMessage = await CheckUsernameAndEmailTakenAsync(conn, data.Username, data.Email);
            if (takenMessage != null) return new CodeResult(false, takenMessage);

            const string insertSql = @"INSERT INTO app_user (username, password, email, subscription_status, trial_end_date, created_at, email_confirmation_code, is_email_confirmed)
                                     VALUES (@username, @password, @email, @subStatus, @trialEnd, @createdAt, NULL, true)";

            await using var insertCmd = new NpgsqlCommand(insertSql, conn);
            insertCmd.Parameters.AddWithValue("@username", data.Username);
            insertCmd.Parameters.AddWithValue("@password", data.PasswordHash);
            insertCmd.Parameters.AddWithValue("@email", data.Email);
            insertCmd.Parameters.AddWithValue("@subStatus", "Trialing");
            insertCmd.Parameters.AddWithValue("@trialEnd", DateTime.UtcNow.AddMinutes(5));
            insertCmd.Parameters.AddWithValue("@createdAt", DateTime.UtcNow);

            try
            {
                await insertCmd.ExecuteNonQueryAsync();
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                return new CodeResult(false, "Bu kullanıcı adı veya e-posta az önce başkası tarafından alındı.");
            }

            _attemptLimiter.ResetCode(CodeFlow.Register, data.Email);
            return new CodeResult(true, "E-posta başarıyla doğrulandı.");
        }

        // Kullanıcı adı veya e-posta kullanımdaysa uygun mesajı, boştaysa null döner
        private static async Task<string?> CheckUsernameAndEmailTakenAsync(NpgsqlConnection conn, string username, string email)
        {
            const string sql = @"
                SELECT
                    COUNT(*) FILTER (WHERE LOWER(username) = LOWER(@username)) AS user_exists,
                    COUNT(*) FILTER (WHERE LOWER(email) = LOWER(@email)) AS email_exists
                FROM app_user";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@username", username);
            cmd.Parameters.AddWithValue("@email", email);

            await using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            bool isUsernameTaken = reader.GetInt64(0) > 0;
            bool isEmailTaken = reader.GetInt64(1) > 0;

            if (isUsernameTaken && isEmailTaken)
                return "Hem kullanıcı adı hem de e-posta adresi zaten kullanımda.";
            if (isUsernameTaken)
                return "Bu kullanıcı adı zaten alınmış.";
            if (isEmailTaken)
                return "Bu e-posta adresi zaten kullanımda.";
            return null;
        }

        // Token sahibinin kullanıcı adını günceller, e-posta ayrı ve doğrulamalı akışla değişir
        public async Task<(bool Success, string Message)> UpdateUserProfile(int userId, UpdateProfileRequest request)
        {
            var username = InputRules.NormalizeUsername(request.NewUsername);

            var inputError = InputRules.ValidateUsername(username);
            if (inputError != null) return (false, inputError);

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string checkSql = "SELECT COUNT(*) FROM app_user WHERE LOWER(username) = LOWER(@username) AND id != @id";

            await using (var cmd = new NpgsqlCommand(checkSql, conn))
            {
                cmd.Parameters.AddWithValue("@username", username);
                cmd.Parameters.AddWithValue("@id", userId);

                if ((long)(await cmd.ExecuteScalarAsync() ?? 0L) > 0)
                    return (false, "Bu kullanıcı adı zaten alınmış.");
            }

            const string updateSql = "UPDATE app_user SET username = @username WHERE id = @id";

            await using (var updateCmd = new NpgsqlCommand(updateSql, conn))
            {
                updateCmd.Parameters.AddWithValue("@username", username);
                updateCmd.Parameters.AddWithValue("@id", userId);

                int affectedRows = await updateCmd.ExecuteNonQueryAsync();

                if (affectedRows == 0)
                    return (false, "Kullanıcı bulunamadı veya güncellenemedi.");
            }

            return (true, "Profil başarıyla güncellendi.");
        }

        // Yeni e-posta adresine onay kodu gönderir ve onay için gereken bileti döner
        public async Task<(bool Success, string Message, string? Ticket)> RequestEmailChangeAsync(int userId, string rawEmail)
        {
            var email = InputRules.NormalizeEmail(rawEmail);
            var emailError = InputRules.ValidateEmail(email);
            if (emailError != null) return (false, emailError, null);

            var user = await GetUserByIdAsync(userId);
            if (user == null) return (false, "Kullanıcı bulunamadı.", null);
            if (string.Equals(user.Email, email, StringComparison.OrdinalIgnoreCase))
                return (false, "Yeni e-posta adresi mevcut adresinizle aynı.", null);

            await using (var conn = new NpgsqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                if (await IsEmailTakenByOtherAsync(conn, email, userId))
                    return (false, "Bu e-posta adresi zaten kullanımda.", null);
            }

            var sendBlocked = _attemptLimiter.CodeSendBlockedMessage(CodeFlow.EmailChange, userId.ToString(), DateTimeOffset.UtcNow);
            if (sendBlocked != null) return (false, sendBlocked, null);

            if (!_emailCooldown.TryAcquire(email, DateTimeOffset.UtcNow, out var remaining))
                return (false, $"Yeni kod için lütfen {remaining} saniye bekleyin.", null);

            string code = RegistrationTicketService.GenerateCode();
            try
            {
                await _emailService.SendEmailChangeCodeAsync(email, code);
                _attemptLimiter.RegisterCodeSent(CodeFlow.EmailChange, userId.ToString(), DateTimeOffset.UtcNow);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"E-posta Değişikliği Mail Hatası: {ex.Message}");
                _emailCooldown.Release(email);
                return (false, "Onay kodu gönderilemedi, lütfen e-posta adresinizi kontrol edip tekrar deneyin.", null);
            }

            return (true, "Onay kodu yeni e-posta adresinize gönderildi.", _emailChangeTickets.Create(userId, user.Email, email, code, DateTimeOffset.UtcNow));
        }

        // Bilet ve kod doğruysa ve adres bilet alındığından beri değişmediyse e-postayı değiştirir, eski adrese bilgilendirme maili atar
        public async Task<CodeResult> ConfirmEmailChangeAsync(int userId, string ticket, string code)
        {
            var now = DateTimeOffset.UtcNow;
            var status = _emailChangeTickets.Read(ticket, now, out var data);
            if (status == TicketStatus.Expired)
                return new CodeResult(false, "Kodun süresi doldu, lütfen yeni kod isteyin.");
            if (status == TicketStatus.Invalid || data == null || data.UserId != userId)
                return new CodeResult(false, "Geçersiz istek, lütfen e-posta değişikliğini yeniden başlatın.");

            var blocked = CodeVerifyBlocked(CodeFlow.EmailChange, userId.ToString(), now);
            if (blocked != null) return blocked;
            if (data.Code != code)
                return WrongCode(CodeFlow.EmailChange, userId.ToString(), now, "Doğrulama kodu hatalı.");

            var user = await GetUserByIdAsync(userId);
            if (user == null) return new CodeResult(false, "Kullanıcı bulunamadı.");
            if (!string.Equals(user.Email, data.OldEmail, StringComparison.OrdinalIgnoreCase))
                return new CodeResult(false, "Geçersiz istek, lütfen e-posta değişikliğini yeniden başlatın.");

            await using (var conn = new NpgsqlConnection(_connectionString))
            {
                await conn.OpenAsync();

                const string updateSql = @"
                    UPDATE app_user SET email = @email
                    WHERE id = @id AND NOT EXISTS (SELECT 1 FROM app_user WHERE LOWER(email) = LOWER(@email) AND id != @id)";

                await using var cmd = new NpgsqlCommand(updateSql, conn);
                cmd.Parameters.AddWithValue("@email", data.NewEmail);
                cmd.Parameters.AddWithValue("@id", userId);

                try
                {
                    if (await cmd.ExecuteNonQueryAsync() == 0)
                        return new CodeResult(false, "Bu e-posta adresi zaten kullanımda.");
                }
                catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
                {
                    return new CodeResult(false, "Bu e-posta adresi zaten kullanımda.");
                }
            }

            _attemptLimiter.ResetCode(CodeFlow.EmailChange, userId.ToString());

            if (!string.IsNullOrWhiteSpace(user.Email))
            {
                try
                {
                    await _emailService.SendEmailChangedNoticeAsync(user.Email, data.NewEmail);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"E-posta Değişikliği Bilgilendirme Hatası: {ex.Message}");
                }
            }

            return new CodeResult(true, "E-posta adresiniz başarıyla değiştirildi.");
        }

        // Bu akışta kod denenemiyorsa kullanıcıya dönülecek sonucu, denenebiliyorsa null döner
        private CodeResult? CodeVerifyBlocked(CodeFlow flow, string key, DateTimeOffset now)
        {
            var message = _attemptLimiter.CodeVerifyBlockedMessage(flow, key, now);
            if (message == null) return null;
            return new CodeResult(false, message, 0, message != AttemptLimiter.CodeUsedUpMessage);
        }

        // Yanlış kodu sayar, kalan hakka göre kullanıcıya gösterilecek sonucu hazırlar
        private CodeResult WrongCode(CodeFlow flow, string key, DateTimeOffset now, string wrongMessage)
        {
            var failure = _attemptLimiter.RegisterWrongCode(flow, key, now);
            if (failure.Blocked) return new CodeResult(false, AttemptLimiter.BlockedMessage(AttemptLimiter.CodeBlock), 0, true);
            if (failure.RemainingAttempts == 0) return new CodeResult(false, AttemptLimiter.CodeUsedUpMessage, 0);
            return new CodeResult(false, $"{wrongMessage} Kalan hak: {failure.RemainingAttempts}", failure.RemainingAttempts);
        }

        // E-posta başka bir kullanıcıda kayıtlıysa true döner
        private static async Task<bool> IsEmailTakenByOtherAsync(NpgsqlConnection conn, string email, int userId)
        {
            const string sql = "SELECT COUNT(*) FROM app_user WHERE LOWER(email) = LOWER(@email) AND id != @id";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@email", email);
            cmd.Parameters.AddWithValue("@id", userId);
            return (long)(await cmd.ExecuteScalarAsync() ?? 0L) > 0;
        }

        public async Task<(bool Success, string Message)> GenerateForgotPasswordCodeAsync(string rawEmail)
        {
            var email = InputRules.NormalizeEmail(rawEmail);
            var emailError = InputRules.ValidateEmail(email);
            if (emailError != null) return (false, emailError);

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string userCheck = "SELECT id FROM app_user WHERE LOWER(email) = LOWER(@email)";
            await using var checkCmd = new NpgsqlCommand(userCheck, conn);
            checkCmd.Parameters.AddWithValue("@email", email);
            var userId = await checkCmd.ExecuteScalarAsync();

            if (userId == null) return (false, "Bu e-posta adresiyle kayıtlı bir kullanıcı bulunamadı.");

            var sendBlocked = _attemptLimiter.CodeSendBlockedMessage(CodeFlow.ResetPassword, email, DateTimeOffset.UtcNow);
            if (sendBlocked != null) return (false, sendBlocked);

            if (!_emailCooldown.TryAcquire(email, DateTimeOffset.UtcNow, out var remaining))
                return (false, $"Yeni kod için lütfen {remaining} saniye bekleyin.");

            string resetCode = RegistrationTicketService.GenerateCode();
            DateTime expiry = DateTime.Now.AddMinutes(15); 

            const string updateSql = "UPDATE app_user SET reset_token = @code, token_expiry = @expiry WHERE id = @id";
            await using var updateCmd = new NpgsqlCommand(updateSql, conn);
            updateCmd.Parameters.AddWithValue("@code", resetCode);
            updateCmd.Parameters.AddWithValue("@expiry", expiry);
            updateCmd.Parameters.AddWithValue("@id", userId);
            await updateCmd.ExecuteNonQueryAsync();

            try
            {
                await _emailService.SendResetEmailAsync(email, resetCode);
                _attemptLimiter.RegisterCodeSent(CodeFlow.ResetPassword, email, DateTimeOffset.UtcNow);
                return (true, "Şifre sıfırlama kodu e-posta adresinize gönderildi.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Email Hatası: {ex.Message}");
                _emailCooldown.Release(email);
                return (false, "E-posta gönderilirken bir hata oluştu.");
            }
        }

        // Kod doğruysa şifreyi değiştirir ve kullanıcının bütün oturumlarını kapatır
        public async Task<CodeResult> ResetPasswordWithCodeAsync(string rawEmail, string code, string newPassword)
        {
            var now = DateTimeOffset.UtcNow;
            var email = InputRules.NormalizeEmail(rawEmail);
            var passwordError = InputRules.ValidatePassword(newPassword);
            if (passwordError != null) return new CodeResult(false, passwordError);

            var blocked = CodeVerifyBlocked(CodeFlow.ResetPassword, email, now);
            if (blocked != null) return blocked;

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string verifySql = "SELECT id FROM app_user WHERE LOWER(email) = LOWER(@email) AND reset_token = @code AND token_expiry > @now";
            await using var verifyCmd = new NpgsqlCommand(verifySql, conn);
            verifyCmd.Parameters.AddWithValue("@email", email);
            verifyCmd.Parameters.AddWithValue("@code", code);
            verifyCmd.Parameters.AddWithValue("@now", DateTime.Now);

            var userId = await verifyCmd.ExecuteScalarAsync();
            if (userId == null) return WrongCode(CodeFlow.ResetPassword, email, now, "Kod hatalı veya süresi dolmuş.");

            string newPasswordHash = BCrypt.Net.BCrypt.HashPassword(newPassword);
            const string updateSql = "UPDATE app_user SET password = @password, reset_token = NULL, token_expiry = NULL WHERE id = @id";
            
            await using var updateCmd = new NpgsqlCommand(updateSql, conn);
            updateCmd.Parameters.AddWithValue("@password", newPasswordHash);
            updateCmd.Parameters.AddWithValue("@id", userId);
            await updateCmd.ExecuteNonQueryAsync();

            await _tokenService.RevokeAllAsync((int)userId, DateTimeOffset.UtcNow);
            _attemptLimiter.ResetCode(CodeFlow.ResetPassword, email);

            return new CodeResult(true, "Şifreniz başarıyla güncellendi.");
        }
    }
}