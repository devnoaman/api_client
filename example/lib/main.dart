import 'package:api_client/api_client.dart';
import 'package:example/views/headlines/views/headline_view.dart';
import 'package:flutter/material.dart';

void main() {
  Configuration.baseUrl = 'https://newsapi.org/v2';
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  // 92e8da8600324b0e90709abf6e3d5c2c
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HeadlineView());
  }
}
