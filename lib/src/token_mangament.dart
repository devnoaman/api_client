import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokensManager {
  TokensManager._();
  static final TokensManager instance = TokensManager._();

  static const String _accessKey = 'access';
  static const String _refreshKey = 'refresh';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static FlutterSecureStorage get storage => _storage;
  Future<void> saveAccess(String accessToken) async {
    return await _storage.write(
      key: _accessKey,
      value: accessToken,
    );
  }

  Future<void> saveRefresh(String refreshToken) async {
    return await _storage.write(
      key: _refreshKey,
      value: refreshToken,
    );
  }

  Future<String?> retriveAccess() async {
    final String? access = await _storage.read(
      key: _accessKey,
    );

    return access;
  }

  Future<String?> retriveRefresh() async {
    final String? refresh = await _storage.read(
      key: _refreshKey,
    );
    return refresh;
  }

  Future<Map<String, dynamic>?> retriveAll() async {
    final String? access = await _storage.read(
      key: _accessKey,
    );
    final String? refresh = await _storage.read(
      key: _refreshKey,
    );
    return {
      "access": access,
      "refresh": refresh,
    };
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
