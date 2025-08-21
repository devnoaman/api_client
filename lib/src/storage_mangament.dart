import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef AuthenticationDecoder<T> = T Function(dynamic data);

class StorageManager {
  // Static private instance is now of a non-generic type.
  // static AuthManager _instance;

  // Private constructor remains the same.
  StorageManager._();
  // static AuthManager<T> instance = _instance<T>;
  static final StorageManager instance = StorageManager._();

  // The decoder is part of the instance state.
  // final AuthDecoder<T> responseDecoder;
  static const String _userKey = 'user_data';
  static Future<void> Function()? onRemove;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static FlutterSecureStorage get storage => _storage;
  Future<void> save(String value) async {
    return await _storage.write(key: _userKey, value: value);
  }

  Future<void> remove() async {
    return await _storage.delete(key: _userKey);
  }

  Future<Map<String, dynamic>?> retrive() async {
    final String? userJson = await _storage.read(key: _userKey);
    if (userJson == null) {
      return null;
    }
    return jsonDecode(userJson) as Map<String, dynamic>;
  }
}
