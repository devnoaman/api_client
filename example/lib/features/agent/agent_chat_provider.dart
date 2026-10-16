import 'package:api_client/api_client.dart';
import 'package:example/features/agent/controllers/agent_chat_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AgentChatState {
  final String assembled;
  final bool streaming;
  final String? error;
  final StreamFormat format;

  const AgentChatState({
    this.assembled = '',
    this.streaming = false,
    this.error,
    this.format = StreamFormat.sse,
  });

  AgentChatState copyWith({
    String? assembled,
    bool? streaming,
    String? error,
    StreamFormat? format,
    bool clearError = false,
  }) {
    return AgentChatState(
      assembled: assembled ?? this.assembled,
      streaming: streaming ?? this.streaming,
      error: clearError ? null : (error ?? this.error),
      format: format ?? this.format,
    );
  }
}

final agentChatProvider =
    NotifierProvider<AgentChatNotifier, AgentChatState>(AgentChatNotifier.new);

class AgentChatNotifier extends Notifier<AgentChatState> {
  CancelToken? _cancelToken;

  @override
  AgentChatState build() => const AgentChatState();

  void setFormat(StreamFormat format) {
    state = state.copyWith(format: format);
  }

  Future<void> send(String prompt) async {
    if (prompt.trim().isEmpty || state.streaming) return;

    _cancelToken?.cancel('superseded');
    _cancelToken = CancelToken();

    state = state.copyWith(
      assembled: '',
      streaming: true,
      clearError: true,
    );

    final controller = AgentChatController(
      prompt: prompt.trim(),
      format: state.format,
      cancelToken: _cancelToken,
    );

    try {
      await for (final event in controller.streamWithResult()) {
        switch (event) {
          case StreamChunk(:final data, event: final sseEvent):
            // Contract uses SSE event names: meta / delta / part / done.
            switch (data.event ?? sseEvent) {
              case 'meta':
              case 'part':
                // Metadata / part boundaries — keep streaming, no text append.
                state = state.copyWith(streaming: true);
              case 'done':
                state = state.copyWith(streaming: false);
              case 'delta':
              default:
                if (data.delta.isNotEmpty) {
                  state = state.copyWith(
                    assembled: state.assembled + data.delta,
                    streaming: true,
                  );
                } else {
                  state = state.copyWith(streaming: true);
                }
            }
          case StreamDone():
            state = state.copyWith(streaming: false);
          case StreamFailed(:final error):
            state = state.copyWith(
              streaming: false,
              error: error.toString(),
            );
        }
      }
    } catch (e) {
      state = state.copyWith(streaming: false, error: e.toString());
    } finally {
      if (state.streaming) {
        state = state.copyWith(streaming: false);
      }
    }
  }

  void cancel() {
    _cancelToken?.cancel('user cancelled');
    _cancelToken = null;
    state = state.copyWith(streaming: false);
  }
}
