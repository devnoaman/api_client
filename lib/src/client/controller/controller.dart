import 'package:api_client/src/client/http_method.dart';
import 'package:dio/dio.dart' show Options, CancelToken, ProgressCallback;

import '../../../api_client.dart';

abstract class ApiController<T> {
  final String path;
  final dynamic data;
  final Map<String, dynamic>? queryParameters;
  final T Function(dynamic) responseDecoder;
  final bool? authenticated;
  final bool? enableLogs;
  final HTTPMethod? method;
  final Options? options;
  final CancelToken? cancelToken;
  final ProgressCallback? onReceiveProgress;

  /// The HTTP status codes that should trigger [responseDecoder].
  /// Defaults to `[200]`. Pass any list to override, e.g. `[200, 201, 202]`.
  final List<int> successStatusCodes;
  const ApiController({
    required this.path,
    this.data,
    this.queryParameters,
    required this.responseDecoder,
    this.authenticated = false,
    this.enableLogs = false,
    this.method = HTTPMethod.get,
    this.options,
    this.cancelToken,
    this.onReceiveProgress,
    this.successStatusCodes = const [200],
  });

  Future<dynamic> call([Map<String, dynamic>? queryParameter]);
  Future<ResponseState> callWithResult([Map<String, dynamic>? queryParameter]);
}
