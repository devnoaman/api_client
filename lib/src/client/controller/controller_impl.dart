import 'package:api_client/api_client.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:dio/dio.dart';

base class BaseController<T> extends ApiController<T> {
  BaseController({
    required super.path,
    super.data,
    super.queryParameters,
    super.options,
    required super.responseDecoder,
    super.enableLogs = true,
    super.authenticated = false,
    super.method = HTTPMethod.get,
  });
  final logger = BaseLogger();

  @override
  Future<dynamic> call([Map<String, dynamic>? queryParameter]) async {
    final client = NetworkClient().dioClient;
    var token = TokensManager.instance;
    var accessToken = await token.retrieveAccess();
    if (authenticated ?? false) {
      client.options.headers.addAll({
        'Authorization': ' Bearer $accessToken',
        'enableLogs': enableLogs ?? true,
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
                headers: {
                  ...Configuration.headers,
                  'enableLogs': enableLogs ?? true,
                },
              )
            : options?.copyWith(
                method: method?.toStringName,
                headers: {
                  ...options?.headers ?? Configuration.headers,
                  'enableLogs': enableLogs ?? true,
                },
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
    var tokern = TokensManager.instance;
    var accessToken = await tokern.retrieveAccess();
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
