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
}
