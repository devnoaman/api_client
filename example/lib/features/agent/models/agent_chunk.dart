import 'package:api_client/api_client.dart';

/// One streamed fragment from POST /agent/chat.
///
/// [event] mirrors the SSE `event:` name (`meta`, `delta`, `part`, `done`, …).
class AgentChunk {
  final String? event;
  final String id;
  final String role;
  final String delta;
  final int index;
  final bool done;

  const AgentChunk({
    this.event,
    required this.id,
    required this.role,
    required this.delta,
    required this.index,
    required this.done,
  });

  factory AgentChunk.fromFrame(StreamEventFrame frame) {
    final json = frame.data;
    return AgentChunk(
      event: frame.event ?? json['event']?.toString(),
      id: json['id']?.toString() ?? frame.id ?? '',
      role: json['role']?.toString() ?? 'assistant',
      delta: (json['delta'] ?? json['text'])?.toString() ?? '',
      index: (json['index'] as num?)?.toInt() ?? 0,
      done: frame.event == 'done' || json['done'] == true,
    );
  }
}
