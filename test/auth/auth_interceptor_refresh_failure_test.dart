import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokensManager tokens;
  late StorageManager userMgr;
  late List<AuthManagerStreamEvent> events;
  late StreamSubscription<AuthManagerStreamEvent> eventSub;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    Configuration.baseUrl = 'https://api.example.com';
    Configuration.refreshUrl = '/auth/refresh';
    Configuration.tokenKeyName = 'token';
    Configuration.refreshTokenKeyName = 'refreshToken';
    Configuration.onSessionExpired = null;
    Configuration.onLogout = null;
    Configuration.onShowMessage = null;
    AuthInterceptor.debugRefreshHttpClientAdapter = null;

    tokens = TokensManager.instance;
    userMgr = StorageManager.instance;
    tokens.rememberMe = true;
    userMgr.rememberMe = true;
    await tokens.deleteAll();
    await userMgr.remove();

    events = <AuthManagerStreamEvent>[];
    eventSub = AuthManager.instance.authManagerStream.listen(events.add);
  });

  tearDown(() async {
    await eventSub.cancel();
    AuthInterceptor.debugRefreshHttpClientAdapter = null;
    Configuration.onSessionExpired = null;
    Configuration.onLogout = null;
    Configuration.onShowMessage = null;
    await tokens.deleteAll();
    await userMgr.remove();
  });

  Future<void> seedExpiredSession({
    String access = 'expired-access',
    String? refresh = 'stale-refresh',
    Map<String, dynamic> user = const {'user': 'Bob'},
  }) async {
    await tokens.saveAccess(access);
    if (refresh != null) {
      await tokens.saveRefresh(refresh);
    } else {
      await tokens.removeRefresh();
    }
    await userMgr.save(jsonEncode(user));
  }

  DioException unauthorized401({
    required String path,
    String accessToken = 'expired-access',
  }) {
    final reqOptions = RequestOptions(
      path: path,
      baseUrl: Configuration.baseUrl,
      headers: {'Authorization': 'Bearer $accessToken'},
      extra: {'authenticated': true, 'enableLogs': false},
    );
    return DioException(
      requestOptions: reqOptions,
      response: Response(
        requestOptions: reqOptions,
        statusCode: 401,
        statusMessage: 'Unauthorized',
      ),
      type: DioExceptionType.badResponse,
    );
  }

  Future<_ErrorOutcome> trigger401(
    AuthInterceptor interceptor,
    DioException err,
  ) async {
    final completer = Completer<_ErrorOutcome>();
    interceptor.onError(
      err,
      _RecordingErrorHandler(
        onNext: (e) {
          if (!completer.isCompleted) {
            completer.complete(_ErrorOutcome.next(e));
          }
        },
        onResolve: (r) {
          if (!completer.isCompleted) {
            completer.complete(_ErrorOutcome.resolved(r));
          }
        },
      ),
    );
    return completer.future.timeout(const Duration(seconds: 3));
  }

  group('AuthInterceptor refresh failure — notify without logout', () {
    test(
      'missing refresh token notifies client and preserves session',
      () async {
        await seedExpiredSession(refresh: null);

        var sessionExpiredCount = 0;
        var logoutCount = 0;
        String? shownMessage;

        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          // ignore: deprecated_member_use_from_same_package
          onLogout: () async => logoutCount++,
          onSessionExpired: () async => sessionExpiredCount++,
          onShowMessage: (msg) => shownMessage = msg,
        );

        final outcome = await trigger401(
          interceptor,
          unauthorized401(path: '/protected/resource'),
        );

        expect(outcome.didPropagateError, isTrue);
        expect(outcome.error?.response?.statusCode, 401);

        expect(sessionExpiredCount, 1);
        expect(logoutCount, 0);
        expect(shownMessage, contains('session has expired'));

        expect(
          events.map((e) => e.type),
          contains(AuthManagerEventType.sessionExpired),
        );
        expect(
          events.map((e) => e.type),
          isNot(contains(AuthManagerEventType.loggedOut)),
        );

        expect(await tokens.retrieveAccess(), 'expired-access');
        expect(await tokens.retriveRefresh(), isNull);
        expect(await userMgr.retrive(), isNotNull);
      },
    );

    test(
      'refresh API 401 emits refreshFailed + sessionExpired without clearing',
      () async {
        await seedExpiredSession();

        AuthInterceptor.debugRefreshHttpClientAdapter = _ScriptedAdapter([
          _AdapterReply.json(statusCode: 401, body: {'error': 'invalid_grant'}),
        ]);

        var sessionExpiredCount = 0;
        var logoutCount = 0;
        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          // ignore: deprecated_member_use_from_same_package
          onLogout: () async => logoutCount++,
          onSessionExpired: () async => sessionExpiredCount++,
        );

        final outcome = await trigger401(
          interceptor,
          unauthorized401(path: '/me'),
        );

        expect(outcome.didPropagateError, isTrue);
        expect(sessionExpiredCount, 1);
        expect(logoutCount, 0);

        final types = events.map((e) => e.type).toList();
        expect(types, contains(AuthManagerEventType.refreshFailed));
        expect(types, contains(AuthManagerEventType.sessionExpired));
        expect(types, isNot(contains(AuthManagerEventType.loggedOut)));

        expect(await tokens.retrieveAccess(), 'expired-access');
        expect(await tokens.retriveRefresh(), 'stale-refresh');
        expect(await userMgr.retrive(), isNotNull);
      },
    );

    test(
      'refresh API returns 200 without token → notify, keep session',
      () async {
        await seedExpiredSession();

        AuthInterceptor.debugRefreshHttpClientAdapter = _ScriptedAdapter([
          _AdapterReply.json(statusCode: 200, body: {'ok': true}),
        ]);

        var sessionExpiredCount = 0;
        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async => sessionExpiredCount++,
        );

        final outcome = await trigger401(
          interceptor,
          unauthorized401(path: '/orders'),
        );

        expect(outcome.didPropagateError, isTrue);
        expect(sessionExpiredCount, 1);
        expect(
          events.map((e) => e.type),
          contains(AuthManagerEventType.sessionExpired),
        );
        expect(await tokens.retrieveAccess(), 'expired-access');
        expect(await tokens.retriveRefresh(), 'stale-refresh');
      },
    );

    test(
      'refresh network error notifies and does not clear tokens',
      () async {
        await seedExpiredSession();

        AuthInterceptor.debugRefreshHttpClientAdapter = _ScriptedAdapter([
          _AdapterReply.fail(
            DioException(
              requestOptions: RequestOptions(path: Configuration.refreshUrl),
              type: DioExceptionType.connectionTimeout,
              message: 'timeout',
            ),
          ),
        ]);

        var sessionExpiredCount = 0;
        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async => sessionExpiredCount++,
        );

        final outcome = await trigger401(
          interceptor,
          unauthorized401(path: '/cart'),
        );

        expect(outcome.didPropagateError, isTrue);
        expect(sessionExpiredCount, 1);
        expect(
          events.map((e) => e.type),
          containsAll([
            AuthManagerEventType.refreshFailed,
            AuthManagerEventType.sessionExpired,
          ]),
        );
        expect(await tokens.retrieveAccess(), 'expired-access');
        expect(await tokens.retriveRefresh(), 'stale-refresh');
      },
    );

    test('invokes Configuration callbacks, not Configuration.onLogout', () async {
      await seedExpiredSession(refresh: null);

      var configSessionExpired = 0;
      var configLogout = 0;
      String? configMessage;

      Configuration.onSessionExpired = () async => configSessionExpired++;
      Configuration.onLogout = () async => configLogout++;
      Configuration.onShowMessage = (msg) => configMessage = msg;

      final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
      final interceptor = AuthInterceptor(dio);

      await trigger401(
        interceptor,
        unauthorized401(path: '/protected'),
      );

      expect(configSessionExpired, 1);
      expect(configLogout, 0);
      expect(configMessage, contains('session has expired'));
    });

    test(
      'client may clearSession after notification',
      () async {
        await seedExpiredSession(refresh: null);

        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async {
            await AuthManager.instance.clearSession();
          },
        );

        await trigger401(
          interceptor,
          unauthorized401(path: '/protected'),
        );

        expect(await tokens.retrieveAccess(), isNull);
        expect(await tokens.retriveRefresh(), isNull);
        expect(await userMgr.retrive(), isNull);
        expect(
          events.map((e) => e.type),
          containsAll([
            AuthManagerEventType.sessionExpired,
            AuthManagerEventType.loggedOut,
          ]),
        );
      },
    );

    test(
      'client may ignore notification and keep session intact',
      () async {
        await seedExpiredSession();

        AuthInterceptor.debugRefreshHttpClientAdapter = _ScriptedAdapter([
          _AdapterReply.json(statusCode: 403, body: {'error': 'forbidden'}),
        ]);

        // Deliberately no clearSession in callbacks.
        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async {},
        );

        await trigger401(interceptor, unauthorized401(path: '/wallet'));

        expect(await tokens.retrieveAccess(), 'expired-access');
        expect(await tokens.retriveRefresh(), 'stale-refresh');
        expect(await userMgr.retrive(), isNotNull);
        expect(
          events.map((e) => e.type),
          isNot(contains(AuthManagerEventType.loggedOut)),
        );
      },
    );

    test(
      'concurrent 401s share one refresh and notify sessionExpired once',
      () async {
        await seedExpiredSession();

        AuthInterceptor.debugRefreshHttpClientAdapter = _ScriptedAdapter(
          [
            _AdapterReply.json(
              statusCode: 401,
              body: {'error': 'expired'},
              delay: const Duration(milliseconds: 50),
            ),
          ],
          repeatLast: true,
        );

        var sessionExpiredCount = 0;
        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async => sessionExpiredCount++,
        );

        final outcomes = await Future.wait([
          trigger401(interceptor, unauthorized401(path: '/a')),
          trigger401(interceptor, unauthorized401(path: '/b')),
          trigger401(interceptor, unauthorized401(path: '/c')),
        ]);

        expect(outcomes.every((o) => o.didPropagateError), isTrue);
        // Debounced — concurrent failures must not spam logout-style notifies.
        expect(sessionExpiredCount, 1);
        expect(
          events.where((e) => e.type == AuthManagerEventType.sessionExpired),
          hasLength(1),
        );
        expect(await tokens.retrieveAccess(), 'expired-access');
        expect(await tokens.retriveRefresh(), 'stale-refresh');
      },
    );

    test(
      '401 on refresh URL itself does not trigger refresh-failure flow',
      () async {
        await seedExpiredSession();

        var sessionExpiredCount = 0;
        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async => sessionExpiredCount++,
        );

        final outcome = await trigger401(
          interceptor,
          unauthorized401(path: Configuration.refreshUrl),
        );

        expect(outcome.didPropagateError, isTrue);
        expect(sessionExpiredCount, 0);
        expect(
          events.map((e) => e.type),
          isNot(contains(AuthManagerEventType.sessionExpired)),
        );
      },
    );

    test('non-401 errors do not notify sessionExpired', () async {
      await seedExpiredSession();

      var sessionExpiredCount = 0;
      final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
      final interceptor = AuthInterceptor(
        dio,
        onSessionExpired: () async => sessionExpiredCount++,
      );

      final req = RequestOptions(
        path: '/protected',
        extra: {'enableLogs': false},
      );
      final err = DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: 500),
        type: DioExceptionType.badResponse,
      );

      final outcome = await trigger401(interceptor, err);

      expect(outcome.didPropagateError, isTrue);
      expect(sessionExpiredCount, 0);
      expect(events, isEmpty);
      expect(await tokens.retrieveAccess(), 'expired-access');
    });

    test(
      'successful refresh retries request and does not notify expiry',
      () async {
        await seedExpiredSession();

        AuthInterceptor.debugRefreshHttpClientAdapter = _ScriptedAdapter([
          _AdapterReply.json(
            statusCode: 200,
            body: {
              'token': 'fresh-access',
              'refreshToken': 'fresh-refresh',
            },
          ),
        ]);

        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        // Main Dio must succeed on the retried original request.
        dio.httpClientAdapter = _ScriptedAdapter([
          _AdapterReply.json(statusCode: 200, body: {'data': 'ok'}),
        ]);

        var sessionExpiredCount = 0;
        final interceptor = AuthInterceptor(
          dio,
          onSessionExpired: () async => sessionExpiredCount++,
        );
        dio.interceptors.add(interceptor);

        final outcome = await trigger401(
          interceptor,
          unauthorized401(path: '/protected'),
        );

        expect(outcome.didResolve, isTrue);
        expect(outcome.response?.statusCode, 200);
        expect(sessionExpiredCount, 0);
        expect(
          events.map((e) => e.type),
          isNot(contains(AuthManagerEventType.sessionExpired)),
        );
        expect(await tokens.retrieveAccess(), 'fresh-access');
        expect(await tokens.retriveRefresh(), 'fresh-refresh');
      },
    );

    test(
      'sessionExpired event carries a descriptive error payload',
      () async {
        await seedExpiredSession(refresh: null);

        final dio = Dio(BaseOptions(baseUrl: Configuration.baseUrl));
        final interceptor = AuthInterceptor(dio);

        await trigger401(
          interceptor,
          unauthorized401(path: '/protected'),
        );

        final expired = events.firstWhere(
          (e) => e.type == AuthManagerEventType.sessionExpired,
        );
        expect(expired.error, isNotNull);
        expect(expired.error.toString(), contains('token refresh failed'));
      },
    );
  });
}

class _ErrorOutcome {
  final DioException? error;
  final Response<dynamic>? response;

  const _ErrorOutcome._({this.error, this.response});

  factory _ErrorOutcome.next(DioException e) => _ErrorOutcome._(error: e);
  factory _ErrorOutcome.resolved(Response<dynamic> r) =>
      _ErrorOutcome._(response: r);

  bool get didPropagateError => error != null;
  bool get didResolve => response != null;
}

class _RecordingErrorHandler extends ErrorInterceptorHandler {
  final void Function(DioException err) onNext;
  final void Function(Response<dynamic> response) onResolve;

  _RecordingErrorHandler({
    required this.onNext,
    required this.onResolve,
  });

  @override
  void next(DioException err) => onNext(err);

  @override
  void resolve(Response<dynamic> response) => onResolve(response);
}

class _AdapterReply {
  final int? statusCode;
  final Object? body;
  final DioException? exception;
  final Duration delay;

  const _AdapterReply._({
    this.statusCode,
    this.body,
    this.exception,
    this.delay = Duration.zero,
  });

  factory _AdapterReply.json({
    required int statusCode,
    required Object body,
    Duration delay = Duration.zero,
  }) =>
      _AdapterReply._(statusCode: statusCode, body: body, delay: delay);

  factory _AdapterReply.fail(DioException exception, {Duration delay = Duration.zero}) =>
      _AdapterReply._(exception: exception, delay: delay);
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._replies, {this.repeatLast = false});

  final List<_AdapterReply> _replies;
  final bool repeatLast;
  int _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_index >= _replies.length) {
      if (!repeatLast || _replies.isEmpty) {
        throw StateError(
          'No scripted reply left for ${options.method} ${options.uri}',
        );
      }
      _index = _replies.length - 1;
    }
    final reply = _replies[_index++];
    if (reply.delay > Duration.zero) {
      await Future<void>.delayed(reply.delay);
    }
    if (reply.exception != null) {
      throw reply.exception!;
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.statusCode!,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
