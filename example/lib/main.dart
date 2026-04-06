import 'package:api_client/api_client.dart';
import 'package:example/features/login/presentation/login_view.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:super_app_bridge/super_app_bridge.dart';
import 'package:super_app_common/models/app_config.dart';

void main() {
  // ── Test server connection ──────────────────────────────────────────────
  // Run: node test_server/server.js  (from the api_client root)
  // iOS simulator  → use 127.0.0.1
  // Android emulator → use 10.0.2.2
  Configuration.baseUrl = 'http://127.0.0.1:3000';

  // The test server returns { "accessToken": "...", "refreshToken": "..." }
  Configuration.tokenKeyName = 'accessToken';
  Configuration.refreshTokenKeyName = 'refreshToken';

  // Token refresh endpoint (matches server.js)
  Configuration.refreshUrl = '/auth/refresh';

  Configuration.enableLogs = true;

  final shellService = getPlatformShellService(apiKey: 'apiKey');

  runApp(ProviderScope(child: MainApp(shellService: shellService)));
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.shellService});

  final ShellService shellService;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  AppConfig? config;
  bool? isShell;
  @override
  void initState() {
    // final service = ShellService();
    _initializeService(widget.shellService);
    super.initState();
  }

  Future<void> _initializeService(ShellService service) async {
    config = await service.getConfiguration();
    await service.verify();
    isShell = config != null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LoginView());
  }
}
