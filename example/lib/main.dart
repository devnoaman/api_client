import 'package:api_client/api_client.dart';
import 'package:example/features/login/presentation/login_view.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  Configuration.baseUrl = 'http://localhost:5048/api';
  runApp(ProviderScope(child: const MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  // 92e8da8600324b0e90709abf6e3d5c2c
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LoginView());
  }
}
