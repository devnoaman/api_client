import 'dart:developer';
import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';

base class BaseController<T> extends ApiController<T> {
  BaseController({
    required super.path,
    super.data,
    super.queryParameters,
    super.options,
    required super.responseDecoder,
    super.authenticated = false,
    super.method = HTTPMethod.get,
  });

  @override
  Future<dynamic> call([Map<String, dynamic>? queryParameter]) async {
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
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      if (response.statusCode == 200 && response.data != null) {
        return responseDecoder(response.data);
      }
      return response;
    } catch (e, s) {
      log('Unexpected error on request to $path: $e');
      log('stacktrace is: $s');
      return null;
    }
  }

  @override
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
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      if (response.statusCode == 200 && response.data != null) {
        return Success(responseDecoder(response.data));
      }
      return Success(data);
    } on DioException catch (e, s) {
      log('Unexpected error on request to $path: $e');
      log('stacktrace is: $s');
      return Failed(e, s, null, e.response?.data);
    } catch (e, s) {
      log('Unexpected error on request to $path: $e');
      log('stacktrace is: $s');
      return Failed(e, s, null, data);
    }
  }
}
