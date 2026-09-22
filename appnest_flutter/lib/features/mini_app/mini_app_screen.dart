import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../client.dart';
import '../builder/builder_screen.dart';
import 'live_adapter.dart';

class MiniAppScreen extends StatefulWidget {
  final int appId;
  final MiniAppLocation? initialLocation;
  final int? initialRecordId;
  final ValueChanged<MiniAppLocation>? onLocationChanged;
  final Future<void> Function()? onClose;
  final Future<void> Function(int appId, {int? recordId})? onOpenApp;
  const MiniAppScreen({
    super.key,
    required this.appId,
    this.initialLocation,
    this.initialRecordId,
    this.onLocationChanged,
    this.onClose,
    this.onOpenApp,
  });
  @override
  State<MiniAppScreen> createState() => MiniAppScreenState();
}

class MiniAppScreenState extends State<MiniAppScreen> {
  AppManifest? manifest;
  Object? error;
  LiveRuntimeAdapter? adapter;
  final controller = MiniAppController();
  MiniAppLocation? initialLocation;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    controller.dispose();
    super.dispose();
  }

  Future<bool> canLeave() => controller.canLeave();
  Future<bool> back() async {
    final location = controller.location;
    final entry = adapter?.spec.navigation?.entryPageId;
    if (location == null ||
        (location.pageId == entry &&
            location.recordId == null &&
            !location.editing)) {
      return false;
    }
    await controller.back();
    // A declined discard confirmation still consumes the back action.
    return true;
  }

  Future<MiniAppLocation?> _resolveLocation(
    MiniAppLocation? requested,
    int? recordId,
  ) async {
    final a = adapter;
    final nav = a?.spec.navigation;
    if (a == null || nav == null) return null;
    if (requested != null) {
      return nav.pages.any((p) => p.id == requested.pageId)
          ? requested
          : MiniAppLocation(nav.entryPageId);
    }
    if (recordId != null) {
      final record = await a.get(recordId);
      final detail = a.spec.views
          .where(
            (v) => v.collectionId == record.collectionId && v.type == 'details',
          )
          .firstOrNull;
      final page = nav.pages
          .where((p) => p.viewIds.contains(detail?.id))
          .firstOrNull;
      if (page != null) return MiniAppLocation(page.id, recordId: recordId);
    }
    return MiniAppLocation(nav.entryPageId);
  }

  Future<bool> navigateTo(MiniAppLocation? location, {int? recordId}) async {
    if (adapter == null) return true;
    try {
      final next = await _resolveLocation(location, recordId);
      if (next != null) return await controller.navigate(next);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          error = const SpecException('This item is no longer available.');
        });
      }
      return true;
    }
  }

  Future<void> close() async {
    if (widget.onClose != null) {
      await widget.onClose!();
    } else if (await canLeave() && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    try {
      final m = await client.apps.manifest(widget.appId);
      if (!mounted || generation != _loadGeneration) return;
      final next = LiveRuntimeAdapter(client, m);
      adapter = next;
      final location = await _resolveLocation(
        controller.location ?? widget.initialLocation,
        widget.initialRecordId,
      );
      if (!mounted || generation != _loadGeneration) return;
      if (mounted) {
        setState(() {
          manifest = m;
          adapter = next;
          initialLocation = location;
          error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _loadGeneration && location != null) {
            widget.onLocationChanged?.call(controller.location ?? location);
          }
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          error = e;
          adapter = null;
          manifest = null;
        });
      }
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
        automaticallyImplyLeading: false,
        toolbarHeight: 54,
        title: Row(
          children: [
            Icon(switch (adapter?.spec.icon) {
              'book' => Icons.menu_book_outlined,
              'board' => Icons.view_kanban_outlined,
              'people' => Icons.people_outline,
              'check' => Icons.check_circle_outline,
              _ => Icons.auto_awesome_outlined,
            }, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                m?.name ?? 'Opening app…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (m != null)
            PopupMenuButton<String>(
              tooltip: 'Mini-app menu',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) async {
                try {
                  if (value == 'activity') await activity();
                  if (value == 'share') await share();
                  if (value == 'edit') {
                    if (!await canLeave()) return;
                    final d = await client.builder.begin(
                      m.workspaceId,
                      'reading',
                      m.appId,
                    );
                    if (context.mounted) {
                      await Navigator.push<int>(
                        context,
                        MaterialPageRoute<int>(
                          builder: (_) => BuilderScreen(initial: d),
                        ),
                      );
                    }
                    load();
                  }
                  if (value == 'members') await manage();
                  if (value == 'unpin') {
                    await client.apps.pin(m.appId, false);
                    if (context.mounted) await close();
                  }
                  if (value == 'remix') {
                    if (!await canLeave()) return;
                    final id = await client.apps.remix(m.appId, m.workspaceId);
                    if (context.mounted) {
                      if (widget.onOpenApp != null) {
                        await widget.onOpenApp!(id);
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MiniAppScreen(appId: id),
                          ),
                        );
                      }
                    }
                  }
                  if (value == 'archive') {
                    if (!await canLeave()) return;
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
                const PopupMenuItem(
                  value: 'activity',
                  child: Text('Activity & reminders'),
                ),
                if (builder && !m.archived)
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Invite to app'),
                  ),
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
          Container(height: 20, width: 1, color: const Color(0xffd7ddd7)),
          IconButton(
            onPressed: close,
            tooltip: 'Close mini-app',
            icon: const Icon(Icons.close, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 36),
                    const SizedBox(height: 16),
                    const Text(
                      'This app or item is unavailable. Try again to check your access.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : adapter == null
          ? const Center(child: CircularProgressIndicator())
          : MiniAppRuntime(
              key: ValueKey('${m!.versionId}-${m.archived}'),
              adapter: adapter!,
              controller: controller,
              initialLocation: initialLocation,
              onLocationChanged: widget.onLocationChanged,
            ),
    );
  }
}
