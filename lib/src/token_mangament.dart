import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokensManager {
  TokensManager._();
  static final TokensManager instance = TokensManager._();
  final logger = BaseLogger();

  static const String _accessKey = 'access';
  static const String _refreshKey = 'refresh';

  // In-memory cache to avoid Web Crypto race conditions on hot restart.
  // On web, concurrent reads through flutter_secure_storage_web can race
  // inside _getEncryptionKey and cause a DOMException during decrypt.
  String? _cachedAccessToken;
  String? _cachedRefreshToken;

  bool _initialized = false;

  /// Call this once at app startup (before any API requests) to eagerly
  /// pre-load tokens from secure storage into the in-memory cache.
  ///
  /// This prevents the Web Crypto race condition where a concurrent
  /// flutter_secure_storage read during the first request can fail and
  /// return null even though a valid token is stored.
  ///
  /// Example (in main.dart or your app bootstrap):
  /// ```dart
  /// await TokensManager.instance.initialize();
  /// ```
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _cachedAccessToken = await _storage.read(key: _accessKey);
      _cachedRefreshToken = await _storage.read(key: _refreshKey);
      if (_cachedAccessToken != null) {
        logger.debug('TokensManager initialized: access token loaded from storage');
      } else {
        logger.debug('TokensManager initialized: no access token in storage');
      }
    } catch (e) {
      // OperationError means the IndexedDB data was encrypted with a WebCrypto
      // key that no longer exists (cleared cookies/session, different origin,
      // or browser key rotation). The stored data is permanently unreadable —
      // wipe it so the user is prompted to re-authenticate cleanly.
      logger.warn('TokensManager.initialize() storage corrupted ($e). Clearing all tokens.');
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
      try {
        await _storage.deleteAll();
      } catch (_) {
        // If deleteAll also fails, ignore — storage is already in a bad state.
      }
    }
  }

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'tokens_db',
      publicKey: 'tokens_db',
      // useSessionStorage: true,
    ),
  );
  static FlutterSecureStorage get storage => _storage;

  Future<void> saveAccess(String accessToken) async {
    logger.debug("Saving access token");
    _cachedAccessToken = accessToken;
    return await _storage.write(
      key: _accessKey,
      value: accessToken,
    );
  }

  Future<void> saveRefresh(String refreshToken) async {
    logger.debug("Saving refresh token");
    _cachedRefreshToken = refreshToken;
    return await _storage.write(
      key: _refreshKey,
      value: refreshToken,
    );
  }

  Future<String?> retrieveAccess() async {
    if (_cachedAccessToken != null) {
      logger.debug("Access token found (cache)");
      return _cachedAccessToken;
    }
    try {
      final String? access = await _storage.read(key: _accessKey);
      if (access != null) {
        logger.debug("Access token found");
        _cachedAccessToken = access;
      } else {
        logger.warn("Access token not found");
      }
      return access;
    } catch (e) {
      logger.warn('retrieveAccess() storage error ($e). Treating as no token.');
      return null;
    }
  }

  Future<String?> retriveRefresh() async {
    if (_cachedRefreshToken != null) {
      logger.debug("Refresh token found (cache)");
      return _cachedRefreshToken;
    }
    try {
      final String? refresh = await _storage.read(key: _refreshKey);
      if (refresh != null) {
        logger.debug("Refresh token found");
        _cachedRefreshToken = refresh;
      } else {
        logger.warn("Refresh token not found");
      }
      return refresh;
    } catch (e) {
      logger.warn('retriveRefresh() storage error ($e). Treating as no token.');
      return null;
    }
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
    logger.warn("Deleting all tokens");
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _initialized = false;
    await _storage.deleteAll();
  }

  Object? findAccessToken(dynamic data) {
    if (data is Map) {
      if (data.containsKey(Configuration.tokenKeyName)) {
        logger.debug("Found access token in data map");
        return data[Configuration.tokenKeyName];
      }
      for (var value in data.values) {
        final result = findAccessToken(value);
        if (result != null) {
          return result;
        }
      }
    } else if (data is List) {
      for (var item in data) {
        final result = findAccessToken(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null; // Key not found
  }

  Object? findRefreshToken(dynamic data) {
    if (data is Map) {
      if (data.containsKey(Configuration.refreshTokenKeyName)) {
        logger.debug("Found refresh token in data map");
        return data[Configuration.refreshTokenKeyName];
      }
      for (var value in data.values) {
        final result = findRefreshToken(value);
        if (result != null) {
          return result;
        }
      }
    } else if (data is List) {
      for (var item in data) {
        final result = findRefreshToken(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }
}
