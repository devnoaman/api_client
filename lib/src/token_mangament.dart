import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

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

  /// When [rememberMe] is `true` (default), tokens are persisted to secure
  /// storage and survive app restarts. When `false`, tokens live only in the
  /// in-memory cache and are cleared when the app process ends.
  bool rememberMe = true;

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
        logger.debug(
          'TokensManager initialized: access token loaded from storage',
        );
      } else {
        logger.debug('TokensManager initialized: no access token in storage');
      }
    } catch (e) {
      // OperationError means the IndexedDB data was encrypted with a WebCrypto
      // key that no longer exists (cleared cookies/session, different origin,
      // or browser key rotation). The stored data is permanently unreadable —
      // wipe it so the user is prompted to re-authenticate cleanly.
      logger.warn(
        'TokensManager.initialize() storage corrupted ($e). Clearing all tokens.',
      );
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
    if (rememberMe) {
      return await _storage.write(
        key: _accessKey,
        value: accessToken,
      );
    }
  }

  Future<void> saveRefresh(String refreshToken) async {
    logger.debug("Saving refresh token");
    _cachedRefreshToken = refreshToken;
    if (rememberMe) {
      return await _storage.write(
        key: _refreshKey,
        value: refreshToken,
      );
    }
  }

  /// Returns the raw access token from cache or secure storage **without**
  /// checking expiry.
  ///
  /// Use [retrieveValidAccess] (or its alias [retrieveNotExpiredToken]) instead,
  /// which automatically refreshes the token when it is expired or about to expire.
  @Deprecated(
    'Use retrieveValidAccess() or retrieveNotExpiredToken() instead. '
    'retrieveAccess() does not check token expiry and may return an expired token.',
  )
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

  // Internal: same as retrieveAccess() but without the deprecation warning,
  // for use within this package (interceptors, etc.) where raw token access
  // is intentional.
  Future<String?> _retrieveAccessRaw() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;
    try {
      final String? access = await _storage.read(key: _accessKey);
      if (access != null) _cachedAccessToken = access;
      return access;
    } catch (_) {
      return null;
    }
  }


  /// Retrieves a valid, unexpired access token.
  ///
  /// 1. Reads the current access token from cache / secure storage.
  /// 2. If it is a decodable JWT that is already expired (or will expire within
  ///    [threshold], which defaults to [Configuration.tokenExpiryThreshold]),
  ///    the refresh flow is triggered automatically.
  /// 3. The refresh is performed by [JwtTokenInterceptor.performRefresh] — the
  ///    **same code path** used by the proactive interceptor — so there is a
  ///    single source of truth and a shared single-flight lock.
  ///
  /// Set [forceRefresh] to `true` to skip the expiry check and refresh
  /// unconditionally.
  ///
  /// Returns the valid access token, or `null` if no token exists or refresh
  /// fails.
  Future<String?> retrieveValidAccess({
    Duration? threshold,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      logger.debug('retrieveValidAccess: forceRefresh=true, refreshing…');
      return JwtTokenInterceptor.performRefresh(NetworkClient.base().dioClient);
    }

    final token = await _retrieveAccessRaw();

    if (token == null) {
      logger.debug('retrieveValidAccess: no token found, attempting refresh…');
      return JwtTokenInterceptor.performRefresh(NetworkClient.base().dioClient);
    }

    // Only treat it as expired when we can actually decode it as a JWT.
    final bool expired;
    try {
      final expiry = JwtDecoder.getExpirationDate(token);
      final remaining = expiry.difference(DateTime.now().toUtc());
      final safeThreshold = threshold ?? Configuration.tokenExpiryThreshold;
      expired = remaining <= safeThreshold;
      logger.debug(
        'retrieveValidAccess: token expires in ${remaining.inSeconds}s '
        '(threshold ${safeThreshold.inSeconds}s) — expired=$expired',
      );
    } catch (_) {
      // Opaque / non-JWT token — assume it is valid and return as-is.
      logger.debug('retrieveValidAccess: token is not a decodable JWT, returning as-is.');
      return token;
    }

    if (!expired) return token;

    logger.info('retrieveValidAccess: token expired or about to expire, refreshing…');
    return JwtTokenInterceptor.performRefresh(NetworkClient.base().dioClient);
  }

  /// Alias for [retrieveValidAccess].
  Future<String?> retrieveNotExpiredToken({Duration? threshold}) =>
      retrieveValidAccess(threshold: threshold);


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
    final String? access =
        _cachedAccessToken ?? await _storage.read(key: _accessKey);
    final String? refresh =
        _cachedRefreshToken ?? await _storage.read(key: _refreshKey);
    return {
      "access": access,
      "refresh": refresh,
    };
  }

  /// Alias for [retriveAll] with standard spelling.
  Future<Map<String, dynamic>?> retrieveAll() => retriveAll();

  /// Alias for [retriveRefresh] with standard spelling.
  Future<String?> retrieveRefresh() => retriveRefresh();

  /// Removes only the access token from cache and persistent storage.
  Future<void> removeAccess() async {
    _cachedAccessToken = null;
    try {
      await _storage.delete(key: _accessKey);
    } catch (_) {}
  }

  /// Removes only the refresh token from cache and persistent storage.
  Future<void> removeRefresh() async {
    _cachedRefreshToken = null;
    try {
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }

  /// Completely removes both access and refresh tokens from in-memory cache
  /// and persistent secure storage.
  Future<void> deleteAll() async {
    logger.warn("Deleting all tokens");
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _initialized = false;
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
      await _storage.deleteAll();
    } catch (e) {
      logger.warn('Error deleting tokens from storage: $e');
    }
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
