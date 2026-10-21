class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://asphaltic-manda-unquarrelling.ngrok-free.dev',
  );
  static const String apiPrefix = '/api';

  static const String login = '$apiPrefix/auth/login';
  static const String register = '$apiPrefix/auth/register';
  static const String verifyEmail = '$apiPrefix/auth/verify-email';
  static const String updateProfile = '$apiPrefix/auth/update-profile';
  static const String forgotPassword = '$apiPrefix/auth/forgot-password';
  static const String resetPassword = '$apiPrefix/auth/reset-password';
  static const String qrLookup = '$apiPrefix/qr/lookup';
  static const String dbVersion = '$apiPrefix/qr/db-version';
  static const String dbExport = '$apiPrefix/qr/db-export';
  static const String itsResolveCode = '$apiPrefix/its/resolve-code';

  // Kullanıcı adını adrese güvenli şekilde ekleyerek profil adresini döner
  static String profile(String username) => '$apiPrefix/auth/profile/${Uri.encodeComponent(username)}';
}

class ExternalUrls {
  static const String itsToken = 'https://its2.saglik.gov.tr/token/app/token/';
  static const String itsCheckStatus = 'https://its2.saglik.gov.tr/reference/app/check_status/';
  static const String publicIp = 'https://api.ipify.org';
}
