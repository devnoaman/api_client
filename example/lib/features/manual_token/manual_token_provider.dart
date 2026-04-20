import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:example/features/users/controllers/user_controllers.dart';
import 'package:example/features/users/models/user_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ─── State ─────────────────────────────────────────────────────────────────

class ManualTokenState {
  final bool isLoading;
  final String? savedToken;
  final String? error;
  final String? log;
  final List<UserModel>? users;

  const ManualTokenState({
    this.isLoading = false,
    this.savedToken,
    this.error,
    this.log,
    this.users,
  });

  ManualTokenState copyWith({
    bool? isLoading,
    Object? savedToken = _absent,
    Object? error = _absent,
    Object? log = _absent,
    Object? users = _absent,
  }) =>
      ManualTokenState(
        isLoading: isLoading ?? this.isLoading,
        savedToken: identical(savedToken, _absent) ? this.savedToken : savedToken as String?,
        error: identical(error, _absent) ? this.error : error as String?,
        log: identical(log, _absent) ? this.log : log as String?,
        users: identical(users, _absent) ? this.users : users as List<UserModel>?,
      );

  static const _absent = Object();
}

// ─── Notifier ──────────────────────────────────────────────────────────────

final manualTokenProvider =
    NotifierProvider<ManualTokenNotifier, ManualTokenState>(ManualTokenNotifier.new);

class ManualTokenNotifier extends Notifier<ManualTokenState> {
  @override
  ManualTokenState build() => const ManualTokenState();

  /// Step 1 — Call POST /auth/token-only on the test server.
  /// This returns ONLY an accessToken (no AuthManager involved).
  /// We then manually save it with TokensManager.instance.saveAccess().
  Future<void> fetchAndSaveToken(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null, log: null, users: null, savedToken: null);

    try {
      // Use a raw Dio call so AuthManager is NOT involved — this is the
      // exact scenario the user was debugging.
      final dio = NetworkClient().dioClient;
      final response = await dio.post(
        '/auth/token-only',
        data: {'email': email, 'password': password},
        options: Options(extra: {'enableLogs': true}),
      );

      final token = response.data['accessToken'] as String?;
      if (token == null) {
        state = state.copyWith(isLoading: false, error: 'Server returned no accessToken');
        return;
      }

      // ✅ Manual save — bypassing AuthManager completely.
      await TokensManager.instance.saveAccess(token);

      state = state.copyWith(
        isLoading: false,
        savedToken: token,
        log: '✅ Token saved via TokensManager.saveAccess()\n'
            '   Token: ${token.substring(0, 12)}…',
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'DioError: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  /// Step 2 — Call GET /users (protected) using the manually saved token.
  /// The AuthInterceptor should pick it up automatically from TokensManager.
  Future<void> callProtectedEndpoint() async {
    if (state.savedToken == null) {
      state = state.copyWith(error: 'Save a token first (Step 1)');
      return;
    }
    state = state.copyWith(isLoading: true, error: null, users: null);

    final result = await GetUsersController().callWithResult();
    switch (result) {
      case Success(data: final d):
        state = state.copyWith(
          isLoading: false,
          users: d as List<UserModel>,
          log: '${state.log}\n\n✅ GET /users succeeded — token was picked up automatically',
        );
      case Failed(error: final e, stackTrace: final st):
        state = state.copyWith(
          isLoading: false,
          error: 'Protected endpoint failed: $e',
          log: '${state.log}\n\n❌ GET /users failed — $e',
        );
    }
  }

  /// Step 3 — Clear the token and verify the protected endpoint now fails.
  Future<void> clearToken() async {
    await TokensManager.instance.deleteAll();
    state = state.copyWith(
      savedToken: null,
      users: null,
      log: '🗑 Token cleared. Step 2 should now fail with 401.',
      error: null,
    );
  }
}
