import 'package:example/features/login/providers/account_provider.dart';
import 'package:example/features/login/presentation/login_view.dart';
import 'package:example/features/manual_token/manual_token_view.dart';
import 'package:example/features/users/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class UsersView extends HookConsumerWidget {
  const UsersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('api_client Demo'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Users (AuthManager)'),
              Tab(icon: Icon(Icons.vpn_key), text: 'Manual Token Test'),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginView()),
                  );
                }
              },
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            _UsersTab(),
            ManualTokenView(),
          ],
        ),
      ),
    );
  }
}

class _UsersTab extends HookConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);
    final pingAsync = ref.watch(pingProvider);

    final nameCtrl = useTextEditingController();
    final emailCtrl = useTextEditingController();

    return Column(
      children: [
        // ── Ping banner ──────────────────────────────────────────
        Container(
          width: double.infinity,
          color: Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: pingAsync.when(
            data: (msg) => Row(
              children: [
                const Icon(Icons.circle, color: Colors.green, size: 10),
                const SizedBox(width: 8),
                Text(msg, style: const TextStyle(fontSize: 12)),
              ],
            ),
            loading: () => const Text('Pinging server…',
                style: TextStyle(fontSize: 12)),
            error: (e, _) => Text('$e',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
          ),
        ),

        // ── Create user form ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty) return;
                  await ref
                      .read(usersProvider.notifier)
                      .create(nameCtrl.text.trim(), emailCtrl.text.trim());
                  nameCtrl.clear();
                  emailCtrl.clear();
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'POST /users returns 201 — demonstrates successStatusCodes: [200, 201]',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        const Divider(),

        // ── Users list ───────────────────────────────────────────
        Expanded(
          child: usersAsync.when(
            data: (users) => RefreshIndicator(
              onRefresh: () => ref.read(usersProvider.notifier).load(),
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (_, i) => _UserTile(user: users[i]),
              ),
            ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text('$e', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.read(usersProvider.notifier).load(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text(user.name[0].toUpperCase())),
      title: Text(user.name),
      subtitle: Text(user.email),
      trailing: Chip(
        label: Text(user.role),
        backgroundColor: user.role == 'admin'
            ? Colors.amber.shade100
            : Colors.blue.shade50,
      ),
    );
  }
}
