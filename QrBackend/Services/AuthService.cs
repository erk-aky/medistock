using Npgsql;
using QrBackend.Models;
using BCrypt.Net;

namespace QrBackend.Services
{
    public enum LoginStatus { Success, InvalidCredentials, EmailNotConfirmed }

    public class AuthService
    {
        private readonly string _connectionString;
        private readonly EmailService _emailService;
        private readonly RegistrationTicketService _ticketService;
        private readonly EmailCooldown _emailCooldown;

        public AuthService(string connectionString, EmailService emailService, RegistrationTicketService ticketService, EmailCooldown emailCooldown)
        {
            _connectionString = connectionString;
            _emailService = emailService;
            _ticketService = ticketService;
            _emailCooldown = emailCooldown;
        }

        public async Task<User?> GetUserByUsernameAsync(string username)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            // SQL Güncellendi: is_email_confirmed eklendi
            const string sql = "SELECT id, username, password, email, subscription_status, trial_end_date, subscription_end_date, is_email_confirmed FROM app_user WHERE LOWER(username) = LOWER(@username) LIMIT 1;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@username", username);

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
                IsEmailConfirmed = reader.GetBoolean(7) // ✅ Onay durumu eklendi
            };
        }

        // Kullanıcı adı veya e-posta ile girişi kontrol eder, sonucu ve kullanıcıyı döner
        public async Task<(LoginStatus Status, User? User)> LoginAsync(string usernameOrEmail, string password)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "SELECT id, username, password, email, subscription_status, trial_end_date, subscription_end_date, is_email_confirmed FROM app_user WHERE LOWER(username) = LOWER(@value) OR LOWER(email) = LOWER(@value) LIMIT 1;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@value", InputRules.NormalizeUsername(usernameOrEmail));

            await using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return (LoginStatus.InvalidCredentials, null);

            // Önce onay kontrolü
            bool isConfirmed = reader.GetBoolean(7);
            if (!isConfirmed) return (LoginStatus.EmailNotConfirmed, null);

            var dbPasswordHash = reader.GetString(2);

            if (!BCrypt.Net.BCrypt.Verify(password, dbPasswordHash))
                return (LoginStatus.InvalidCredentials, null);

            return (LoginStatus.Success, new User
            {
                Id = reader.GetInt32(0),
                Username = reader.GetString(1),
                Password = dbPasswordHash,
                Email = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                SubscriptionStatus = reader.IsDBNull(4) ? "None" : reader.GetString(4),
                TrialEndDate = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                SubscriptionEndDate = reader.IsDBNull(6) ? null : reader.GetDateTime(6),
                IsEmailConfirmed = isConfirmed
            });
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

            if (!_emailCooldown.TryAcquire(email, DateTimeOffset.UtcNow, out var remaining))
                return (false, $"Yeni kod için lütfen {remaining} saniye bekleyin.", null);

            string code = RegistrationTicketService.GenerateCode();
            try
            {
                await _emailService.SendConfirmationEmailAsync(email, code);
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
        public async Task<(bool Success, string Message)> VerifyEmailAsync(string ticket, string code)
        {
            var status = _ticketService.Read(ticket, DateTimeOffset.UtcNow, out var data);
            if (status == TicketStatus.Expired)
                return (false, "Kodun süresi doldu, lütfen yeni kod isteyin.");
            if (status == TicketStatus.Invalid || data == null)
                return (false, "Geçersiz istek, lütfen kayıt işlemini yeniden başlatın.");
            if (data.Code != code)
                return (false, "Doğrulama kodu hatalı.");

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            var takenMessage = await CheckUsernameAndEmailTakenAsync(conn, data.Username, data.Email);
            if (takenMessage != null) return (false, takenMessage);

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
                return (false, "Bu kullanıcı adı veya e-posta az önce başkası tarafından alındı.");
            }

            return (true, "E-posta başarıyla doğrulandı.");
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

        public async Task<(bool Success, string Message)> UpdateUserProfile(UpdateProfileRequest request)
        {
            var username = InputRules.NormalizeUsername(request.NewUsername);
            var email = InputRules.NormalizeEmail(request.NewEmail);

            var inputError = InputRules.ValidateUsername(username) ?? InputRules.ValidateEmail(email);
            if (inputError != null) return (false, inputError);

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string checkSql = @"
                SELECT 
                    COUNT(*) FILTER (WHERE LOWER(email) = LOWER(@email) AND id != @id) as email_exists,
                    COUNT(*) FILTER (WHERE LOWER(username) = LOWER(@username) AND id != @id) as user_exists
                FROM app_user";

            await using (var cmd = new NpgsqlCommand(checkSql, conn))
            {
                cmd.Parameters.AddWithValue("@email", email);
                cmd.Parameters.AddWithValue("@username", username);
                cmd.Parameters.AddWithValue("@id", request.UserId);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    bool emailExists = reader.GetInt64(0) > 0;
                    bool userExists = reader.GetInt64(1) > 0;

                    if (emailExists) return (false, "Bu e-posta adresi zaten başka bir kullanıcı tarafından kullanılıyor.");
                    if (userExists) return (false, "Bu kullanıcı adı zaten alınmış.");
                }
            }

            const string updateSql = @"
                UPDATE app_user 
                SET username = @username, email = @email 
                WHERE id = @id";

            await using (var updateCmd = new NpgsqlCommand(updateSql, conn))
            {
                updateCmd.Parameters.AddWithValue("@username", username);
                updateCmd.Parameters.AddWithValue("@email", email);
                updateCmd.Parameters.AddWithValue("@id", request.UserId);

                int affectedRows = await updateCmd.ExecuteNonQueryAsync();
                
                if (affectedRows == 0)
                    return (false, "Kullanıcı bulunamadı veya güncellenemedi.");
            }

            return (true, "Profil başarıyla güncellendi.");
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
                return (true, "Şifre sıfırlama kodu e-posta adresinize gönderildi.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Email Hatası: {ex.Message}");
                _emailCooldown.Release(email);
                return (false, "E-posta gönderilirken bir hata oluştu.");
            }
        }

        public async Task<(bool Success, string Message)> ResetPasswordWithCodeAsync(string rawEmail, string code, string newPassword)
        {
            var email = InputRules.NormalizeEmail(rawEmail);
            var passwordError = InputRules.ValidatePassword(newPassword);
            if (passwordError != null) return (false, passwordError);

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string verifySql = "SELECT id FROM app_user WHERE LOWER(email) = LOWER(@email) AND reset_token = @code AND token_expiry > @now";
            await using var verifyCmd = new NpgsqlCommand(verifySql, conn);
            verifyCmd.Parameters.AddWithValue("@email", email);
            verifyCmd.Parameters.AddWithValue("@code", code);
            verifyCmd.Parameters.AddWithValue("@now", DateTime.Now);

            var userId = await verifyCmd.ExecuteScalarAsync();
            if (userId == null) return (false, "Kod hatalı veya süresi dolmuş.");

            string newPasswordHash = BCrypt.Net.BCrypt.HashPassword(newPassword);
            const string updateSql = "UPDATE app_user SET password = @password, reset_token = NULL, token_expiry = NULL WHERE id = @id";
            
            await using var updateCmd = new NpgsqlCommand(updateSql, conn);
            updateCmd.Parameters.AddWithValue("@password", newPasswordHash);
            updateCmd.Parameters.AddWithValue("@id", userId);
            await updateCmd.ExecuteNonQueryAsync();

            return (true, "Şifreniz başarıyla güncellendi.");
        }
    }
}