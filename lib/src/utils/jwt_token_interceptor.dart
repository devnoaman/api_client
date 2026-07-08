// lib/src/utils/jwt_token_interceptor.dart

import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:awesome_dio_interceptor/awesome_dio_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

/// A Dio interceptor that **proactively** checks JWT expiry before every request.
///
/// Behaviour:
/// 1. Skips the refresh endpoint itself to avoid infinite loops.
/// 2. Reads the stored access token and decodes it with `jwt_decoder`.
/// 3. If the token will expire within [expiryThreshold] (default 60 s), a
///    silent refresh is triggered *before* the original request is forwarded.
/// 4. Uses the same single-flight lock pattern as [AuthInterceptor] so that
///    parallel requests during a refresh share one refresh call.
/// 5. If refresh fails, the request still proceeds — the reactive [AuthInterceptor]
///    will handle any resulting 401.
///
/// Place this interceptor **before** [AuthInterceptor] in the interceptors list
/// so that the header is already fresh when [AuthInterceptor] runs.
class JwtTokenInterceptor extends Interceptor {
  final Dio _dio;

  /// How far in advance of actual expiry we should refresh (default: 60 s).
  final Duration expiryThreshold;

  final _logger = BaseLogger();

  /// Single-flight lock: if a proactive refresh is already in-flight, new
  /// requests wait on this future rather than issuing their own refresh.
  Future<String?>? _refreshTokenFuture;

  JwtTokenInterceptor(
    this._dio, {
    this.expiryThreshold = const Duration(seconds: 60),
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // onRequest
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Never intercept the refresh endpoint — infinite loop guard.
    // Also skip requests explicitly marked as unauthenticated so we never
    // proactively refresh/attach a token for a public endpoint.
    final requiresAuth = options.extra['authenticated'] as bool? ?? false;
    if (options.path.contains(Configuration.refreshUrl) || !requiresAuth) {
      return handler.next(options);
    }

    final accessToken = await TokensManager.instance.retrieveAccess();

    if (accessToken == null) {
      _logger.debug(
        'JwtTokenInterceptor: no access token stored, skipping check.',
      );
      return handler.next(options);
    }

    // Silently ignore tokens that cannot be decoded (opaque / non-JWT).
    if (!_isJwt(accessToken)) {
      _logger.debug(
        'JwtTokenInterceptor: token is not a decodable JWT, skipping.',
      );
      return handler.next(options);
    }

    if (_isAboutToExpire(accessToken)) {
      _logger.info(
        'JwtTokenInterceptor: token expires within '
        '${expiryThreshold.inSeconds}s — refreshing proactively.',
      );

      // Single-flight: only one refresh runs at a time.
      _refreshTokenFuture ??= _performTokenRefresh();

      try {
        final newToken = await _refreshTokenFuture;
        if (newToken != null) {
          _logger.info('JwtTokenInterceptor: proactive refresh succeeded.');
          options.headers['Authorization'] = 'Bearer $newToken';
        } else {
          _logger.warn(
            'JwtTokenInterceptor: proactive refresh returned null — '
            'proceeding with old token; AuthInterceptor will handle 401.',
          );
          // Still attach the old (possibly expired) token; the reactive
          // AuthInterceptor will deal with any resulting 401.
          options.headers['Authorization'] = 'Bearer $accessToken';
        }
      } catch (e) {
        _logger.error('JwtTokenInterceptor: proactive refresh threw: $e');
        options.headers['Authorization'] = 'Bearer $accessToken';
      } finally {
        _refreshTokenFuture = null;
      }
    }
    // If not about to expire the token header is set by AuthInterceptor.

    return handler.next(options);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns `true` when the token will expire within [expiryThreshold].
  bool _isAboutToExpire(String token) {
    try {
      final expiry = JwtDecoder.getExpirationDate(token);
      final remaining = expiry.difference(DateTime.now().toUtc());
      _logger.debug(
        'JwtTokenInterceptor: token expires in ${remaining.inSeconds}s '
        '(threshold: ${expiryThreshold.inSeconds}s).',
      );
      return remaining <= expiryThreshold;
    } catch (_) {
      // Malformed token — treat as not-about-to-expire; let the server decide.
      return false;
    }
  }

  /// Returns `true` if [token] looks like a three-part JWT.
  bool _isJwt(String token) {
    try {
      return !JwtDecoder.isExpired(token) ||
          JwtDecoder.decode(token).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Calls the backend refresh endpoint and persists the new tokens.
  ///
  /// Returns the new access token string, or `null` on failure.
  Future<String?> _performTokenRefresh() async {
    final refreshToken = await TokensManager.instance.retriveRefresh();
    final accessToken = await TokensManager.instance.retrieveAccess();

    if (refreshToken == null) {
      _logger.warn(
        'JwtTokenInterceptor: no refresh token available — cannot proactively refresh.',
      );
      return null;
    }

    // Use an independent Dio instance so this call bypasses the interceptor stack.
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ),
    )..interceptors.add(AwesomeDioInterceptor());

    try {
      _logger.info('JwtTokenInterceptor: sending proactive refresh request…');
      final response = await refreshDio.post(
        Configuration.refreshUrl,
        data: Configuration.refreshData ?? {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final newAccess = response.data[Configuration.tokenKeyName] as String?;
        final newRefresh =
            response.data[Configuration.refreshTokenKeyName] as String?;

        if (newAccess != null) {
          await TokensManager.instance.saveAccess(newAccess);
          if (newRefresh != null) {
            await TokensManager.instance.saveRefresh(newRefresh);
          }

          AuthManager.instance.emitAuthManagerEvent(
            AuthManagerStreamEvent(AuthManagerEventType.tokenRefreshed),
          );

          _logger.info('JwtTokenInterceptor: tokens saved successfully.');
          return newAccess;
        }
      }

      _logger.warn(
        'JwtTokenInterceptor: refresh call returned status '
        '${response.statusCode} — treating as failure.',
      );
      return null;
    } on DioException catch (e) {
      _logger.error(
        'JwtTokenInterceptor: Dio error during proactive refresh: ${e.message}',
      );

      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        // Refresh token itself is invalid/expired — emit session-expired event.
        AuthManager.instance.emitAuthManagerEvent(
          AuthManagerStreamEvent(
            AuthManagerEventType.sessionExpired,
            error: e.response?.data?.toString(),
          ),
        );
      } else {
        AuthManager.instance.emitAuthManagerEvent(
          AuthManagerStreamEvent(
            AuthManagerEventType.refreshFailed,
            error: e.response?.data?.toString(),
          ),
        );
      }
      return null;
    } catch (e) {
      _logger.error(
        'JwtTokenInterceptor: unexpected error during proactive refresh: $e',
      );
      return null;
    }
  }
}
