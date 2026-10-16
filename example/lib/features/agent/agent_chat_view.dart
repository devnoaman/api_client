import 'package:api_client/api_client.dart';
import 'package:example/features/agent/agent_chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AgentChatView extends HookConsumerWidget {
  const AgentChatView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentChatProvider);
    final notifier = ref.read(agentChatProvider.notifier);
    final promptCtrl = useTextEditingController();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI agent streaming',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'POST /agent/chat — chunks arrive via streamWithResult()',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<StreamFormat>(
            segments: const [
              ButtonSegment(
                value: StreamFormat.sse,
                label: Text('SSE'),
                icon: Icon(Icons.bolt, size: 16),
              ),
              ButtonSegment(
                value: StreamFormat.ndjson,
                label: Text('NDJSON'),
                icon: Icon(Icons.view_stream, size: 16),
              ),
            ],
            selected: {state.format},
            onSelectionChanged: state.streaming
                ? null
                : (s) => notifier.setFormat(s.first),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  state.assembled.isEmpty
                      ? (state.streaming
                          ? 'Waiting for first chunk…'
                          : 'Agent reply will stream here.')
                      : state.assembled,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: promptCtrl,
                  enabled: !state.streaming,
                  decoration: const InputDecoration(
                    hintText: 'Ask the test agent…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (v) => notifier.send(v),
                ),
              ),
              const SizedBox(width: 8),
              if (state.streaming)
                IconButton.filled(
                  onPressed: notifier.cancel,
                  icon: const Icon(Icons.stop),
                  tooltip: 'Cancel',
                )
              else
                IconButton.filled(
                  onPressed: () => notifier.send(promptCtrl.text),
                  icon: const Icon(Icons.send),
                  tooltip: 'Send',
                ),
            ],
          ),
        ],
      ),
    );
  }
}
