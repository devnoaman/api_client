import 'dart:convert';

import 'package:api_client/src/client/stream_event_frame.dart';
import 'package:api_client/src/client/stream_format.dart';

/// Parses a raw byte stream into [StreamEventFrame]s for [StreamFormat.sse]
/// or [StreamFormat.ndjson].
///
/// SSE frames preserve the `event:` name (e.g. `meta`, `delta`, `part`,
/// `done`) alongside the JSON `data:` payload.
class StreamBodyParser {
  StreamBodyParser({
    required this.format,
    this.onDoneMarker,
  });

  final StreamFormat format;

  /// Called when SSE `data: [DONE]` is seen (OpenAI-style). The parser stops
  /// yielding further payloads.
  final void Function()? onDoneMarker;

  /// Converts [byteStream] into a stream of [StreamEventFrame]s.
  Stream<StreamEventFrame> parse(Stream<List<int>> byteStream) {
    switch (format) {
      case StreamFormat.sse:
        return _parseSse(byteStream);
      case StreamFormat.ndjson:
        return _parseNdjson(byteStream);
    }
  }

  Stream<StreamEventFrame> _parseNdjson(
    Stream<List<int>> byteStream,
  ) async* {
    var pending = '';
    await for (final bytes in byteStream) {
      pending += utf8.decode(bytes, allowMalformed: true);
      var newline = pending.indexOf('\n');
      while (newline >= 0) {
        final line = pending.substring(0, newline).replaceAll('\r', '').trim();
        pending = pending.substring(newline + 1);
        newline = pending.indexOf('\n');
        final frame = _frameFromMap(_tryDecodeMap(line));
        if (frame != null) yield frame;
      }
    }
    final leftover = pending.replaceAll('\r', '').trim();
    final frame = _frameFromMap(_tryDecodeMap(leftover));
    if (frame != null) yield frame;
  }

  Stream<StreamEventFrame> _parseSse(
    Stream<List<int>> byteStream,
  ) async* {
    var pending = '';
    await for (final bytes in byteStream) {
      pending += utf8.decode(bytes, allowMalformed: true);

      while (true) {
        final sepIndex = _indexOfEventSeparator(pending);
        if (sepIndex < 0) break;
        final eventBlock = pending.substring(0, sepIndex);
        pending = pending.substring(
          sepIndex + _separatorLength(pending, sepIndex),
        );
        final result = _handleSseBlock(eventBlock);
        if (result.isDone) return;
        if (result.frame != null) yield result.frame!;
      }
    }

    final trailing = pending.trim();
    if (trailing.isEmpty) return;
    final result = _handleSseBlock(trailing);
    if (result.isDone) return;
    if (result.frame != null) yield result.frame!;
  }

  _SseHandleResult _handleSseBlock(String eventBlock) {
    final fields = _extractSseFields(eventBlock);
    final payload = fields.data;
    if (payload == null) return const _SseHandleResult.empty();
    if (payload.trim() == '[DONE]') {
      onDoneMarker?.call();
      return const _SseHandleResult.doneMarker();
    }
    final map = _tryDecodeMap(payload) ?? <String, dynamic>{};
    return _SseHandleResult.frameValue(
      StreamEventFrame(
        event: fields.event,
        id: fields.id,
        data: map,
      ),
    );
  }

  /// Promotes NDJSON `"event"` into [StreamEventFrame.event] when present.
  static StreamEventFrame? _frameFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final event = map['event']?.toString();
    return StreamEventFrame(event: event, data: map);
  }

  static Map<String, dynamic>? _tryDecodeMap(String text) {
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed chunk — skip
    }
    return null;
  }

  static int _indexOfEventSeparator(String text) {
    final lf = text.indexOf('\n\n');
    final crlf = text.indexOf('\r\n\r\n');
    if (lf < 0) return crlf;
    if (crlf < 0) return lf;
    return lf < crlf ? lf : crlf;
  }

  static int _separatorLength(String text, int index) {
    if (text.startsWith('\r\n\r\n', index)) return 4;
    return 2;
  }

  /// Reads `event:`, `id:`, and all `data:` lines from one SSE event block.
  static ({String? event, String? id, String? data}) _extractSseFields(
    String eventBlock,
  ) {
    String? event;
    String? id;
    final dataLines = <String>[];
    for (final rawLine in eventBlock.split(RegExp(r'\r?\n'))) {
      if (rawLine.startsWith('event:')) {
        var value = rawLine.substring(6);
        if (value.startsWith(' ')) value = value.substring(1);
        event = value;
      } else if (rawLine.startsWith('id:')) {
        var value = rawLine.substring(3);
        if (value.startsWith(' ')) value = value.substring(1);
        id = value;
      } else if (rawLine.startsWith('data:')) {
        var value = rawLine.substring(5);
        if (value.startsWith(' ')) value = value.substring(1);
        dataLines.add(value);
      }
    }
    if (dataLines.isEmpty) {
      return (event: event, id: id, data: null);
    }
    return (event: event, id: id, data: dataLines.join('\n'));
  }
}

class _SseHandleResult {
  final StreamEventFrame? frame;
  final bool isDone;

  const _SseHandleResult.empty()
      : frame = null,
        isDone = false;

  const _SseHandleResult.doneMarker()
      : frame = null,
        isDone = true;

  const _SseHandleResult.frameValue(this.frame) : isDone = false;
}
