import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';

class EndpointImpl<T> extends Endpoint<T> {
  EndpointImpl({
    required super.path,
    super.data,
    super.queryParameters,
    required super.responseDecoder,
    super.authenticated = false,
    super.method = HTTPMethod.get,
  });

  @override
  Future<dynamic> call([Map<String, dynamic>? queryParameter]) async {
    final client = NetworkClient().dioClient;
    final requestHeaders = Map<String, dynamic>.from(
      options?.headers ?? Configuration.headers,
    );
    final requestExtra = Map<String, dynamic>.from(options?.extra ?? {});

    if (authenticated ?? false) {
      requestExtra['authenticated'] = true;
      final accessToken = await TokensManager.instance.retrieveAccess();
      if (accessToken != null) {
        requestHeaders['Authorization'] = 'Bearer $accessToken';
      }
    } else {
      requestExtra['authenticated'] = false;
      requestHeaders.remove('Authorization');
      client.options.headers.remove('Authorization');
    }

    try {
      final response = await client.request(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,
        options: options == null
            ? Options(
                method: method?.toStringName,
                headers: requestHeaders,
                extra: requestExtra,
              )
            : options?.copyWith(
                method: method?.toStringName,
                headers: requestHeaders,
                extra: requestExtra,
              ),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      if (response.statusCode == 200 && response.data != null) {
        return responseDecoder(response.data);
      }
      return response;
    } catch (e, s) {
      logger.error('Unexpected error on request to $path: $e');
      logger.error('stacktrace is: $s');
      return null;
    }
  }

  @override
  Future<ResponseState> callWithResult([
    Map<String, dynamic>? queryParameter,
  ]) async {
    final client = NetworkClient().dioClient;
    final requestHeaders = Map<String, dynamic>.from(
      options?.headers ?? Configuration.headers,
    );
    final requestExtra = Map<String, dynamic>.from(options?.extra ?? {});

    if (authenticated ?? false) {
      requestExtra['authenticated'] = true;
      final accessToken = await TokensManager.instance.retrieveAccess();
      if (accessToken != null) {
        requestHeaders['Authorization'] = 'Bearer $accessToken';
      }
    } else {
      requestExtra['authenticated'] = false;
      requestHeaders.remove('Authorization');
      client.options.headers.remove('Authorization');
    }

    try {
      final response = await client.request(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,
        options: options == null
            ? Options(
                method: method?.toStringName,
                headers: requestHeaders,
                extra: requestExtra,
              )
            : options?.copyWith(
                method: method?.toStringName,
                headers: requestHeaders,
                extra: requestExtra,
              ),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      if (response.statusCode == 200 && response.data != null) {
        return Success(responseDecoder(response.data));
      }
      return Success(data);
    } on DioException catch (e, s) {
      logger.error('Unexpected error on request to $path: $e');
      logger.error('stacktrace is: $s');
      return Failed(e, s, null, e.response?.data);
    } catch (e, s) {
      logger.error('Unexpected error on request to $path: $e');
      logger.error('stacktrace is: $s');
      return Failed(e, s, null, data);
    }
  }
}
