import 'package:api_client/api_client.dart';
import 'package:example/features/login/presentation/login_view.dart';
import 'package:example/views/users/users_view.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // WidgetsFlutterBinding.ensureInitialized()

  // ── Test server connection ──────────────────────────────────────────────
  // Run: node test_server/server.js  (from the api_client root)
  // iOS simulator  → use 127.0.0.1
  // Android emulator → use 10.0.2.2
  // Web (Flutter web) → use localhost
  Configuration.baseUrl = 'http://localhost:3000';

  // The test server returns { "accessToken": "...", "refreshToken": "..." }
  Configuration.tokenKeyName = 'accessToken';
  Configuration.refreshTokenKeyName = 'refreshToken';

  // Token refresh endpoint (matches server.js)
  Configuration.refreshUrl = '/auth/refresh';

  Configuration.enableLogs = true;

  // ✅ Pre-load any previously saved tokens from secure storage into memory.
  // This avoids the WebCrypto race condition on web where the first
  // concurrent read can throw OperationError before the key is ready.
  await TokensManager.instance.initialize();

  // Initialize the network client now that configuration is set.
  NetworkClient(baseUrl: Configuration.baseUrl);

  // Check if there is an existing session
  final bool hasSession = await AuthManager.instance.me() != null;

  runApp(ProviderScope(child: MainApp(hasSession: hasSession)));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.hasSession});

  final bool hasSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'api_client Demo',
      home: hasSession ? const UsersView() : const LoginView(),
    );
  }
}
