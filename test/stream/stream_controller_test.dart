import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    Configuration.baseUrl = 'https://api.example.com';
    Configuration.onSessionExpired = null;
    Configuration.onLogout = null;
    Configuration.onShowMessage = null;
    // Ensure singleton is initialized for adapter swap.
    NetworkClient(baseUrl: Configuration.baseUrl);
  });

  tearDown(() {
    // Restore a no-op adapter so later tests don't see leftover replies.
    NetworkClient.instance.dioClient.httpClientAdapter = _ScriptedStreamAdapter([]);
  });

  test('streamWithResult yields SSE chunks then StreamDone', () async {
    final body = [
      'event: delta',
      'data: {"delta":"A"}',
      '',
      'event: delta',
      'data: {"delta":"B"}',
      '',
      'event: done',
      'data: {}',
      '',
      'data: [DONE]',
      '',
    ].join('\n');

    NetworkClient.instance.dioClient.httpClientAdapter = _ScriptedStreamAdapter([
      _StreamReply(
        statusCode: 200,
        contentType: 'text/event-stream',
        chunks: [utf8.encode(body)],
      ),
    ]);

    final controller = _DeltaStreamController(
      format: StreamFormat.sse,
    );

    final events = await controller.streamWithResult().toList();
    expect(events.length, 4);
    expect(events[0], isA<StreamChunk<String>>());
    expect((events[0] as StreamChunk<String>).data, 'A');
    expect((events[0] as StreamChunk<String>).event, 'delta');
    expect((events[1] as StreamChunk<String>).data, 'B');
    expect((events[2] as StreamChunk<String>).event, 'done');
    expect(events[3], isA<StreamDone<String>>());
  });

  test('streamWithResult yields NDJSON chunks', () async {
    NetworkClient.instance.dioClient.httpClientAdapter = _ScriptedStreamAdapter([
      _StreamReply(
        statusCode: 200,
        contentType: 'application/x-ndjson',
        chunks: [
          utf8.encode('{"delta":"one"}\n'),
          utf8.encode('{"delta":"two"}\n'),
        ],
      ),
    ]);

    final controller = _DeltaStreamController(format: StreamFormat.ndjson);
    final chunks = await controller.stream().toList();
    expect(chunks, ['one', 'two']);
  });

  test('cancelToken stops stream early as StreamDone', () async {
    final cancel = CancelToken();
    final controller = StreamController<List<int>>();

    NetworkClient.instance.dioClient.httpClientAdapter = _LiveStreamAdapter(
      statusCode: 200,
      contentType: 'application/x-ndjson',
      byteStream: controller.stream,
    );

    final chat = _DeltaStreamController(
      format: StreamFormat.ndjson,
      cancelToken: cancel,
    );

    final events = <StreamResponseState<String>>[];
    final sub = chat.streamWithResult().listen(events.add);

    controller.add(utf8.encode('{"delta":"x"}\n'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancel.cancel('stop');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await controller.close();
    await sub.asFuture<void>().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await sub.cancel();

    expect(
      events.whereType<StreamChunk<String>>().map((e) => e.data),
      contains('x'),
    );
  });

  test('non-success status yields StreamFailed', () async {
    NetworkClient.instance.dioClient.httpClientAdapter = _ScriptedStreamAdapter([
      _StreamReply(
        statusCode: 500,
        contentType: 'application/json',
        chunks: [utf8.encode('{"error":"boom"}')],
      ),
    ]);

    final controller = _DeltaStreamController(format: StreamFormat.sse);
    final events = await controller.streamWithResult().toList();
    expect(events, hasLength(1));
    expect(events.first, isA<StreamFailed<String>>());
  });
}

base class _DeltaStreamController extends BaseController<String> {
  _DeltaStreamController({
    required StreamFormat format,
    super.cancelToken,
  }) : super(
          path: '/agent/chat',
          method: HTTPMethod.post,
          authenticated: false,
          data: const {'prompt': 'hi'},
          streamFormat: format,
          enableLogs: false,
          responseDecoder: (data) =>
              (data as Map)['delta']?.toString() ?? '',
          chunkDecoder: (frame) => frame.data['delta']?.toString() ?? '',
        );
}

class _StreamReply {
  final int statusCode;
  final String contentType;
  final List<List<int>> chunks;

  _StreamReply({
    required this.statusCode,
    required this.contentType,
    required this.chunks,
  });
}

class _ScriptedStreamAdapter implements HttpClientAdapter {
  _ScriptedStreamAdapter(this._replies);

  final List<_StreamReply> _replies;
  int _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_index >= _replies.length) {
      throw StateError('No scripted stream reply left for ${options.uri}');
    }
    final reply = _replies[_index++];
    return ResponseBody(
      Stream<Uint8List>.fromIterable(
        reply.chunks.map(Uint8List.fromList),
      ),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [reply.contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _LiveStreamAdapter implements HttpClientAdapter {
  _LiveStreamAdapter({
    required this.statusCode,
    required this.contentType,
    required this.byteStream,
  });

  final int statusCode;
  final String contentType;
  final Stream<List<int>> byteStream;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      byteStream.map(Uint8List.fromList),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
