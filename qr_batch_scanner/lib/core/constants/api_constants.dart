class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://asphaltic-manda-unquarrelling.ngrok-free.dev',
  );
  static const String apiPrefix = '/api/v1';

  static const String login = '$apiPrefix/auth/login';
  static const String register = '$apiPrefix/auth/register';
  static const String verifyEmail = '$apiPrefix/auth/verify-email';
  static const String updateProfile = '$apiPrefix/auth/update-profile';
  static const String forgotPassword = '$apiPrefix/auth/forgot-password';
  static const String resetPassword = '$apiPrefix/auth/reset-password';
  static const String refresh = '$apiPrefix/auth/refresh';
  static const String logout = '$apiPrefix/auth/logout';
  static const String me = '$apiPrefix/auth/me';
  static const String changeEmailRequest = '$apiPrefix/auth/change-email/request';
  static const String changeEmailConfirm = '$apiPrefix/auth/change-email/confirm';
  static const String qrLookup = '$apiPrefix/qr/lookup';
  static const String dbVersion = '$apiPrefix/qr/db-version';
  static const String dbExport = '$apiPrefix/qr/db-export';
  static const String itsResolveCode = '$apiPrefix/its/resolve-code';

  static const Set<String> publicPaths = {login, register, verifyEmail, forgotPassword, resetPassword, refresh, logout};
}

class ExternalUrls {
  static const String itsToken = 'https://its2.saglik.gov.tr/token/app/token/';
  static const String itsCheckStatus = 'https://its2.saglik.gov.tr/reference/app/check_status/';
  static const String publicIp = 'https://api.ipify.org';
}
