using Npgsql;
using QrBackend.Models;
using BCrypt.Net;

namespace QrBackend.Services
{
    public class AuthService
    {
        private readonly string _connectionString;
        private readonly EmailService _emailService;

        public AuthService(string connectionString, EmailService emailService)
        {
            _connectionString = connectionString;
            _emailService = emailService;
        }

        public async Task<User?> GetUserByUsernameAsync(string username)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            // SQL Güncellendi: is_email_confirmed eklendi
            const string sql = "SELECT id, username, password, email, subscription_status, trial_end_date, subscription_end_date, is_email_confirmed FROM app_user WHERE username = @username LIMIT 1;";

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

        public async Task<User?> LoginAsync(string usernameOrEmail, string password)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "SELECT id, username, password, email, subscription_status, trial_end_date, subscription_end_date, is_email_confirmed FROM app_user WHERE username = @value OR email = @value LIMIT 1;";

            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@value", usernameOrEmail);

            await using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;

            // Önce onay kontrolü
            bool isConfirmed = reader.GetBoolean(7);
            if (!isConfirmed) throw new Exception("Lütfen e-posta adresinizi onaylayın.");

            var dbPasswordHash = reader.GetString(2);

            if (!BCrypt.Net.BCrypt.Verify(password, dbPasswordHash))
                return null;

            return new User
            {
                Id = reader.GetInt32(0),
                Username = reader.GetString(1),
                Password = dbPasswordHash,
                Email = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                SubscriptionStatus = reader.IsDBNull(4) ? "None" : reader.GetString(4),
                TrialEndDate = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                SubscriptionEndDate = reader.IsDBNull(6) ? null : reader.GetDateTime(6),
                IsEmailConfirmed = isConfirmed
            };
        }

        public async Task<(bool Success, string Message)> RegisterAsync(RegisterRequest request)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            bool isUsernameTaken = false;
            bool isEmailTaken = false;

            const string userCheckSql = "SELECT COUNT(*) FROM app_user WHERE username = @username";
            await using (var cmd = new NpgsqlCommand(userCheckSql, conn))
            {
                cmd.Parameters.AddWithValue("@username", request.Username);
                isUsernameTaken = (long?)await cmd.ExecuteScalarAsync() > 0;
            }

            const string emailCheckSql = "SELECT COUNT(*) FROM app_user WHERE email = @email";
            await using (var cmd = new NpgsqlCommand(emailCheckSql, conn))
            {
                cmd.Parameters.AddWithValue("@email", request.Email);
                isEmailTaken = (long?)await cmd.ExecuteScalarAsync() > 0;
            }

            if (isUsernameTaken && isEmailTaken)
                return (false, "Hem kullanıcı adı hem de e-posta adresi zaten kullanımda.");
            
            if (isUsernameTaken)
                return (false, "Bu kullanıcı adı zaten alınmış.");
            
            if (isEmailTaken)
                return (false, "Bu e-posta adresi zaten kullanımda.");

            string passwordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);
            
            // ✅ YENİ: Doğrulama kodu üretiliyor
            string confirmationCode = new Random().Next(100000, 999999).ToString();

            // SQL Güncellendi: email_confirmation_code ve is_email_confirmed eklendi
            const string insertSql = @"INSERT INTO app_user (username, password, email, subscription_status, trial_end_date, created_at, email_confirmation_code, is_email_confirmed) 
                                     VALUES (@username, @password, @email, @subStatus, @trialEnd, @createdAt, @code, false)";
            
            await using (var insertCmd = new NpgsqlCommand(insertSql, conn))
            {
                insertCmd.Parameters.AddWithValue("@username", request.Username);
                insertCmd.Parameters.AddWithValue("@password", passwordHash);
                insertCmd.Parameters.AddWithValue("@email", request.Email);
                insertCmd.Parameters.AddWithValue("@subStatus", "Trialing"); 
                insertCmd.Parameters.AddWithValue("@trialEnd", DateTime.UtcNow.AddMinutes(5));
                insertCmd.Parameters.AddWithValue("@createdAt", DateTime.UtcNow);
                insertCmd.Parameters.AddWithValue("@code", confirmationCode); // ✅ Kod DB'ye yazılıyor
                
                await insertCmd.ExecuteNonQueryAsync();
            }

            // ✅ YENİ: Onay maili gönderiliyor
            try {
                await _emailService.SendConfirmationEmailAsync(request.Email, confirmationCode);
            } catch {
                // Mail gitmese bile kullanıcı oluştu, ileride tekrar gönderilebilir.
            }

            return (true, "Kayıt başarılı. Lütfen e-postanıza gelen kodu onaylayın.");
        }

        // ✅ YENİ: Email Doğrulama Kodunu Kontrol Eden Metod
        public async Task<(bool Success, string Message)> VerifyEmailAsync(string email, string code)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = "UPDATE app_user SET is_email_confirmed = true, email_confirmation_code = NULL WHERE email = @email AND email_confirmation_code = @code RETURNING id";
            
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@email", email);
            cmd.Parameters.AddWithValue("@code", code);

            var result = await cmd.ExecuteScalarAsync();

            if (result != null)
                return (true, "E-posta başarıyla doğrulandı.");
            
            return (false, "Doğrulama kodu hatalı veya e-posta bulunamadı.");
        }

        public async Task<(bool Success, string Message)> UpdateUserProfile(UpdateProfileRequest request)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string checkSql = @"
                SELECT 
                    COUNT(*) FILTER (WHERE email = @email AND id != @id) as email_exists,
                    COUNT(*) FILTER (WHERE username = @username AND id != @id) as user_exists
                FROM app_user";

            await using (var cmd = new NpgsqlCommand(checkSql, conn))
            {
                cmd.Parameters.AddWithValue("@email", request.NewEmail);
                cmd.Parameters.AddWithValue("@username", request.NewUsername);
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
                updateCmd.Parameters.AddWithValue("@username", request.NewUsername);
                updateCmd.Parameters.AddWithValue("@email", request.NewEmail);
                updateCmd.Parameters.AddWithValue("@id", request.UserId);

                int affectedRows = await updateCmd.ExecuteNonQueryAsync();
                
                if (affectedRows == 0)
                    return (false, "Kullanıcı bulunamadı veya güncellenemedi.");
            }

            return (true, "Profil başarıyla güncellendi.");
        }

        public async Task<(bool Success, string Message)> GenerateForgotPasswordCodeAsync(string email)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string userCheck = "SELECT id FROM app_user WHERE email = @email";
            await using var checkCmd = new NpgsqlCommand(userCheck, conn);
            checkCmd.Parameters.AddWithValue("@email", email);
            var userId = await checkCmd.ExecuteScalarAsync();

            if (userId == null) return (false, "Bu e-posta adresiyle kayıtlı bir kullanıcı bulunamadı.");

            string resetCode = new Random().Next(100000, 999999).ToString();
            DateTime expiry = DateTime.Now.AddMinutes(15); 

            const string updateSql = "UPDATE app_user SET reset_token = @code, token_expiry = @expiry WHERE email = @email";
            await using var updateCmd = new NpgsqlCommand(updateSql, conn);
            updateCmd.Parameters.AddWithValue("@code", resetCode);
            updateCmd.Parameters.AddWithValue("@expiry", expiry);
            updateCmd.Parameters.AddWithValue("@email", email);
            await updateCmd.ExecuteNonQueryAsync();

            try
            {
                await _emailService.SendResetEmailAsync(email, resetCode);
                return (true, "Şifre sıfırlama kodu e-posta adresinize gönderildi.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Email Hatası: {ex.Message}");
                return (false, "E-posta gönderilirken bir hata oluştu.");
            }
        }

        public async Task<(bool Success, string Message)> ResetPasswordWithCodeAsync(string email, string code, string newPassword)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            const string verifySql = "SELECT id FROM app_user WHERE email = @email AND reset_token = @code AND token_expiry > @now";
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