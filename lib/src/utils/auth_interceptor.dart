// lib/auth/auth_interceptor.dart

import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/network_client_logger_mixin.dart';
// import 'package:awesome_dio_interceptor/awesome_dio_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// Define these typedefs so they can be imported and used for dependency injection.
typedef LogoutCallback = Future<void> Function();
typedef ShowMessageCallback = void Function(String message);

/// A Dio interceptor for automatically handling authentication tokens.
///
/// This interceptor performs the following tasks:
/// 1. Attaches the current access token to every outgoing request (except for the refresh endpoint).
/// 2. Catches 401 Unauthorized errors.
/// 3. When a 401 is caught, it attempts to refresh the access token using a refresh token.
/// 4. It handles concurrent requests that fail with a 401, ensuring that the token is only refreshed once.
/// 5. If the token refresh is successful, it retries the original failed request(s) with the new token.
/// 6. If the token refresh fails, it triggers a global logout flow.
class AuthInterceptor extends Interceptor with NetworkClientLoggerMixin {
  final Dio _dio;
  final LogoutCallback? _onLogout;
  final ShowMessageCallback? _onShowMessage;
  final LogoutCallback? _onSessionExpired;

  static bool _isHandlingRefreshFailure = false;

  /// A Future that completes when the token refresh operation is done.
  ///
  /// This is used as a "lock" to prevent multiple concurrent token refresh requests.
  /// If this is not null, a refresh is already in progress.
  @visibleForTesting
  Future<String?>? refreshTokenFuture;

  AuthInterceptor(
    this._dio, {
    LogoutCallback? onLogout,
    ShowMessageCallback? onShowMessage,
    LogoutCallback? onSessionExpired,
  })  : _onLogout = onLogout,
        _onShowMessage = onShowMessage,
        _onSessionExpired = onSessionExpired;

  /// Called before a request is sent.
  ///
  /// Attaches the Authorization header with the access token.
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final enableLogs = options.extra['enableLogs'] as bool? ?? true;
    if (enableLogs) {
      logRequest(options);
    }
    // Do not add the Authorization header to the refresh token request itself,
    // as it typically uses the refresh token in its body for authentication.
    // Also skip it for requests the caller explicitly marked as unauthenticated
    // (e.g. signup/OTP endpoints) so a stale/expired cached token never gets
    // attached to a request that should be sent anonymously.
    final requiresAuth = options.extra['authenticated'] as bool? ?? false;
    if (options.path.contains(Configuration.refreshUrl) || !requiresAuth) {
      return handler.next(options);
    }

    // Wait if a token refresh is currently in progress.
    if (refreshTokenFuture != null) {
      logger.info('AuthInterceptor: Pausing request to ${options.path} while token is refreshing.');
      await refreshTokenFuture;
    }

    // ignore: deprecated_member_use_from_same_package
    final accessToken = await TokensManager.instance.retrieveAccess();

    if (accessToken != null) {
      // The proactive check from the original code was removed because relying
      // on the 401 `onError` handler is a simpler and more robust pattern.
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (options.data is FormData) {
      // Clone the form data fields and files to re-create it later
      final formData = options.data as FormData;
      final Map<String, dynamic> formDataMap = {};

      // Copy fields
      formDataMap.addEntries(formData.fields);

      // Copy files
      formDataMap.addEntries(formData.files);

      // Store this map in 'extra' so we can access it in onError
      options.extra['formData'] = formDataMap;
    }
    return handler.next(options);
  }

  /// Called when a request fails.
  ///
  /// This is the core logic for handling expired tokens.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Check if the error is a 401 Unauthorized and it's not from the refresh endpoint.
    if (err.response?.statusCode == 401 &&
        !err.requestOptions.path.contains(Configuration.refreshUrl)) {
      logger.info(
        'AuthInterceptor: 401 Unauthorized detected for ${err.requestOptions.path}',
      );

      final options = err.requestOptions;

      // Check if the token was already refreshed while this request was in flight.
      // ignore: deprecated_member_use_from_same_package
      final currentToken = await TokensManager.instance.retrieveAccess();
      final requestToken = options.headers['Authorization']?.toString().replaceFirst('Bearer ', '');

      if (currentToken != null && requestToken != null && currentToken != requestToken) {
        logger.info('AuthInterceptor: Token was already refreshed by another request. Retrying immediately.');
        options.headers['Authorization'] = 'Bearer $currentToken';
        
        // Handle FormData and clone MultipartFiles if necessary
        if (options.data is FormData) {
          final oldFormData = options.data as FormData;
          final newFormDataMap = <String, dynamic>{};
          newFormDataMap.addEntries(oldFormData.fields);
          for (var mapEntry in oldFormData.files) {
            newFormDataMap[mapEntry.key] = mapEntry.value.clone();
          }
          options.data = FormData.fromMap(newFormDataMap);
        }
        
        try {
          final response = await _dio.fetch(options);
          return handler.resolve(response);
        } catch (e) {
          return handler.next(err);
        }
      }

      // Lock to prevent multiple concurrent refresh attempts.
      // If a refresh is already in progress, `refreshTokenFuture` will not be null,
      // and subsequent requests will wait on the existing future.
      if (refreshTokenFuture == null) {
        logger.info('AuthInterceptor: Starting new token refresh.');
        refreshTokenFuture = _performTokenRefresh();
      } else {
        logger.info('AuthInterceptor: Waiting for ongoing token refresh.');
      }

      try {
        // Wait for the refresh operation to complete.
        final newAccessToken = await refreshTokenFuture;

        if (newAccessToken == null) {
          // If refresh failed, logout the user and propagate the original error.
          logger.info('AuthInterceptor: Token refresh failed. Logging out.');
          await _handleRefreshFailure();
          return handler.next(err);
        }

        // Successfully refreshed the token.
        // Now, retry the original request with the new token.
        logger.info(
          'AuthInterceptor: Token refreshed. Retrying original request.',
        );

        options.headers['Authorization'] = 'Bearer $newAccessToken';

        // // Step 3: Re-create FormData if it was the original data type
        // if (options.extra.containsKey('formData')) {
        //   final formDataMap = options.extra['formData'] as Map<String, dynamic>;
        //   // ✨ This is the key part: create a NEW FormData object ✨
        //   options.data = FormData.fromMap(formDataMap);
        // }

        // 3. Handle FormData and clone MultipartFiles
        if (options.data is FormData) {
          final oldFormData = options.data as FormData;
          final newFormDataMap = <String, dynamic>{};

          // Copy regular fields
          newFormDataMap.addEntries(oldFormData.fields);

          // ✨ Clone each MultipartFile before adding to the new map ✨
          for (var mapEntry in oldFormData.files) {
            newFormDataMap[mapEntry.key] = mapEntry.value.clone();
          }

          // Create a new FormData object with the cloned files
          options.data = FormData.fromMap(newFormDataMap);
        }
        final response = await _dio.fetch(options);
        return handler.resolve(response);
      } catch (e) {
        logger.error(
          'AuthInterceptor: Exception during token refresh/retry logic: $e',
        );
        await _handleRefreshFailure();
        return handler.next(err);
      } finally {
        refreshTokenFuture = null;
      }
    }

    final enableLogs = err.requestOptions.extra['enableLogs'] as bool? ?? true;
    if (enableLogs) {
      logError(err);
      if (err.response != null) {
        logResponse(
          err.response!,
          error: true,
          style: NetworkClientLoggerMixin.defaultErrorStyle,
        );
      }

      logNewLine();
    }

    // For all other errors, pass them along.
    return handler.next(err);
  }

  /// Handles the actual token refresh API call.
  ///
  /// Returns the new access token on success, or null on failure.
  Future<String?> _performTokenRefresh() async {
    final refreshToken = await TokensManager.instance.retriveRefresh();

    if (refreshToken == null) {
      logger.info(
        'AuthInterceptor: No refresh token available. Cannot refresh.',
      );
      return null;
    }

    // Use a separate Dio instance for the refresh token call to avoid
    // running into an infinite loop with the interceptor.
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    )..interceptors.addAll([LogInterceptor()]);

    try {
      logger.info('AuthInterceptor: Sending refresh token request...');
      final response = await refreshDio.post(
        Configuration.refreshUrl,
        data: Configuration.refreshData ??
            {Configuration.refreshTokenKeyName: refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final newAccessToken =
            response.data[Configuration.tokenKeyName] as String?;
        final newRefreshToken =
            response.data[Configuration.refreshTokenKeyName] as String?;

        if (newAccessToken != null) {
          await TokensManager.instance.saveAccess(newAccessToken);
          if (newRefreshToken != null) {
            // If the backend provides a new refresh token (rotation), store it.
            // await _secureStorage.write(
            //   key: 'refreshToken',
            //   value: newRefreshToken,
            // );
            await TokensManager.instance.saveRefresh(newRefreshToken);
          }
          logger.info('AuthInterceptor: Token refreshed successfully!');
          return newAccessToken;
        }
      }
      // If status code is not 200 or tokens are missing, it's a refresh failure.
      logger.info(
        'AuthInterceptor: Refresh token API call failed: Status ${response.statusCode}, Data: ${response.data}',
      );

      return null;
    } on DioException catch (e) {
      logger.info(
        'AuthInterceptor: Dio error during refresh token API call:\n'
        '  type    : ${e.type}\n'
        '  message : ${e.message}\n'
        '  error   : ${e.error}\n'
        '  status  : ${e.response?.statusCode}\n'
        '  baseUrl : ${refreshDio.options.baseUrl}\n'
        '  refreshUrl: ${Configuration.refreshUrl}',
      );
      AuthManager.instance.emitAuthManagerEvent(
        AuthManagerStreamEvent(
          AuthManagerEventType.refreshFailed,
          error:
              'type=${e.type} message=${e.message} error=${e.error} status=${e.response?.statusCode}',
        ),
      );
      // A 401 or 403 on the refresh endpoint means the refresh token is invalid/expired.
      return null;
    } catch (e) {
      logger.info('AuthInterceptor: Unexpected error during refresh token: $e');
      return null;
    }
  }

  /// Handles the common logic for a failed token refresh.
  ///
  /// This clears all stored tokens, user data, Dio headers, emits
  /// [AuthManagerEventType.sessionExpired] and [AuthManagerEventType.loggedOut],
  /// and triggers app-wide callbacks.
  Future<void> _handleRefreshFailure([Object? error]) async {
    if (_isHandlingRefreshFailure) return;
    _isHandlingRefreshFailure = true;

    try {
      // 1. Clear session, tokens, user data, and Dio headers
      await AuthManager.instance.clearSession();

      // 2. Emit sessionExpired event on auth stream
      AuthManager.instance.emitAuthManagerEvent(
        AuthManagerStreamEvent(
          AuthManagerEventType.sessionExpired,
          error: error ?? 'Session expired: token refresh failed.',
        ),
      );

      // 3. User-facing message callback
      const message = 'Your session has expired. Please log in again.';
      _onShowMessage?.call(message);
      Configuration.onShowMessage?.call(message);

      // 4. Trigger app-wide logout callbacks
      await _onLogout?.call();
      await _onSessionExpired?.call();
      await Configuration.onSessionExpired?.call();
      await Configuration.onLogout?.call();
    } catch (e) {
      logger.error('AuthInterceptor: Error during _handleRefreshFailure: $e');
    } finally {
      _isHandlingRefreshFailure = false;
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final enableLogs =
        response.requestOptions.extra['enableLogs'] as bool? ?? true;
    if (enableLogs) {
      logResponse(response);
    }
    super.onResponse(response, handler);
  }
}
