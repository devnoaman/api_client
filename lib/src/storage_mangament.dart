import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';


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
    _inMemoryData = value;
    if (rememberMe) {
      return await _storage.write(key: _userKey, value: value);
    }
  }

  /// Completely removes user data from both in-memory cache and persistent storage.
  Future<void> remove() async {
    _inMemoryData = null;
    try {
      await _storage.delete(key: _userKey);
      await _storage.deleteAll();
    } catch (_) {}
  }

  /// Alias for [remove].
  Future<void> clear() => remove();

  /// Alias for [remove].
  Future<void> deleteAll() => remove();

  Future<Map<String, dynamic>?> retrive() async {
    String? userJson = _inMemoryData;
    if (userJson == null && rememberMe) {
      try {
        userJson = await _storage.read(key: _userKey);
      } catch (_) {}
    }
    if (userJson == null) {
      return null;
    }
    try {
      return jsonDecode(userJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Alias for [retrive] with standard spelling.
  Future<Map<String, dynamic>?> retrieve() => retrive();
}
