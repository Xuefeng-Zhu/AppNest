import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../../client.dart';
import '../builder/builder_screen.dart';
import '../mini_app/mini_app_screen.dart';
import 'home_load_failure.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function(int appId, {int? recordId})? onOpenApp;
  final int refreshToken;
  const HomeScreen({super.key, this.onOpenApp, this.refreshToken = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<WorkspaceInfo> workspaces = [];
  List<AppManifest> apps = [];
  List<TemplateInfo> templates = [];
  List<InboxItem> inbox = [];
  int? workspaceId;
  int page = 0;
  bool loading = true;
  Object? error;
  PlatformInfo? platform;
  final prompt = TextEditingController();
  bool invitationHandled = false;
  int loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prompt.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only retry reads. Never replay a business command on reconnect/resume.
    if (state == AppLifecycleState.resumed && error != null && !loading) {
      load();
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    final requestedWorkspace = workspaceId;
    setState(() => loading = true);
    try {
      final ws = await client.apps.workspaces(),
          p = await client.builder.platform();
      if (!mounted || generation != loadGeneration) return;
      final selectedWorkspace = ws.any((w) => w.id == requestedWorkspace)
          ? requestedWorkspace!
          : ws.first.id;
      final results = await Future.wait<dynamic>([
        client.apps.list(selectedWorkspace),
        client.apps.templates(),
        client.runtime.inbox(),
      ]);
      if (!mounted || generation != loadGeneration) return;
      if (mounted) {
        setState(() {
          workspaceId = selectedWorkspace;
          workspaces = ws;
          platform = p;
          apps = results[0] as List<AppManifest>;
          templates = results[1] as List<TemplateInfo>;
          inbox = results[2] as List<InboxItem>;
          loading = false;
          error = null;
        });
      }
      final token = Uri.base.queryParameters['invite'];
      if (token != null && !invitationHandled && mounted) {
        invitationHandled = true;
        await join(token);
      }
    } catch (e) {
      if (mounted && generation == loadGeneration) {
        setState(() {
          // Do not leave private launcher/inbox content cached after a failed
          // authorization or refresh. The next load rechecks every endpoint.
          workspaces = [];
          apps = [];
          inbox = [];
          templates = [];
          platform = null;
          error = e;
          loading = false;
        });
      }
    }
  }

  Future<void> open(int id, {int? recordId}) async {
    if (widget.onOpenApp != null) {
      await widget.onOpenApp!(id, recordId: recordId);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MiniAppScreen(appId: id, initialRecordId: recordId),
      ),
    );
    load();
  }

  Future<void> builder(String templateKey, {bool generate = false}) async {
    try {
      var d = await client.builder.begin(workspaceId!, templateKey, null);
      if (generate) {
        d = await client.builder.generate(
          d.draftId,
          d.mutation,
          prompt.text,
          startFromScratch: true,
        );
      }
      if (mounted) {
        final published = await Navigator.push<int>(
          context,
          MaterialPageRoute<int>(builder: (_) => BuilderScreen(initial: d)),
        );
        if (published != null && mounted) await open(published);
      }
      load();
    } catch (e) {
      showError(e);
    }
  }

  void showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> join(String token) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a shared app?'),
        content: const Text(
          'This opens the same app and shared records, using the role chosen by the inviter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join app'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await open(await client.apps.acceptInvitation(token));
    } catch (e) {
      showError(e);
    }
  }

  Future<void> newWorkspace() async {
    final text = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New shared workspace'),
        content: TextField(
          controller: text,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null) {
      try {
        workspaceId = await client.apps.createWorkspace(name);
        load();
      } catch (e) {
        showError(e);
      }
    }
  }

  Widget workspacePicker() => DropdownButton<int>(
    isExpanded: true,
    value: workspaceId,
    underline: const SizedBox(),
    items: workspaces
        .map(
          (w) => DropdownMenuItem(
            value: w.id,
            child: Text(w.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) {
      setState(() => workspaceId = v);
      load();
    },
  );
  Widget navigation(bool wide) => wide
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.spa_outlined, size: 30),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AppNest',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: workspacePicker(),
            ),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  selected: page == i,
                  selectedTileColor: const Color(0xffe2eeea),
                  leading: Icon(
                    [
                      Icons.home_outlined,
                      Icons.grid_view_outlined,
                      Icons.inbox_outlined,
                    ][i],
                  ),
                  title: Text(['Home', 'Templates', 'Inbox'][i]),
                  onTap: () => setState(() => page = i),
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: newWorkspace,
              icon: const Icon(Icons.add),
              label: const Text('New workspace'),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'signout') await client.auth.signOutDevice();
                if (v == 'copy') {
                  await Clipboard.setData(
                    ClipboardData(text: platform?.actorId ?? ''),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'copy',
                  child: Text('Copy my account ID'),
                ),
                const PopupMenuItem(value: 'signout', child: Text('Sign out')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: [
                    CircleAvatar(child: Icon(Icons.person_outline)),
                    SizedBox(width: 12),
                    Expanded(child: Text('Your account')),
                  ],
                ),
              ),
            ),
          ],
        )
      : NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (i) => setState(() => page = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              label: 'Templates',
            ),
            NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              label: 'Inbox',
            ),
          ],
        );
  Widget icon(String? definition, {double size = 48}) {
    final spec = definition == null ? null : AppSpec.parse(definition);
    const colors = {
      'amber': Color(0xffffe8ba),
      'sage': Color(0xffdcece2),
      'blue': Color(0xffdbeafa),
      'teal': Color(0xffdaeeea),
      'rose': Color(0xfff7dfdf),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors[spec?.theme] ?? colors['teal'],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        switch (spec?.icon) {
          'book' => Icons.menu_book_outlined,
          'board' => Icons.view_kanban_outlined,
          'check' => Icons.check_circle_outline,
          'people' => Icons.people_outline,
          _ => Icons.auto_awesome_outlined,
        },
        size: size * .5,
      ),
    );
  }

  Widget templateList() => Column(
    children: templates
        .map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, c) => Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      icon(t.specJson, size: 42),
                      SizedBox(
                        width: c.maxWidth < 500 ? 180 : 200,
                        child: Text(
                          t.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (c.maxWidth > 700)
                        SizedBox(
                          width: c.maxWidth - 450,
                          child: Text(t.description),
                        ),
                      OutlinedButton(
                        onPressed: () => builder(t.key),
                        child: const Text('Use template'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(),
  );
  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'A little app. A lot together.',
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 16),
      Text(
        'Describe the tool your group needs.',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 32),
      LayoutBuilder(
        builder: (context, c) {
          final input = TextField(
            controller: prompt,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Describe an app…',
              contentPadding: EdgeInsets.all(24),
            ),
          );
          final button = FilledButton.icon(
            onPressed: () {
              if (platform?.aiAvailable == true &&
                  prompt.text.trim().isNotEmpty) {
                builder('volunteer', generate: true);
              } else {
                setState(() => page = 1);
              }
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Create preview'),
          );
          return c.maxWidth < 600
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [input, const SizedBox(height: 12), button],
                )
              : Row(
                  children: [
                    Expanded(child: input),
                    const SizedBox(width: 16),
                    button,
                  ],
                );
        },
      ),
      if (platform?.aiAvailable == false) ...[
        const SizedBox(height: 10),
        Text(
          platform!.aiMode,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: 48),
      Text('Your apps', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      if (apps.where((a) => a.pinned).isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('Your workspace is ready. Start with a template below.'),
        ),
      LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: apps
              .where((a) => a.pinned)
              .map(
                (a) => SizedBox(
                  width: c.maxWidth < 650 ? c.maxWidth : (c.maxWidth - 32) / 3,
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => open(a.appId),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Row(
                          children: [
                            icon(a.specJson),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    a.archived
                                        ? 'Archived'
                                        : AppSpec.parse(a.specJson!).requires
                                              .contains('capacity.v1')
                                        ? '${a.availablePlaces} places available'
                                        : '${a.recordCount} ${a.recordCount == 1 ? 'record' : 'records'}',
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      if (apps.any((a) => !a.pinned))
        ExpansionTile(
          title: const Text('All apps, including unpinned'),
          children: apps
              .where((a) => !a.pinned)
              .map(
                (a) => ListTile(
                  title: Text(a.name),
                  onTap: () => open(a.appId),
                  trailing: IconButton(
                    tooltip: 'Pin app',
                    icon: const Icon(Icons.push_pin_outlined),
                    onPressed: () async {
                      await client.apps.pin(a.appId, true);
                      load();
                    },
                  ),
                ),
              )
              .toList(),
        ),
      const SizedBox(height: 40),
      const Divider(),
      const SizedBox(height: 28),
      Text(
        'Start with a template',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      templateList(),
    ],
  );
  Widget content() => loading
      ? const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to AppNest…'),
            ],
          ),
        )
      : error != null
      ? HomeLoadFailure(error: error!, onRetry: load)
      : SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 700 ? 20 : 48,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: switch (page) {
                0 => home(),
                1 => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Templates',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A template creates an empty app. Review its structure and permissions before publishing.',
                    ),
                    const SizedBox(height: 32),
                    templateList(),
                  ],
                ),
                _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inbox',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 24),
                    if (inbox.isEmpty)
                      const Text(
                        'All quiet. Approved reminders will appear here.',
                      ),
                    ...inbox.map(
                      (n) => Card(
                        child: ListTile(
                          leading: Icon(
                            n.isRead
                                ? Icons.drafts_outlined
                                : Icons.mark_email_unread_outlined,
                          ),
                          title: Text(n.title),
                          subtitle: Text('${n.body}\n${n.createdAt.toLocal()}'),
                          onTap: () async {
                            await client.runtime.readNotification(n.id);
                            open(n.appId, recordId: n.recordId);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              },
            ),
          ),
        );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return Scaffold(
        appBar: wide
            ? null
            : AppBar(
                title: const Text('AppNest'),
                actions: [
                  IconButton(
                    tooltip: 'New workspace',
                    onPressed: newWorkspace,
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => client.auth.signOutDevice(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
        body: wide
            ? Row(
                children: [
                  SizedBox(width: 230, child: navigation(true)),
                  const VerticalDivider(width: 1),
                  Expanded(child: content()),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: workspacePicker(),
                  ),
                  Expanded(child: content()),
                ],
              ),
        bottomNavigationBar: wide ? null : navigation(false),
      );
    },
  );
}
