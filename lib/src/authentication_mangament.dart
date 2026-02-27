import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:api_client/src/storage_mangament.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:dio/dio.dart';

typedef AuthenticationDecoder<T> = T Function(dynamic data);
typedef LoginDecoder<T> = T Function(dynamic data);
typedef RefreshErrorHandler<T> = void Function(T data);

// AuthManagerStreamEvent

enum AuthManagerEventType {
  loggedIn,
  loggedOut,
  tokenRefreshed,
  refreshFailed,
  tokenExpired,
  sessionExpired,
}

class AuthManagerStreamEvent<T> {
  final AuthManagerEventType type;
  final T? data;
  final Object? error;

  AuthManagerStreamEvent(this.type, {this.data, this.error});

  @override
  String toString() =>
      'AuthManagerStreamEvent(type: $type, data: $data, error: $error)';
}

class AuthManager {
  // Static private instance is now of a non-generic type.
  // static AuthManager _instance;

  // Private constructor remains the same.
  AuthManager._();
  //
  final logger = BaseLogger();

  //
  final _authManagerStreamController =
      StreamController<AuthManagerStreamEvent>.broadcast();
  Stream<AuthManagerStreamEvent> get authManagerStream =>
      _authManagerStreamController.stream;

  void emitAuthManagerEvent(AuthManagerStreamEvent event) {
    logger.debug('Emitting AuthManager event: $event');
    _authManagerStreamController.add(event);
  }

  // Add dispose method
  Future<void> dispose() async {
    await _authManagerStreamController.close();
  }

  // Add method to check if controller is closed
  bool get isDisposed => _authManagerStreamController.isClosed;
  static RefreshErrorHandler? onRefreshError;

  // static AuthManager<T> instance = _instance<T>;
  static final AuthManager instance = AuthManager._();

  // The decoder is part of the instance state.
  // final AuthDecoder<T> responseDecoder;
  static const String _userKey = 'user_model';
  static const String _tokenKey = 'token_key';
  static Future<void> Function()? onRemove;

  // static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static StorageManager userManager = StorageManager.instance;
  static TokensManager tokensManager = TokensManager.instance;
  // A public static getter to allow other classes to access the storage instance.
  // You can now use `AuthManager.storage` from anywhere in your app.
  // static FlutterSecureStorage get storage => _storage;

  // Your methods can now use the responseDecoder.
  Future login({
    required String path,
    required Map<String, dynamic> data,
    bool enableLogs = true,
    required AuthenticationDecoder decoder,
  }) async {
    final client = NetworkClient().dioClient;
    // var baseUrl = Configuration.baseUrl;
    try {
      var response = await client.post(
        path,
        data: data,
        options: Options(
          headers: {
            ...Configuration.headers,
            'enableLogs': enableLogs,
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        var token = findAccessToken(response.data);
        var refreshToken = findRefreshToken(response.data);

        logger.debug('token founded: ${token}');
        if (token != null) {
          await tokensManager.saveAccess(
            token.toString(),
          );
          await tokensManager.saveRefresh(
            refreshToken.toString(),
          );
        }
        userManager.save(jsonEncode(response.data));
        var decoded = decoder(response.data);
        return decoded;
      }
      return null;
      // throw Exception('Login failed with status code: ${response.statusCode}');
    } on DioException catch (e) {
      logger.error('Dio error on GET request to $path: ${e.message}');
      // return null;
      throw Exception('Dio error on GET request to $path: ${e.message}');
    } catch (e, st) {
      logger.error('Unexpected error on GET request to $path: $e');
      logger.error(e.toString());
      logger.error(st.toString());
      // return null;
      throw Exception('Unexpected error on GET request to $path: $e');
    }
  }

  // tokenData
  // apiClient
  Object? findAccessToken(dynamic data) {
    if (data is Map) {
      if (data.containsKey(Configuration.tokenKeyName)) {
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

  Future logout({
    required String path,
    Object? data,
    required AuthenticationDecoder decoder,
    bool callApi = true,
    bool? authenticated = false,
  }) async {
    // final client = NetworkClient().dioClient;
    final client = NetworkClient().dioClient;

    var user = await me();
    await onRemove?.call();
    if (!callApi) {
      await userManager.remove();
      return;
    }
    var token = (user != null) ? findAccessToken(user) as String : null;

    try {
      var ob = Options(headers: {'Authorization': 'Bearer $token'});
      var response = await client.post(
        path,
        data: data ?? Configuration.logoutData,
        options: ob,
      );

      if (response.statusCode == 200 && response.data != null) {
        return decoder(
          response.data,
        );
      }
      return null;
    } on DioException catch (e) {
      logger.error('Dio error on GET request to $path: ${e.message}');
      return null;
    } catch (e) {
      logger.error('Unexpected error on GET request to $path: $e');
      return null;
    } finally {
      await userManager.remove();
    }
  }

  Future<Map<String, dynamic>?> me({
    String? path,
    AuthenticationDecoder? responseDecoder,
  }) async {
    final userJson = await userManager.retrive();
    if (userJson == null) {
      return null;
    }
    if (responseDecoder != null) {
      return responseDecoder(userJson);
    }
    return userJson;
  }
}
