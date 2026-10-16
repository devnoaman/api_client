import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamBodyParser NDJSON', () {
    test('parses one JSON object per line across chunk boundaries', () async {
      final parser = StreamBodyParser(format: StreamFormat.ndjson);
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('{"delta":"Hel'),
        utf8.encode('lo"}\n{"delta":" wor'),
        utf8.encode('ld"}\n'),
      ]);

      final frames = await parser.parse(input).toList();
      expect(frames.map((f) => f.data).toList(), [
        {'delta': 'Hello'},
        {'delta': ' world'},
      ]);
    });

    test('promotes NDJSON event field to frame.event', () async {
      final parser = StreamBodyParser(format: StreamFormat.ndjson);
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('{"event":"meta","sessionId":"s1"}\n'),
        utf8.encode('{"event":"delta","text":"hi"}\n'),
      ]);

      final frames = await parser.parse(input).toList();
      expect(frames[0].event, 'meta');
      expect(frames[0].data['sessionId'], 's1');
      expect(frames[1].event, 'delta');
      expect(frames[1].data['text'], 'hi');
    });

    test('flushes trailing line without final newline', () async {
      final parser = StreamBodyParser(format: StreamFormat.ndjson);
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('{"delta":"bye"}'),
      ]);

      final frames = await parser.parse(input).toList();
      expect(frames.single.data, {'delta': 'bye'});
    });

    test('skips blank lines and malformed JSON', () async {
      final parser = StreamBodyParser(format: StreamFormat.ndjson);
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('\nnot-json\n{"ok":true}\n'),
      ]);

      final frames = await parser.parse(input).toList();
      expect(frames.single.data, {'ok': true});
    });
  });

  group('StreamBodyParser SSE', () {
    test('returns event name with data payload', () async {
      final parser = StreamBodyParser(format: StreamFormat.sse);
      final payload = [
        'event: meta',
        'id: 1',
        'data: {"sessionId":"abc"}',
        '',
        'event: delta',
        'data: {"text":"Hi"}',
        '',
        'event: part',
        'data: {"index":0}',
        '',
        'event: done',
        'data: {}',
        '',
      ].join('\n');
      final input = Stream<List<int>>.fromIterable([utf8.encode(payload)]);

      final frames = await parser.parse(input).toList();
      expect(frames, hasLength(4));
      expect(frames[0].event, 'meta');
      expect(frames[0].id, '1');
      expect(frames[0].data, {'sessionId': 'abc'});
      expect(frames[1].event, 'delta');
      expect(frames[1].data, {'text': 'Hi'});
      expect(frames[2].event, 'part');
      expect(frames[3].event, 'done');
      expect(frames[3].data, isEmpty);
    });

    test('parses data-only events with null event name', () async {
      final parser = StreamBodyParser(format: StreamFormat.sse);
      final payload = [
        'data: {"delta":"Hi"}',
        '',
        'data: {"delta":"!"}',
        '',
      ].join('\n');
      final input = Stream<List<int>>.fromIterable([utf8.encode(payload)]);

      final frames = await parser.parse(input).toList();
      expect(frames.map((f) => f.event).toList(), [null, null]);
      expect(frames.map((f) => f.data).toList(), [
        {'delta': 'Hi'},
        {'delta': '!'},
      ]);
    });

    test('stops on data: [DONE] and invokes callback', () async {
      var done = false;
      final parser = StreamBodyParser(
        format: StreamFormat.sse,
        onDoneMarker: () => done = true,
      );
      final payload = [
        'event: delta',
        'data: {"delta":"a"}',
        '',
        'data: [DONE]',
        '',
        'event: delta',
        'data: {"delta":"ignored"}',
        '',
      ].join('\n');
      final input = Stream<List<int>>.fromIterable([utf8.encode(payload)]);

      final frames = await parser.parse(input).toList();
      expect(frames, hasLength(1));
      expect(frames.single.event, 'delta');
      expect(done, isTrue);
    });

    test('handles CRLF separators and split chunks', () async {
      final parser = StreamBodyParser(format: StreamFormat.sse);
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('event: delta\r\ndata: {"n":1}\r\n'),
        utf8.encode('\r\nevent: delta\r\ndata: {"n":2}\r\n\r\n'),
      ]);

      final frames = await parser.parse(input).toList();
      expect(frames.map((f) => f.event).toList(), ['delta', 'delta']);
      expect(frames.map((f) => f.data).toList(), [
        {'n': 1},
        {'n': 2},
      ]);
    });
  });
}
