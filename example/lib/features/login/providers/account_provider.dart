import 'package:api_client/api_client.dart';
import 'package:example/features/users/controllers/user_controllers.dart';
import 'package:example/features/users/models/user_model.dart';
import 'package:example/views/users/users_view.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ─── Auth Provider ─────────────────────────────────────────────────────────

final authProvider =
    AsyncNotifierProvider<LoginNotifier, void>(LoginNotifier.new);

class LoginNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> login(
    String email,
    String password,
    BuildContext context,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await AuthManager.instance.login(
        path: '/auth/login',
        data: {'email': email, 'password': password},
        decoder: (data) => data,
      );
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UsersView()),
        );
      }
    });
  }

  Future<void> logout() async {
    await AuthManager.instance.logout(
      path: '/auth/logout',
      callApi: true,
      decoder: (data) => data,
    );
    state = const AsyncData(null);
  }
}

// ─── Users Provider ────────────────────────────────────────────────────────

final usersProvider =
    AsyncNotifierProvider<UsersNotifier, List<UserModel>>(UsersNotifier.new);

class UsersNotifier extends AsyncNotifier<List<UserModel>> {
  @override
  Future<List<UserModel>> build() => _fetch();

  Future<List<UserModel>> _fetch() async {
    final result = await GetUsersController().callWithResult();
    return switch (result) {
      Success(data: final d) => d as List<UserModel>,
      Failed(error: final e, stackTrace: final st) => throw AsyncError(e, st!),
    };
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> create(String name, String email) async {
    final result =
        await CreateUserController(name: name, email: email).callWithResult();
    if (result is Success) await load();
  }
}

// ─── Ping Provider ────────────────────────────────────────────────────────

final pingProvider = FutureProvider<String>((ref) async {
  final result = await PingController().callWithResult();
  return switch (result) {
    Success(data: final d) =>
      'Server: ${(d as Map)['message']} @ ${d['timestamp']}',
    Failed(error: final e) => 'Ping failed: $e',
  };
});
