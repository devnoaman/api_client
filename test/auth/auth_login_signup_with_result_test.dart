import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Simple model to decode into
// ---------------------------------------------------------------------------

class _FakeUser {
  final int id;
  final String name;
  _FakeUser({required this.id, required this.name});

  factory _FakeUser.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return _FakeUser(id: map['id'] as int, name: map['name'] as String);
  }
}

// ---------------------------------------------------------------------------
// Interceptor that fakes HTTP responses so no real network call is made
// ---------------------------------------------------------------------------

typedef _ResponseFactory = Response Function(RequestOptions options);

class _FakeResponseInterceptor extends Interceptor {
  final _ResponseFactory factory;
  _FakeResponseInterceptor(this.factory);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final response = factory(options);
    handler.resolve(response);
  }
}

class _FakeErrorInterceptor extends Interceptor {
  final DioException Function(RequestOptions options) errorFactory;
  _FakeErrorInterceptor(this.errorFactory);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(errorFactory(options));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokensManager tokens;
  late StorageManager userMgr;
  late AuthManager auth;
  late List<AuthManagerStreamEvent> events;
  late StreamSubscription<AuthManagerStreamEvent> eventSub;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    Configuration.baseUrl = 'https://api.example.com';
    Configuration.tokenKeyName = 'token';
    Configuration.refreshTokenKeyName = 'refreshToken';

    tokens = TokensManager.instance;
    userMgr = StorageManager.instance;
    tokens.rememberMe = true;
    userMgr.rememberMe = true;
    await tokens.deleteAll();
    await userMgr.remove();

    auth = AuthManager.instance;

    events = <AuthManagerStreamEvent>[];
    eventSub = auth.authManagerStream.listen(events.add);
  });

  tearDown(() async {
    await eventSub.cancel();
    await tokens.deleteAll();
    await userMgr.remove();
  });

  /// Installs a fake interceptor on the NetworkClient Dio instance that
  /// resolves every request with the given [response].
  void installFakeResponse(_ResponseFactory factory) {
    // Ensure NetworkClient is initialised (idempotent because of singleton).
    NetworkClient(baseUrl: Configuration.baseUrl);
    final dio = NetworkClient.instance.dioClient;
    // Insert the fake as the *first* interceptor so it runs before auth/jwt.
    dio.interceptors.insert(0, _FakeResponseInterceptor(factory));
  }

  void installFakeError(DioException Function(RequestOptions) factory) {
    NetworkClient(baseUrl: Configuration.baseUrl);
    final dio = NetworkClient.instance.dioClient;
    dio.interceptors.insert(0, _FakeErrorInterceptor(factory));
  }

  void removeFakeInterceptors() {
    final dio = NetworkClient.instance.dioClient;
    dio.interceptors.removeWhere(
      (i) => i is _FakeResponseInterceptor || i is _FakeErrorInterceptor,
    );
  }

  // =========================================================================
  // loginWithResult
  // =========================================================================

  group('loginWithResult', () {
    test('returns AuthSuccess and persists tokens on 200', () async {
      final responsePayload = {
        'id': 1,
        'name': 'Alice',
        'token': 'access-abc',
        'refreshToken': 'refresh-xyz',
      };

      installFakeResponse(
        (opts) => Response(
          requestOptions: opts,
          statusCode: 200,
          data: responsePayload,
        ),
      );

      final result = await auth.loginWithResult<_FakeUser>(
        path: '/auth/login',
        data: {'email': 'alice@example.com', 'password': '123'},
        decoder: _FakeUser.fromJson,
      );

      // Verify result type
      expect(result, isA<AuthSuccess<_FakeUser>>());
      final success = result as AuthSuccess<_FakeUser>;
      expect(success.data.id, 1);
      expect(success.data.name, 'Alice');
      expect(success.statusCode, 200);

      // Verify tokens were persisted
      expect(await tokens.retrieveAccess(), 'access-abc');
      expect(await tokens.retriveRefresh(), 'refresh-xyz');

      // Verify user data was saved
      final user = await auth.me();
      expect(user, isNotNull);
      expect(user!['name'], 'Alice');

      // Verify loggedIn event was emitted
      expect(events.map((e) => e.type), contains(AuthManagerEventType.loggedIn));

      removeFakeInterceptors();
    });

    test('returns AuthFailure on non-200 response', () async {
      installFakeResponse(
        (opts) => Response(
          requestOptions: opts,
          statusCode: 403,
          data: {'error': 'Invalid credentials'},
        ),
      );

      final result = await auth.loginWithResult<_FakeUser>(
        path: '/auth/login',
        data: {'email': 'bad@example.com', 'password': 'wrong'},
        decoder: _FakeUser.fromJson,
      );

      expect(result, isA<AuthFailure<_FakeUser>>());
      final failure = result as AuthFailure<_FakeUser>;
      expect(failure.statusCode, 403);
      expect(failure.rawData, isNotNull);

      // No tokens should be saved
      expect(await tokens.retrieveAccess(), isNull);

      // No loggedIn event should be emitted
      expect(
        events.map((e) => e.type),
        isNot(contains(AuthManagerEventType.loggedIn)),
      );

      removeFakeInterceptors();
    });

    test('returns AuthFailure on DioException', () async {
      installFakeError(
        (opts) => DioException(
          requestOptions: opts,
          type: DioExceptionType.connectionTimeout,
          message: 'Connection timed out',
          response: Response(
            requestOptions: opts,
            statusCode: 408,
          ),
        ),
      );

      final result = await auth.loginWithResult<_FakeUser>(
        path: '/auth/login',
        data: {'email': 'alice@example.com', 'password': '123'},
        decoder: _FakeUser.fromJson,
      );

      expect(result, isA<AuthFailure<_FakeUser>>());
      final failure = result as AuthFailure<_FakeUser>;
      expect(failure.error, isA<DioException>());
      expect(failure.stackTrace, isNotNull);
      expect(failure.statusCode, 408);

      removeFakeInterceptors();
    });

    test('returns AuthFailure on unexpected exception', () async {
      // Intercept and throw a generic exception by using a custom interceptor
      NetworkClient(baseUrl: Configuration.baseUrl);
      final dio = NetworkClient.instance.dioClient;
      final badInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          throw StateError('Something went wrong');
        },
      );
      dio.interceptors.insert(0, badInterceptor);

      final result = await auth.loginWithResult<_FakeUser>(
        path: '/auth/login',
        data: {'email': 'alice@example.com', 'password': '123'},
        decoder: _FakeUser.fromJson,
      );

      expect(result, isA<AuthFailure<_FakeUser>>());
      final failure = result as AuthFailure<_FakeUser>;
      expect(failure.stackTrace, isNotNull);

      dio.interceptors.remove(badInterceptor);
    });

    test('respects rememberMe = false', () async {
      final responsePayload = {
        'id': 2,
        'name': 'Bob',
        'token': 'access-bob',
        'refreshToken': 'refresh-bob',
      };

      installFakeResponse(
        (opts) => Response(
          requestOptions: opts,
          statusCode: 200,
          data: responsePayload,
        ),
      );

      final result = await auth.loginWithResult<_FakeUser>(
        path: '/auth/login',
        data: {'email': 'bob@example.com', 'password': '456'},
        decoder: _FakeUser.fromJson,
        rememberMe: false,
      );

      expect(result, isA<AuthSuccess<_FakeUser>>());
      // Token should still be accessible in-memory
      expect(await tokens.retrieveAccess(), 'access-bob');

      removeFakeInterceptors();
    });
  });

  // =========================================================================
  // signUpWithResult
  // =========================================================================

  group('signUpWithResult', () {
    test('returns AuthSuccess and persists tokens on 200', () async {
      final responsePayload = {
        'id': 10,
        'name': 'Charlie',
        'token': 'access-charlie',
        'refreshToken': 'refresh-charlie',
      };

      installFakeResponse(
        (opts) => Response(
          requestOptions: opts,
          statusCode: 200,
          data: responsePayload,
        ),
      );

      final result = await auth.signUpWithResult<_FakeUser>(
        path: '/auth/register',
        data: {
          'name': 'Charlie',
          'email': 'charlie@example.com',
          'password': 'secure123',
        },
        decoder: _FakeUser.fromJson,
      );

      expect(result, isA<AuthSuccess<_FakeUser>>());
      final success = result as AuthSuccess<_FakeUser>;
      expect(success.data.id, 10);
      expect(success.data.name, 'Charlie');

      // Verify tokens were persisted
      expect(await tokens.retrieveAccess(), 'access-charlie');
      expect(await tokens.retriveRefresh(), 'refresh-charlie');

      // Verify user was stored
      final user = await auth.me();
      expect(user, isNotNull);
      expect(user!['id'], 10);

      // Verify loggedIn event
      expect(events.map((e) => e.type), contains(AuthManagerEventType.loggedIn));

      removeFakeInterceptors();
    });

    test('returns AuthFailure on non-200 response', () async {
      installFakeResponse(
        (opts) => Response(
          requestOptions: opts,
          statusCode: 422,
          data: {'error': 'Email already taken'},
        ),
      );

      final result = await auth.signUpWithResult<_FakeUser>(
        path: '/auth/register',
        data: {
          'name': 'Existing',
          'email': 'taken@example.com',
          'password': '123',
        },
        decoder: _FakeUser.fromJson,
      );

      expect(result, isA<AuthFailure<_FakeUser>>());
      final failure = result as AuthFailure<_FakeUser>;
      expect(failure.statusCode, 422);

      removeFakeInterceptors();
    });

    test('returns AuthFailure on DioException', () async {
      installFakeError(
        (opts) => DioException(
          requestOptions: opts,
          type: DioExceptionType.connectionError,
          message: 'No internet',
        ),
      );

      final result = await auth.signUpWithResult<_FakeUser>(
        path: '/auth/register',
        data: {'name': 'X', 'email': 'x@y.com', 'password': 'p'},
        decoder: _FakeUser.fromJson,
      );

      expect(result, isA<AuthFailure<_FakeUser>>());
      final failure = result as AuthFailure<_FakeUser>;
      expect(failure.error, isA<DioException>());

      removeFakeInterceptors();
    });
  });

  // =========================================================================
  // AuthResult pattern matching
  // =========================================================================

  group('AuthResult sealed class', () {
    test('can pattern match on AuthSuccess', () {
      final result = AuthSuccess<_FakeUser>(
        _FakeUser(id: 1, name: 'Test'),
        statusCode: 200,
      );

      final message = switch (result) {
        AuthSuccess<_FakeUser>(:final data) => 'Hello ${data.name}',
        AuthFailure<_FakeUser>(:final error) => 'Error: $error',
      };

      expect(message, 'Hello Test');
    });

    test('can pattern match on AuthFailure', () {
      final result = AuthFailure<_FakeUser>(
        Exception('bad request'),
        statusCode: 400,
      );

      final isError = switch (result) {
        AuthSuccess() => false,
        AuthFailure() => true,
      };

      expect(isError, isTrue);
    });

    test('AuthSuccess.toString includes data and statusCode', () {
      final s = AuthSuccess<int>(42, statusCode: 201);
      expect(s.toString(), contains('42'));
      expect(s.toString(), contains('201'));
    });

    test('AuthFailure.toString includes error and statusCode', () {
      final f = AuthFailure<int>(Exception('oops'), statusCode: 500);
      expect(f.toString(), contains('500'));
      expect(f.toString(), contains('oops'));
    });
  });
}
