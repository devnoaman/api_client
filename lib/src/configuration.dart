class Configuration {
  static String baseUrl = 'localhost';
  static String refreshUrl = '/auth/refresh';
  static String tokenKeyName = 'token';
  static String refreshTokenKeyName = 'refreshToken';

  static Map<String, String> headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  static Map<String, String>? refreshData;
  static Map<String, String>? logoutData;
  static Duration? connectTimeout = const Duration(seconds: 30);
  static Duration? receiveTimeout = const Duration(seconds: 30);
  static Duration? sendTimeout = const Duration(seconds: 30);
  static bool enableLogs = true;

  /// How far before the JWT access-token's `exp` claim we should proactively
  /// refresh it. Defaults to 60 seconds so there is a safe window even on
  /// slow connections. Set to [Duration.zero] to disable proactive refresh.
  static Duration tokenExpiryThreshold = const Duration(seconds: 60);
}
