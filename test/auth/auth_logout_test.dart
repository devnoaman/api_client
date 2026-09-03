import 'dart:convert';
import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Configuration.baseUrl = 'https://api.example.com';
  });

  group('TokensManager cleanup tests', () {
    test('deleteAll removes access and refresh tokens when rememberMe is true', () async {
      final manager = TokensManager.instance;
      manager.rememberMe = true;

      await manager.saveAccess('access-token-123');
      await manager.saveRefresh('refresh-token-456');

      expect(await manager.retrieveAccess(), equals('access-token-123'));
      expect(await manager.retriveRefresh(), equals('refresh-token-456'));

      await manager.deleteAll();

      expect(await manager.retrieveAccess(), isNull);
      expect(await manager.retriveRefresh(), isNull);

      final allTokens = await manager.retriveAll();
      expect(allTokens?['access'], isNull);
      expect(allTokens?['refresh'], isNull);
    });

    test('deleteAll removes tokens even when rememberMe is false', () async {
      final manager = TokensManager.instance;
      // First save with rememberMe = true
      manager.rememberMe = true;
      await manager.saveAccess('persisted-token');
      await manager.saveRefresh('persisted-refresh');

      // Then change to rememberMe = false
      manager.rememberMe = false;
      await manager.saveAccess('memory-only-token');

      // Now call deleteAll
      await manager.deleteAll();

      expect(await manager.retrieveAccess(), isNull);
      expect(await manager.retriveRefresh(), isNull);

      final allTokens = await manager.retriveAll();
      expect(allTokens?['access'], isNull);
      expect(allTokens?['refresh'], isNull);
    });

    test('removeAccess and removeRefresh remove tokens individually', () async {
      final manager = TokensManager.instance;
      manager.rememberMe = true;

      await manager.saveAccess('access-1');
      await manager.saveRefresh('refresh-1');

      await manager.removeAccess();
      expect(await manager.retrieveAccess(), isNull);
      expect(await manager.retriveRefresh(), equals('refresh-1'));

      await manager.removeRefresh();
      expect(await manager.retriveRefresh(), isNull);
    });
  });

  group('StorageManager cleanup tests', () {
    test('remove completely clears user data when rememberMe is true', () async {
      final storage = StorageManager.instance;
      storage.rememberMe = true;

      await storage.save(jsonEncode({'id': 1, 'name': 'John'}));
      expect(await storage.retrive(), isNotNull);

      await storage.remove();
      expect(await storage.retrive(), isNull);
      expect(await storage.retrieve(), isNull);
    });

    test('remove completely clears user data when rememberMe is false', () async {
      final storage = StorageManager.instance;
      storage.rememberMe = false;

      await storage.save(jsonEncode({'id': 2, 'name': 'Jane'}));
      expect(await storage.retrive(), isNotNull);

      await storage.remove();
      expect(await storage.retrive(), isNull);
    });
  });

  group('AuthManager logout and clearSession tests', () {
    test('clearSession completely removes access, refresh, and user data', () async {
      final auth = AuthManager.instance;
      final tokens = TokensManager.instance;
      final userMgr = StorageManager.instance;

      tokens.rememberMe = true;
      userMgr.rememberMe = true;

      await tokens.saveAccess('access-xyz');
      await tokens.saveRefresh('refresh-xyz');
      await userMgr.save(jsonEncode({'email': 'test@example.com'}));

      expect(await tokens.retrieveAccess(), equals('access-xyz'));
      expect(await tokens.retriveRefresh(), equals('refresh-xyz'));
      expect(await auth.me(), isNotNull);

      bool loggedOutEmitted = false;
      final sub = auth.authManagerStream.listen((event) {
        if (event.type == AuthManagerEventType.loggedOut) {
          loggedOutEmitted = true;
        }
      });

      await auth.clearSession();

      expect(await tokens.retrieveAccess(), isNull);
      expect(await tokens.retriveRefresh(), isNull);
      expect(await auth.me(), isNull);
      expect(loggedOutEmitted, isTrue);

      await sub.cancel();
    });

    test('logout with callApi=false completely removes all tokens and user data', () async {
      final auth = AuthManager.instance;
      final tokens = TokensManager.instance;
      final userMgr = StorageManager.instance;

      await tokens.saveAccess('access-abc');
      await tokens.saveRefresh('refresh-abc');
      await userMgr.save(jsonEncode({'user': 'Alice'}));

      expect(await tokens.retrieveAccess(), equals('access-abc'));
      expect(await auth.me(), isNotNull);

      await auth.logout(
        path: '/auth/logout',
        decoder: (d) => d,
        callApi: false,
      );

      expect(await tokens.retrieveAccess(), isNull);
      expect(await tokens.retriveRefresh(), isNull);
      expect(await auth.me(), isNull);
    });

    test('AuthInterceptor triggers callbacks and emits sessionExpired on refresh failure', () async {
      final tokens = TokensManager.instance;
      final userMgr = StorageManager.instance;

      await tokens.saveAccess('expired-access');
      // No refresh token available, so refresh will fail
      await tokens.removeRefresh();
      await userMgr.save(jsonEncode({'user': 'Bob'}));

      bool onSessionExpiredCalled = false;
      bool onLogoutCalled = false;
      String? shownMessage;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      final interceptor = AuthInterceptor(
        dio,
        onLogout: () async => onLogoutCalled = true,
        onSessionExpired: () async => onSessionExpiredCalled = true,
        onShowMessage: (msg) => shownMessage = msg,
      );

      final events = <AuthManagerEventType>[];
      final sub = AuthManager.instance.authManagerStream.listen((event) {
        events.add(event.type);
      });

      // Simulate 401 error reaching interceptor
      final reqOptions = RequestOptions(
        path: '/protected/resource',
        headers: {'Authorization': 'Bearer expired-access'},
        extra: {'authenticated': true},
      );
      final dioErr = DioException(
        requestOptions: reqOptions,
        response: Response(requestOptions: reqOptions, statusCode: 401),
      );

      var nextCalled = false;
      final handler = _TestErrorHandler((_) => nextCalled = true);
      interceptor.onError(dioErr, handler);

      // Wait for async refresh and failure handling
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(nextCalled, isTrue);
      expect(onSessionExpiredCalled, isTrue);
      expect(onLogoutCalled, isTrue);
      expect(shownMessage, contains('session has expired'));
      expect(events, contains(AuthManagerEventType.sessionExpired));
      expect(await tokens.retrieveAccess(), isNull);
      expect(await userMgr.retrive(), isNull);

      await sub.cancel();
    });

    test('NetworkClient getters allow accessing Dio via dio.instance, dio, client, and instance.dioClient', () {
      NetworkClient(baseUrl: 'https://api.example.com');

      // 1. NetworkClient.dio.instance (requested by user)
      expect(NetworkClient.dio.instance, isA<Dio>());

      // 2. NetworkClient.dio
      expect(NetworkClient.dio, isA<Dio>());

      // 3. NetworkClient.client
      expect(NetworkClient.client, isA<Dio>());

      // 4. NetworkClient.instance.dioClient
      expect(NetworkClient.instance.dioClient, isA<Dio>());

      // 5. NetworkClient.instance
      expect(NetworkClient.instance, isA<NetworkClient>());

      // All point to the exact same Dio instance
      expect(identical(NetworkClient.dio.instance, NetworkClient.dio), isTrue);
      expect(identical(NetworkClient.dio.instance, NetworkClient.instance.dioClient), isTrue);
      expect(identical(NetworkClient.client, NetworkClient.dio), isTrue);
    });
  });
}

class _TestErrorHandler extends ErrorInterceptorHandler {
  final void Function(DioException err) onNext;
  _TestErrorHandler(this.onNext);

  @override
  void next(DioException err) {
    onNext(err);
  }
}
