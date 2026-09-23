import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../../client.dart';
import '../builder/idea_guidance.dart';
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
  bool creating = false;
  Object? error;
  PlatformInfo? platform;
  final prompt = TextEditingController();
  final guidancePanelKey = GlobalKey();
  List<GuidanceQuestion>? guidanceQuestions;
  String? guidanceSource;
  int? guidanceWorkspace;
  bool guidanceFallback = false;
  String? guidanceNotice;
  int? preparedGuidanceWorkspace;
  String? preparedGuidanceText;
  String? assessedIdea;
  int? assessedWorkspace;
  ({int workspaceId, BuilderSnapshot draft, String request})? pendingCreation;
  bool invitationHandled = false;
  int loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prompt.addListener(onPromptChanged);
    load();
  }

  void onPromptChanged() {
    if (guidanceQuestions != null && prompt.text.trim() != guidanceSource) {
      setState(() => guidanceQuestions = null);
    }
  }

  void showGuidance(
    List<GuidanceQuestion> questions,
    String source,
    int selectedWorkspace, {
    required bool fallback,
    String? notice,
  }) {
    setState(() {
      guidanceQuestions = questions;
      guidanceSource = source;
      guidanceWorkspace = selectedWorkspace;
      guidanceFallback = fallback;
      guidanceNotice = notice;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panelContext = guidancePanelKey.currentContext;
      if (mounted && panelContext != null) {
        Scrollable.ensureVisible(
          panelContext,
          alignment: 0,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
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
          if (workspaceId != selectedWorkspace) {
            guidanceQuestions = null;
            preparedGuidanceWorkspace = null;
            preparedGuidanceText = null;
          }
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
    final request = prompt.text.trim();
    if (creating || workspaceId == null) return;
    if (generate && (platform?.aiAvailable != true || request.isEmpty)) return;
    final selectedWorkspace = workspaceId!;
    setState(() => creating = true);
    try {
      final pending = pendingCreation;
      BuilderSnapshot? d;
      var submittedRequest = request;
      var alreadyAccepted = false;
      if (generate &&
          pending != null &&
          pending.workspaceId == selectedWorkspace) {
        d = await client.builder.get(pending.draft.draftId);
        // A lost response may hide a successful enqueue. Recover that request
        // instead of creating another app or submitting the same idea twice.
        alreadyAccepted =
            d.jobId != null && d.mutation > pending.draft.mutation;
        if (alreadyAccepted) submittedRequest = pending.request;
      }
      if (generate && !alreadyAccepted) {
        final prepared =
            preparedGuidanceWorkspace == selectedWorkspace &&
            preparedGuidanceText != null &&
            request.startsWith(preparedGuidanceText!);
        final assessed =
            assessedWorkspace == selectedWorkspace && assessedIdea == request;
        if (!prepared && !assessed && canAssessIdea(request)) {
          try {
            final questions = cleanGuidanceQuestions(
              await client.builder.suggestQuestions(
                request,
                selectedWorkspace,
                null,
              ),
            );
            if (!mounted ||
                workspaceId != selectedWorkspace ||
                prompt.text.trim() != request) {
              return;
            }
            if (questions == null || questions.isNotEmpty) {
              showGuidance(
                questions ?? builtInGuidanceQuestions,
                request,
                selectedWorkspace,
                fallback: questions == null,
                notice: questions == null
                    ? 'AI questions were incomplete. Try these built-in questions.'
                    : null,
              );
              return;
            }
            assessedIdea = request;
            assessedWorkspace = selectedWorkspace;
          } catch (e) {
            if (!mounted ||
                workspaceId != selectedWorkspace ||
                prompt.text.trim() != request) {
              return;
            }
            if (!canOfferBuiltInGuidance(e)) rethrow;
            showGuidance(
              builtInGuidanceQuestions,
              request,
              selectedWorkspace,
              fallback: true,
              notice: 'AI questions are unavailable. Try these built-in questions, or continue with your original idea.',
            );
            return;
          }
        }
        if (pending == null || pending.workspaceId != selectedWorkspace) {
          d = await client.builder.begin(selectedWorkspace, templateKey, null);
        }
      }
      if (!generate) {
        d = await client.builder.begin(selectedWorkspace, templateKey, null);
      }
      if (generate && !alreadyAccepted) {
        final startingDraft = d!;
        pendingCreation = (
          workspaceId: selectedWorkspace,
          draft: startingDraft,
          request: request,
        );
        d = await client.builder.generate(
          startingDraft.draftId,
          startingDraft.mutation,
          request,
          startFromScratch: true,
        );
      }
      if (mounted) {
        preparedGuidanceWorkspace = null;
        preparedGuidanceText = null;
        guidanceQuestions = null;
        final navigation = Navigator.push<int>(
          context,
          MaterialPageRoute<int>(
            builder: (_) => BuilderScreen(
              initial: d!,
              initialPrompt: generate ? submittedRequest : null,
              startFromScratch: generate,
            ),
          ),
        );
        pendingCreation = null;
        final published = await navigation;
        if (published != null && mounted) await open(published);
      }
      load();
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => creating = false);
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
        final createdWorkspace = await client.apps.createWorkspace(name);
        if (!mounted) return;
        setState(() {
          workspaceId = createdWorkspace;
          guidanceQuestions = null;
          preparedGuidanceWorkspace = null;
          preparedGuidanceText = null;
        });
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
    onChanged: creating
        ? null
        : (v) {
            setState(() {
              workspaceId = v;
              guidanceQuestions = null;
              preparedGuidanceWorkspace = null;
              preparedGuidanceText = null;
            });
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
                        onPressed: creating ? null : () => builder(t.key),
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
  Widget creationEntry() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final canGenerate = platform?.aiAvailable == true;
          final selectedWorkspace = workspaceId;
          final theme = Theme.of(context);
          final createButton = ValueListenableBuilder<TextEditingValue>(
            valueListenable: prompt,
            builder: (context, value, _) => FilledButton.icon(
              key: const ValueKey('create-app'),
              onPressed:
                  creating ||
                      guidanceQuestions != null ||
                      (canGenerate && value.text.trim().isEmpty)
                  ? null
                  : () {
                      if (canGenerate) {
                        builder('volunteer', generate: true);
                      } else {
                        setState(() => page = 1);
                      }
                    },
              icon: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(canGenerate ? Icons.arrow_upward : Icons.grid_view),
              label: Text(
                creating
                    ? 'Checking your idea…'
                    : canGenerate
                    ? 'Create app'
                    : 'Browse templates',
              ),
            ),
          );
          return Column(
            children: [
              SizedBox(height: compact ? 12 : 36),
              const Icon(
                Icons.spa_outlined,
                color: Color(0xff276c61),
                size: 34,
              ),
              const SizedBox(height: 20),
              Text(
                'What would you like to build?',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: compact ? 34 : 46,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Describe your idea. Bring it to life, then make it your own.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xff617069),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xffd7ddd7)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0825332e),
                      blurRadius: 28,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('app-idea'),
                        controller: prompt,
                        enabled: !creating,
                        minLines: 3,
                        maxLines: 7,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'An app for my book club to track books, share notes, and plan our next read…',
                          hintMaxLines: 4,
                          semanticCounterText:
                              'Describe the app you want to build',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (guidanceQuestions != null &&
                          guidanceWorkspace == selectedWorkspace)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IdeaGuidancePanel(
                            key: guidancePanelKey,
                            composer: prompt,
                            sourceText: guidanceSource!,
                            contextId: 'workspace:$guidanceWorkspace',
                            currentContext: () => 'workspace:$workspaceId',
                            questions: guidanceQuestions!,
                            usedFallback: guidanceFallback,
                            notice: guidanceNotice,
                            onUseAnswers: (combined) {
                              setState(() {
                                guidanceQuestions = null;
                                preparedGuidanceWorkspace = selectedWorkspace;
                                preparedGuidanceText = combined;
                              });
                              prompt.value = TextEditingValue(
                                text: combined,
                                selection: TextSelection.collapsed(
                                  offset: combined.length,
                                ),
                              );
                            },
                            onContinueOriginal: () {
                              setState(() {
                                guidanceQuestions = null;
                                preparedGuidanceWorkspace = selectedWorkspace;
                                preparedGuidanceText = prompt.text.trim();
                              });
                              unawaited(builder('volunteer', generate: true));
                            },
                            onEditIdea: () =>
                                setState(() => guidanceQuestions = null),
                          ),
                        ),
                      if (compact)
                        Align(
                          alignment: Alignment.centerRight,
                          child: createButton,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Start with an idea. Refine it together.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xff617069),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            createButton,
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final starter in const [
                    (
                      'Daily planner',
                      Icons.today_outlined,
                      'Build a daily planner where I can organize tasks by day, set priorities, and track what I finish.',
                    ),
                    (
                      'Reading journal',
                      Icons.menu_book_outlined,
                      'Build a reading journal to track books I want to read, what I am reading, and my notes and ratings.',
                    ),
                    (
                      'Shared chores',
                      Icons.home_outlined,
                      'Build a shared chores app for my household with assigned tasks, due dates, and a view of what still needs doing.',
                    ),
                    (
                      'Volunteer shifts',
                      Icons.people_outline,
                      'Build an app for volunteers to browse upcoming shifts, see available places, and sign up together.',
                    ),
                  ])
                    ActionChip(
                      avatar: Icon(starter.$2, size: 16),
                      label: Text(starter.$1),
                      onPressed: creating
                          ? null
                          : () {
                              prompt.value = TextEditingValue(
                                text: starter.$3,
                                selection: TextSelection.collapsed(
                                  offset: starter.$3.length,
                                ),
                              );
                            },
                      backgroundColor: const Color(0xfff7f6f2),
                      side: const BorderSide(color: Color(0xffdfe4dc)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!canGenerate)
                Text(
                  '${platform?.aiMode ?? 'AI creation is unavailable'}. Choose a template to start building.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else
                TextButton(
                  onPressed: creating ? null : () => setState(() => page = 1),
                  child: const Text('Or start with a template'),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget appCard(AppManifest app) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => open(app.appId),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            icon(app.specJson),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.archived
                        ? 'Archived'
                        : AppSpec.parse(app.specJson!).requires.contains(
                            'capacity.v1',
                          )
                        ? '${app.availablePlaces} places available'
                        : '${app.recordCount} ${app.recordCount == 1 ? 'record' : 'records'}',
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );

  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      creationEntry(),
      const SizedBox(height: 56),
      Text('Your apps', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      if (apps.where((a) => a.pinned).isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Your next idea belongs here. Create an app to get started.',
          ),
        ),
      LayoutBuilder(
        builder: (context, c) {
          final pinned = apps.where((a) => a.pinned).toList();
          final columns = c.maxWidth < 650 ? 1 : 3;
          return Column(
            children: [
              for (var start = 0; start < pinned.length; start += columns)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: start + columns < pinned.length ? 16 : 0,
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) const SizedBox(width: 16),
                          Expanded(
                            child: start + column < pinned.length
                                ? appCard(pinned[start + column])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
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
