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

  /// Wire format used by [BaseController.stream] / [BaseController.streamWithResult].
  final StreamFormat streamFormat;

  /// Decodes each streamed [StreamEventFrame] into [T].
  ///
  /// The frame carries the SSE `event:` name (e.g. `meta`, `delta`, `done`)
  /// plus the JSON `data` map. When null, [responseDecoder] is called with
  /// [StreamEventFrame.data] only (event name is dropped).
  final T Function(StreamEventFrame frame)? chunkDecoder;

  /// Receive timeout for streaming requests. Defaults to [Duration.zero]
  /// (no timeout) so long-lived agent streams are not killed.
  final Duration? streamReceiveTimeout;

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
    this.streamFormat = StreamFormat.sse,
    this.chunkDecoder,
    this.streamReceiveTimeout,
  });

  Future<dynamic> call([Map<String, dynamic>? queryParameter]);
  Future<ResponseState> callWithResult([Map<String, dynamic>? queryParameter]);
}
