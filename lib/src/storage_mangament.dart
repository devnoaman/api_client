import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef AuthenticationDecoder<T> = T Function(dynamic data);

class StorageManager {
  // Private constructor remains the same.
  StorageManager._();
  static final StorageManager instance = StorageManager._();

  static const String _userKey = 'user_data';
  static Future<void> Function()? onRemove;

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'user_db',
      publicKey: 'user_db',
    ),
  );
  static FlutterSecureStorage get storage => _storage;

  /// When [rememberMe] is `true` (default), user data is persisted to secure
  /// storage and survives app restarts. When `false`, data lives only in memory
  /// and is cleared when the app process ends.
  bool rememberMe = true;

  /// In-memory store used when [rememberMe] is `false`.
  String? _inMemoryData;

  Future<void> save(String value) async {
    if (rememberMe) {
      return await _storage.write(key: _userKey, value: value);
    } else {
      _inMemoryData = value;
    }
  }

  Future<void> remove() async {
    _inMemoryData = null;
    if (rememberMe) {
      return await _storage.delete(key: _userKey);
    }
  }

  Future<Map<String, dynamic>?> retrive() async {
    final String? userJson =
        rememberMe ? await _storage.read(key: _userKey) : _inMemoryData;
    if (userJson == null) {
      return null;
    }
    return jsonDecode(userJson) as Map<String, dynamic>;
  }
}
