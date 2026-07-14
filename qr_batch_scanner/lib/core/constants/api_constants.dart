class ApiConstants {
  // Sadece ana domain ve port. Sonu /api ile BİTMESİN.
  static const String baseUrl = 'https://asphaltic-manda-unquarrelling.ngrok-free.dev';

  // Endpointleri burada yönetelim
  static const String login = '$baseUrl/api/auth/login';
  static const String register = '$baseUrl/api/auth/register';
  static const String qrLookup = '$baseUrl/api/qr/lookup';
  static const String dbVersion = '$baseUrl/api/qr/db-version';
  static const String dbExport = '$baseUrl/api/qr/db-export';
  static const String forgotPassword = '$baseUrl/api/auth/forgot-password';
  static const String resetPassword = '$baseUrl/api/auth/reset-password';
}