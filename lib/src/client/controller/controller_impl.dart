import 'dart:typed_data';

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
    super.authenticated = true,
    super.method = HTTPMethod.get,
    super.successStatusCodes = const [200],
    super.cancelToken,
    super.onReceiveProgress,
    super.streamFormat = StreamFormat.sse,
    super.chunkDecoder,
    super.streamReceiveTimeout,
  });

  final logger = BaseLogger();

  /// Returns `true` when [statusCode] is in [successStatusCodes].
  bool _isSuccess(int? statusCode) =>
      statusCode != null && successStatusCodes.contains(statusCode);

  T _decodeChunk(StreamEventFrame frame) {
    final decoder = chunkDecoder;
    if (decoder != null) return decoder(frame);
    return responseDecoder(frame.data);
  }

  /// Builds the [Options] for the Dio request, merging [Configuration.headers]
  /// with any caller-supplied [options] and setting the HTTP method.
  ///
  /// `enableLogs` / `authenticated` are passed in [Options.extra] for
  /// [AuthInterceptor] / logging mixins.
  Options _buildOptions({bool streaming = false}) {
    final baseHeaders = {...Configuration.headers};
    if (streaming) {
      baseHeaders['Accept'] = streamFormat.acceptHeader;
    }

    final Options built;
    if (options == null) {
      built = Options(
        method: method?.toStringName,
        headers: baseHeaders,
        extra: {
          'enableLogs': enableLogs ?? true,
          'authenticated': authenticated ?? true,
        },
      );
    } else {
      built = options!.copyWith(
        method: method?.toStringName,
        headers: {
          ...baseHeaders,
          ...?options!.headers,
          if (streaming) 'Accept': streamFormat.acceptHeader,
        },
        extra: {
          ...options!.extra ?? const <String, dynamic>{},
          'enableLogs': enableLogs ?? true,
          'authenticated': authenticated ?? false,
        },
      );
    }

    if (!streaming) return built;

    return built.copyWith(
      responseType: ResponseType.stream,
      // Duration.zero disables the receive timeout for long-lived streams.
      receiveTimeout: streamReceiveTimeout ?? Duration.zero,
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

  /// Streams decoded chunks of type [T] until the connection closes or
  /// [cancelToken] is cancelled.
  ///
  /// Errors are surfaced as stream errors. Prefer [streamWithResult] for UI
  /// code that wants typed failure states.
  ///
  /// Mid-stream HTTP 401 is **not** retried — the stream fails and
  /// [AuthInterceptor] may emit `sessionExpired` separately.
  Stream<T> stream([Map<String, dynamic>? queryParameter]) async* {
    await for (final event in streamWithResult(queryParameter)) {
      switch (event) {
        case StreamChunk<T>(:final data):
          yield data;
        case StreamDone<T>():
          return;
        case StreamFailed<T>(:final error, :final stackTrace):
          Error.throwWithStackTrace(
            error,
            stackTrace ?? StackTrace.current,
          );
      }
    }
  }

  /// Streams typed [StreamResponseState] events for UI `switch` matching.
  Stream<StreamResponseState<T>> streamWithResult([
    Map<String, dynamic>? queryParameter,
  ]) async* {
    final client = NetworkClient().dioClient;
    try {
      final response = await client.request<ResponseBody>(
        path,
        data: data,
        queryParameters: queryParameter ?? queryParameters,
        options: _buildOptions(streaming: true),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      if (!_isSuccess(response.statusCode)) {
        yield StreamFailed<T>(
          'Unexpected status code: ${response.statusCode}',
          StackTrace.current,
          null,
          null,
        );
        return;
      }

      final body = response.data;
      if (body == null) {
        yield StreamFailed<T>(
          'Streaming response body was null',
          StackTrace.current,
          null,
          null,
        );
        return;
      }

      var sawDoneMarker = false;
      final parser = StreamBodyParser(
        format: streamFormat,
        onDoneMarker: () => sawDoneMarker = true,
      );

      final byteStream = body.stream.map<List<int>>(
        (Uint8List chunk) => chunk,
      );

      await for (final frame in parser.parse(byteStream)) {
        if (cancelToken?.isCancelled ?? false) break;
        try {
          yield StreamChunk<T>(
            _decodeChunk(frame),
            event: frame.event,
            id: frame.id,
          );
        } catch (e, s) {
          logger.error('Chunk decode error on $path: $e');
          yield StreamFailed<T>(e, s, null, frame);
          return;
        }
      }

      yield StreamDone<T>();
      if (sawDoneMarker && (enableLogs ?? false)) {
        logger.debug('SSE [DONE] received for $path');
      }
    } on DioException catch (e, s) {
      if (CancelToken.isCancel(e)) {
        yield StreamDone<T>();
        return;
      }
      logger.error('Stream error on request to $path: $e');
      yield StreamFailed<T>(e, s, null, e.response?.data);
    } catch (e, s) {
      logger.error('Unexpected stream error on request to $path: $e');
      yield StreamFailed<T>(e, s, null, data);
    }
  }
}
