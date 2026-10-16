import 'package:api_client/api_client.dart';
import 'package:example/features/agent/models/agent_chunk.dart';

/// POST /agent/chat — authenticated SSE (or NDJSON) agent message stream.
base class AgentChatController extends BaseController<AgentChunk> {
  AgentChatController({
    required String prompt,
    StreamFormat format = StreamFormat.sse,
    super.cancelToken,
  }) : super(
          path: '/agent/chat',
          method: HTTPMethod.post,
          authenticated: true,
          data: {'prompt': prompt},
          queryParameters: {
            'format': format == StreamFormat.sse ? 'sse' : 'ndjson',
          },
          streamFormat: format,
          responseDecoder: (data) => AgentChunk.fromFrame(
            StreamEventFrame(
              data: Map<String, dynamic>.from(data as Map),
            ),
          ),
          chunkDecoder: AgentChunk.fromFrame,
        );
}
