import 'package:api_client/api_client.dart';
import 'package:example/features/login/presentation/login_view.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  // ── Test server connection ──────────────────────────────────────────────
  // Run: node test_server/server.js  (from the api_client root)
  // iOS simulator  → use 127.0.0.1
  // Android emulator → use 10.0.2.2
  Configuration.baseUrl = 'http://127.0.0.1:3000';

  // The test server returns { "accessToken": "...", "refreshToken": "..." }
  Configuration.tokenKeyName        = 'accessToken';
  Configuration.refreshTokenKeyName = 'refreshToken';

  // Token refresh endpoint (matches server.js)
  Configuration.refreshUrl = '/auth/refresh';

  Configuration.enableLogs = true;

  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LoginView());
  }
}
