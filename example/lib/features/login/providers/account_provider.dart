import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final authProvider = StateNotifierProvider<LoginNotifier, String>((ref) {
  return LoginNotifier(ref);
});

class LoginNotifier extends StateNotifier<String> {
  final Ref ref;

  LoginNotifier(this.ref) : super('');
  login(String userName, String password, BuildContext context) async {
    // state = state.copyWith(loading: true);

    var manager = AuthManager.instance;
    try {
      var data = await manager.login(
        path: '/Auth/login',
        data: {"username": userName, "password": password},
        decoder: (data) {
          print(data);

          state = 'SplashView.route';
        },
      );
      ref.read(meProvider.notifier).me();
    } catch (e, s) {
      print(e);
      print(s);
    }
  }
}

final meProvider = StateNotifierProvider.autoDispose<MeNotifier, String>((ref) {
  return MeNotifier(ref);
});

class MeNotifier extends StateNotifier<String> {
  final Ref ref;

  MeNotifier(this.ref) : super('') {
    me();
  }

  me() async {
    var manager = TokensManager.instance;
    try {
      var data = await manager.retriveAccess();
      state = data ?? 'not found';
    } catch (e, s) {
      print(e);
      print(s);
    }
  }
}
