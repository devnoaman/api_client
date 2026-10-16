/// One parsed streaming frame: SSE `event:` name (when present) + JSON payload.
///
/// For NDJSON, [event] is taken from a top-level `"event"` field when present,
/// otherwise `null`.
class StreamEventFrame {
  /// SSE `event:` value (e.g. `meta`, `delta`, `part`, `done`), or NDJSON
  /// `"event"` field. Null when the wire format did not supply a name.
  final String? event;

  /// Decoded JSON object from `data:` (SSE) or the NDJSON line.
  final Map<String, dynamic> data;

  /// Optional SSE `id:` field.
  final String? id;

  const StreamEventFrame({
    required this.data,
    this.event,
    this.id,
  });

  @override
  String toString() =>
      'StreamEventFrame(event: $event, id: $id, data: $data)';
}
