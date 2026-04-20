import 'package:example/features/manual_token/manual_token_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Demonstrates using [TokensManager.saveAccess] directly —
/// without going through [AuthManager.login].
///
/// Steps:
///   1. Fetch a token from POST /auth/token-only (raw call, no AuthManager)
///   2. Token is saved via TokensManager.saveAccess()
///   3. Call GET /users (protected) — interceptor attaches token automatically
///   4. Clear the token and repeat Step 3 to confirm 401
class ManualTokenView extends HookConsumerWidget {
  const ManualTokenView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualTokenProvider);
    final notifier = ref.read(manualTokenProvider.notifier);

    final emailCtrl = useTextEditingController(text: 'alice@example.com');
    final passCtrl = useTextEditingController(text: 'password123');

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Token Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Description ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Text(
                'This screen tests TokensManager.saveAccess() WITHOUT using '
                'AuthManager.login.\n\n'
                'Step 1 → GET /auth/token-only (raw Dio, no AuthManager)\n'
                'Step 2 → GET /users (protected — interceptor auto-attaches token)\n'
                'Step 3 → Clear token, retry Step 2 to confirm 401',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),

            // ── Credentials ────────────────────────────────────────────
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // ── Step 1 ──────────────────────────────────────────────────
            _StepButton(
              step: '1',
              label: 'Fetch token & save via TokensManager.saveAccess()',
              color: Colors.indigo,
              loading: state.isLoading,
              onPressed: () => notifier.fetchAndSaveToken(
                emailCtrl.text.trim(),
                passCtrl.text,
              ),
            ),
            const SizedBox(height: 10),

            // ── Step 2 ──────────────────────────────────────────────────
            _StepButton(
              step: '2',
              label: 'Call GET /users (protected) — token auto-attached',
              color: Colors.teal,
              loading: state.isLoading,
              enabled: state.savedToken != null,
              onPressed: notifier.callProtectedEndpoint,
            ),
            const SizedBox(height: 10),

            // ── Step 3 ──────────────────────────────────────────────────
            _StepButton(
              step: '3',
              label: 'Clear token (then retry Step 2 → expect 401)',
              color: Colors.red,
              loading: false,
              enabled: state.savedToken != null,
              onPressed: notifier.clearToken,
            ),
            const SizedBox(height: 20),

            // ── Status / log ───────────────────────────────────────────
            if (state.error != null)
              _StatusBox(
                label: 'Error',
                text: state.error!,
                color: Colors.red.shade50,
                borderColor: Colors.red.shade300,
                textColor: Colors.red.shade800,
              ),
            if (state.log != null) ...[
              const SizedBox(height: 10),
              _StatusBox(
                label: 'Log',
                text: state.log!,
                color: Colors.green.shade50,
                borderColor: Colors.green.shade300,
                textColor: Colors.green.shade900,
              ),
            ],

            // ── Token chip ─────────────────────────────────────────────
            if (state.savedToken != null) ...[
              const SizedBox(height: 10),
              Wrap(
                children: [
                  Chip(
                    avatar: const Icon(Icons.key, size: 16, color: Colors.indigo),
                    label: Text(
                      'Token: ${state.savedToken!.substring(0, 12)}…',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.indigo.shade50,
                  ),
                ],
              ),
            ],

            // ── Users list ─────────────────────────────────────────────
            if (state.users != null) ...[
              const Divider(height: 24),
              Text(
                'Users (${state.users!.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...state.users!.map(
                (u) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(u.name[0].toUpperCase()),
                  ),
                  title: Text(u.name),
                  subtitle: Text(u.email),
                  trailing: Chip(
                    label: Text(u.role, style: const TextStyle(fontSize: 11)),
                    backgroundColor: u.role == 'admin'
                        ? Colors.amber.shade100
                        : Colors.blue.shade50,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String step;
  final String label;
  final Color color;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  const _StepButton({
    required this.step,
    required this.label,
    required this.color,
    required this.loading,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: enabled ? color : Colors.grey,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        alignment: Alignment.centerLeft,
      ),
      onPressed: (loading || !enabled) ? null : onPressed,
      icon: CircleAvatar(
        radius: 12,
        backgroundColor: Colors.white24,
        child: Text(step, style: const TextStyle(fontSize: 11, color: Colors.white)),
      ),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _StatusBox extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final Color borderColor;
  final Color textColor;

  const _StatusBox({
    required this.label,
    required this.text,
    required this.color,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: textColor)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 13, color: textColor)),
        ],
      ),
    );
  }
}
