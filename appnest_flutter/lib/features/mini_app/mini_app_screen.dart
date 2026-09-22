import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../client.dart';
import '../builder/builder_screen.dart';
import 'live_adapter.dart';

class MiniAppScreen extends StatefulWidget {
  final int appId;
  const MiniAppScreen({super.key, required this.appId});
  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen> {
  AppManifest? manifest;
  Object? error;
  LiveRuntimeAdapter? adapter;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final m = await client.apps.manifest(widget.appId);
      if (mounted) {
        setState(() {
          manifest = m;
          adapter = LiveRuntimeAdapter(client, m);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> share() async {
    String role = 'member';
    final recipient = TextEditingController();
    String? token;
    Object? failure;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Invite to this app'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'They join this same app and its shared records. The link expires in 7 days and can be accepted by one person.',
                ),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  value: role,
                  items: ['member', 'viewer', 'builder']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: token == null
                      ? (v) => update(() => role = v!)
                      : null,
                ),
                TextField(
                  controller: recipient,
                  decoration: const InputDecoration(
                    labelText: 'Recipient account ID (optional)',
                    helperText:
                        'Leave blank for an authenticated link invitation.',
                  ),
                ),
                if (token != null)
                  SelectableText('${Uri.base.origin}/?invite=$token'),
                if (failure != null) Text('$failure'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (token == null)
              FilledButton(
                onPressed: () async {
                  try {
                    final t = await client.apps.invite(
                      widget.appId,
                      role,
                      recipient.text.trim().isEmpty
                          ? null
                          : recipient.text.trim(),
                    );
                    update(() => token = t);
                  } catch (e) {
                    update(() => failure = e);
                  }
                },
                child: const Text('Create invitation'),
              ),
            if (token != null)
              TextButton(
                onPressed: () async {
                  await client.apps.revokeInvitation(widget.appId, token!);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Revoke link'),
              ),
            if (token != null)
              FilledButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: '${Uri.base.origin}/?invite=$token'),
                ),
                child: const Text('Copy link'),
              ),
          ],
        ),
      ),
    );
    recipient.dispose();
  }

  Future<void> activity() async {
    try {
      final items = await client.apps.activity(widget.appId),
          runs = (manifest!.role == 'owner' || manifest!.role == 'builder')
              ? await client.builder.runs(widget.appId)
              : <ActivityItem>[];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Activity & reminders'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [...runs, ...items]
                  .map(
                    (i) => ListTile(
                      title: Text(i.action),
                      subtitle: Text('${i.status} · ${i.createdAt.toLocal()}'),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> manage() async {
    final members = await client.apps.members(widget.appId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App members'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: members
                .map(
                  (m) => ListTile(
                    title: SelectableText(m.actorId),
                    subtitle: Text(m.role),
                    trailing: m.role == 'owner'
                        ? null
                        : TextButton(
                            onPressed: () async {
                              await client.apps.setGrant(
                                widget.appId,
                                m.actorId,
                                null,
                              );
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: const Text('Revoke'),
                          ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final builder = m?.role == 'owner' || m?.role == 'builder';
    return Scaffold(
      appBar: AppBar(
        title: Text(m?.name ?? 'Opening app…'),
        actions: [
          if (m != null)
            IconButton(
              onPressed: activity,
              tooltip: 'Activity and reminder history',
              icon: const Icon(Icons.history),
            ),
          if (builder && !m!.archived)
            IconButton(
              onPressed: share,
              tooltip: 'Share',
              icon: const Icon(Icons.person_add_alt),
            ),
          if (m != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                try {
                  if (value == 'edit') {
                    final d = await client.builder.begin(
                      m.workspaceId,
                      'reading',
                      m.appId,
                    );
                    if (context.mounted) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => BuilderScreen(initial: d),
                        ),
                      );
                    }
                    load();
                  }
                  if (value == 'members') await manage();
                  if (value == 'unpin') {
                    await client.apps.pin(m.appId, false);
                    if (context.mounted) Navigator.pop(context);
                  }
                  if (value == 'remix') {
                    final id = await client.apps.remix(m.appId, m.workspaceId);
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => MiniAppScreen(appId: id),
                        ),
                      );
                    }
                  }
                  if (value == 'archive') {
                    if (!context.mounted) return;
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Archive this app?'),
                        content: const Text(
                          'Records remain available read-only. Future reminders will be suppressed.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Archive'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await client.apps.archive(m.appId);
                      load();
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              itemBuilder: (_) => [
                if (builder && !m.archived)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit with AI'),
                  ),
                if (builder)
                  const PopupMenuItem(
                    value: 'members',
                    child: Text('Manage members'),
                  ),
                const PopupMenuItem(
                  value: 'remix',
                  child: Text('Remix structure only'),
                ),
                const PopupMenuItem(
                  value: 'unpin',
                  child: Text('Remove shortcut'),
                ),
                if (m.role == 'owner' && !m.archived)
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive app'),
                  ),
              ],
            ),
        ],
      ),
      body: error != null
          ? Center(child: Text('$error'))
          : adapter == null
          ? const Center(child: CircularProgressIndicator())
          : MiniAppRuntime(
              key: ValueKey('${m!.versionId}-${m.archived}'),
              adapter: adapter!,
            ),
    );
  }
}
