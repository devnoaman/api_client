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
    super.successStatusCodes = const [200],
  });

  final logger = BaseLogger();

  /// Returns `true` when [statusCode] is in [successStatusCodes].
  bool _isSuccess(int? statusCode) =>
      statusCode != null && successStatusCodes.contains(statusCode);

  /// Builds the [Options] for the Dio request, merging [Configuration.headers]
  /// with any caller-supplied [options] and setting the HTTP method.
  ///
  /// `enableLogs` is passed as a header so that [AuthInterceptor] can toggle
  /// request/response logging per-controller without it being sent to the server
  /// (the interceptor reads and removes it before forwarding the request).
  Options _buildOptions() {
    final baseHeaders = {
      ...Configuration.headers,
    };

    if (options == null) {
      return Options(
        method: method?.toStringName,
        headers: baseHeaders,
        extra: {'enableLogs': enableLogs ?? true},
      );
    }

    return options!.copyWith(
      method: method?.toStringName,
      headers: {
        ...options!.headers ?? Configuration.headers,
      },
      extra: {
        ...options!.extra ?? const <String, dynamic>{},
        'enableLogs': enableLogs ?? true,
      },
    );
  }

  @override
  Future<dynamic> call([Map<String, dynamic>? queryParameter]) async {
    final client = NetworkClient().dioClient;
    try {
      final response = await client.request(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,
        options: _buildOptions(),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      if (!_isSuccess(response.statusCode)) {
        return Failed(
          'Unexpected status code: ${response.statusCode}',
          StackTrace.current,
          null,
          response.data,
        );
      }
      return responseDecoder(response.data);
    } catch (e, s) {
      logger.error('Unexpected error on request to $path: $e');
      logger.error('stacktrace is: $s');
      return Failed(e, s, null, data);
    }
  }

  @override
  Future<ResponseState> callWithResult([
    Map<String, dynamic>? queryParameter,
  ]) async {
    final client = NetworkClient().dioClient;
    try {
      final response = await client.request(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,
        options: _buildOptions(),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      if (!_isSuccess(response.statusCode)) {
        return Failed(
          'Unexpected status code: ${response.statusCode}',
          StackTrace.current,
          null,
          response.data,
        );
      }
      return Success(responseDecoder(response.data));
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
