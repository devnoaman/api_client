import 'dart:developer';

import '../api_client.dart';
import 'client/http_method.dart';
import 'network_client.dart';
import 'token_mangament.dart';
import 'package:dio/dio.dart';




/// Abstract class representing an API endpoint.
///]
//
@Deprecated('Use EndpointImpl instead')
abstract class Endpoint<T> {
  AuthManager get authManager => AuthManager.instance;
  Future<bool> get isLogedIn async => await authManager.me() != null;

  final String path;
  Object? data;

  Map<String, dynamic>? queryParameters;

  /// Optional headers to be sent with the request.
  /// If not provided, the default headers will be used.
  /// Default headers include the Authorization header with the access token.
  // Map<String, dynamic>? headers;
  Options? options;
  HTTPMethod? method;

  /// Indicates whether the request requires authentication.
  /// If true, the Authorization header will be included with the access token.
  /// If false, the request will be made without authentication.
  /// Default is false.
  bool? authenticated = false;
  CancelToken? cancelToken;
  void Function(int, int)? onReceiveProgress;
  final T Function(dynamic data) responseDecoder;

  Endpoint({
    required this.path,
    this.data,
    this.queryParameters,

    required this.responseDecoder,
    this.authenticated = false,
    this.method = HTTPMethod.get,
    this.options,
  });

  /// Performs a GET request and uses the configured decoder.
  @Deprecated(
    'use [call]/[callWithResult] instead,change http method type via method param',
  )
  Future<T?> get() async {
    var tokern = TokensManager.instance;
    var accessToken = await tokern.retriveAccess();
    final client = NetworkClient().dioClient;
    client.options.headers.addAll({
      'Authorization': ' Bearer $accessToken',
      // ...?headers,
    });
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
    } catch (e, s) {
      log('Unexpected error on GET request to $path: $e');
      log('stacktrace to is: $s');
      return null;
    }
  }

  Future<dynamic> call([
    Map<String, dynamic>? queryParameter,
  ]) async {
    final client = NetworkClient().dioClient;
    var tokern = TokensManager.instance;
    var accessToken = await tokern.retriveAccess();
    if (authenticated ?? false) {
      client.options.headers.addAll({
        'Authorization': ' Bearer $accessToken',
        // ...?headers,
      });
    }
    try {
      final response = await client.request(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,

        options: options == null
            ? Options(
                method: method?.toStringName,
                headers: Configuration.headers,
              )
            : options?.copyWith(
                method: method?.toStringName,
                headers: options?.headers ?? Configuration.headers,
              ),

        //  Options(
        //   method: method?.toStringName,
        //   headers: Configuration.headers,
        // ),

        //  options?.copyWith(
        //   method: method?.toStringName,
        // ),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      if (response.statusCode == 200 && response.data != null) {
        return responseDecoder(response.data);
      }
      return response;
    } catch (e, s) {
      log('Unexpected error on GET request to $path: $e');
      log('stacktrace to is: $s');
      return null;
    }
  }

  Future<ResponseState> callWithResult([
    Map<String, dynamic>? queryParameter,
  ]) async {
    final client = NetworkClient().dioClient;
    var tokern = TokensManager.instance;
    var accessToken = await tokern.retriveAccess();
    if (authenticated ?? false) {
      client.options.headers.addAll({
        'Authorization': ' Bearer $accessToken',
      });
    }
    try {
      final response = await client.request(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,

        options: options == null
            ? Options(
                method: method?.toStringName,
                headers: Configuration.headers,
              )
            : options?.copyWith(
                method: method?.toStringName,
                headers: options?.headers ?? Configuration.headers,
              ),

        // Options(
        //   method: method?.toStringName,
        // ),

        //  options?.copyWith(
        //   method: method?.toStringName,
        // ),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      if (response.statusCode == 200 && response.data != null) {
        return Success(responseDecoder(response.data));
      }
      return Success(data);
    } on DioException catch (e, s) {
      log('Unexpected error on GET request to $path: $e');
      log('stacktrace to is: $s');
      return Failed(
        e,
        s,
        null,
        e.response?.data,
      );
    } catch (e, s) {
      log('Unexpected error on GET request to $path: $e');
      log('stacktrace to is: $s');
      return Failed(
        e,
        s,
        null,
        data,
      );
    }
  }
}
