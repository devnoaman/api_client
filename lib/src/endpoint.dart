import 'dart:developer';

import 'package:api_client/src/network_client.dart';
import 'package:dio/dio.dart';

abstract class Endpoint<T> {
  final String path;
  Object? data;
  Map<String, dynamic>? queryParameters;
  Options? options;
  CancelToken? cancelToken;
  void Function(int, int)? onReceiveProgress;
  final T Function(dynamic data) responseDecoder;

  Endpoint({
    required this.path,
    required this.responseDecoder,
  });

  /// Performs a GET request and uses the configured decoder.
  Future<T?> get() async {
    final client = NetworkClient().dioClient;
    try {
      final response = await client.get(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      if (response.statusCode == 200 && response.data != null) {
        return responseDecoder(response.data);
      }
      return null;
    } on DioException catch (e) {
      log('Dio error on GET request to $path: ${e.message}');
      return null;
    } catch (e) {
      log('Unexpected error on GET request to $path: $e');
      return null;
    }
  }
}
