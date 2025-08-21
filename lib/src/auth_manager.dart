// import 'dart:convert';
// import 'dart:developer';

// import 'package:api_client/src/network_client.dart';
// import 'package:dio/dio.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// typedef AuthDecoder<T> =
//     Future<T> Function(
//       dynamic data,
//       Future<void> Function(String formattedUser) onSave,
//       void Function() onRemove,
//     );

// class AuthManager<T> {
//   // Static private instance is now of a non-generic type.
//   static AuthManager? _instance;

//   // Private constructor remains the same.
//   AuthManager._(this.responseDecoder);

//   // The decoder is part of the instance state.
//   final AuthDecoder<T> responseDecoder;
//   static const String _userKey = 'user_model';

//   // 1. The static getter is now a generic method.
//   // It checks the type when you call it.
//   static AuthManager<T> instance<T>() {
//     if (_instance == null) {
//       throw Exception(
//         "AuthManager has not been initialized. Call AuthManager.setup() first.",
//       );
//     }
//     // We cast to the specific generic type requested.
//     return _instance! as AuthManager<T>;
//   }

//   // 2. The setup method is also made generic.
//   // This ensures the instance is created with the correct type.
//   static void setup<T>({required AuthDecoder<T> decoder}) {
//     // Only initialize if it hasn't been already.
//     _instance ??= AuthManager<T>._(decoder);
//   }

//   static const FlutterSecureStorage _storage = FlutterSecureStorage();

//   // Your methods can now use the responseDecoder.
//   Future<T?> login({
//     required String path,
//     required Map<String, dynamic> data,
//   }) async {
//     final client = NetworkClient().dioClient;
//     try {
//       var response = await client.post(path, data: data);

//       if (response.statusCode == 200 && response.data != null) {
//         return responseDecoder(response.data, (user) async {
//           // calls save logic

//           await _storage.write(key: _userKey, value: user);
//         }, () {});
//       }
//       return null;
//     } on DioException catch (e) {
//       log('Dio error on GET request to $path: ${e.message}');
//       return null;
//     } catch (e) {
//       log('Unexpected error on GET request to $path: $e');
//       return null;
//     }
//   }

//   logout({String? path}) {
//     final client = NetworkClient().dioClient;
//   }

//   Future<Map<String, dynamic>?> me({String? path}) async {
//     // final client = NetworkClient().dioClient;
//     final String? userJson = await _storage.read(key: _userKey);
//     if (userJson == null) {
//       return null;
//     }
//     return jsonDecode(userJson) as Map<String, dynamic>;
//   }
// }
