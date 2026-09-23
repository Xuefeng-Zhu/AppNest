part of '../appnest_renderer.dart';

class _LegacyMiniAppRuntime extends StatefulWidget {
  final RuntimeAdapter adapter;
  const _LegacyMiniAppRuntime({required this.adapter});
  @override
  State<_LegacyMiniAppRuntime> createState() => __LegacyMiniAppRuntimeState();
}

class __LegacyMiniAppRuntimeState extends State<_LegacyMiniAppRuntime>
    with WidgetsBindingObserver {
  late String viewId;
  RuntimePage? page;
  Object? error;
  bool loading = true, fetching = false, dirty = false, reconnecting = false;
  StreamSubscription<void>? subscription;
  Timer? refreshTimer;
  Timer? reconnectTimer;
  String? filterChoice;
  String search = '';
  RuntimeAdapter get adapter => widget.adapter;
  ViewSpec get view => adapter.spec.views.firstWhere((v) => v.id == viewId);
  @override
  void initState() {
    super.initState();
    viewId = adapter.spec.views.first.id;
    WidgetsBinding.instance.addObserver(this);
    connect();
    refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refresh(),
    );
  }

  void connect() {
    reconnectTimer?.cancel();
    subscription?.cancel();
    subscription = adapter.watch().listen(
      (_) {
        if (fetching) {
          dirty = true;
        } else {
          refresh();
        }
      },
      onError: (Object e) {
        if (mounted)
          setState(() {
            error = e;
            page = null;
            reconnecting = true;
          });
        reconnectTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) connect();
        });
      },
      onDone: () {
        if (mounted) setState(() => reconnecting = true);
        reconnectTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) connect();
        });
      },
    );
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) connect();
  }

  @override
  void dispose() {
    subscription?.cancel();
    refreshTimer?.cancel();
    reconnectTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh({bool next = false}) async {
    if (fetching) {
      dirty = true;
      return;
    }
    fetching = true;
    try {
      do {
        dirty = false;
        final col = adapter.spec.collection(view.collectionId);
        final choice = col.fields
            .where((f) => f.type == FieldType.choice)
            .firstOrNull;
        final result = await adapter.query(view.collectionId, {
          'limit': 50,
          'filters': [
            if (search.isNotEmpty && view.titleFieldId != null)
              {
                'fieldId': view.titleFieldId,
                'operator': 'contains',
                'value': search,
              },
            if (filterChoice != null && choice != null)
              {'fieldId': choice.id, 'operator': 'eq', 'value': filterChoice},
          ],
          if (next && page?.cursor != null) 'cursor': page!.cursor,
        });
        if (mounted)
          setState(() {
            page = result;
            error = null;
            loading = false;
            reconnecting = false;
          });
      } while (dirty && mounted);
    } catch (e) {
      if (mounted)
        setState(() {
          error = e;
          loading = false;
          page = null;
        });
    } finally {
      fetching = false;
    }
  }

  Future<void> run(ActionSpec action, RuntimeItem? item) async {
    final edit = _VisualEditScope.of(context);
    if (edit != null) {
      edit.onSelect(MiniAppEditTarget(MiniAppEditKind.section, view.id));
      return;
    }
    Map<String, dynamic>? input;
    final col = adapter.spec.collection(action.collectionId);
    if (action.capability == 'records.create.v1' ||
        action.capability == 'records.patch.v1') {
      input = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => RecordForm(
          collection: col,
          adapter: adapter,
          record: item,
          initial: item?.data,
          members: adapter.members,
          capacity: item?.capacity,
        ),
      );
    } else if (action.capability == 'capacity.configure.v1') {
      input = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ValueDialog(
          label: 'Capacity',
          initial: '${item?.capacity ?? 1}',
          numeric: true,
        ),
      );
      if (input != null)
        input = {'capacity': int.tryParse(input['value'].toString())};
    } else if (action.capability == 'assignment.assign.v1' ||
        action.capability == 'workflow.transition.v1') {
      final b = col.behavior(action.behaviorId!);
      final values = action.capability == 'assignment.assign.v1'
          ? await adapter.members()
          : b.transitions[item?.data[b.fieldId]] ?? [];
      if (!mounted) return;
      input = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) =>
            _ChoiceDialog(label: action.label, values: values),
      );
    } else {
      input = {};
    }
    if (input == null || !mounted) return;
    // Never imply a place is reserved until execute has returned successfully.
    final key = 'ui-${DateTime.now().microsecondsSinceEpoch}-${item?.id ?? 0}';
    setState(() => loading = true);
    try {
      await adapter.execute(action, item, input, key);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adapter.preview ? 'Simulated in preview' : 'Saved'),
          ),
        );
      await refresh();
    } catch (e) {
      if (mounted)
        setState(() {
          error = e;
          loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = adapter.spec.collection(view.collectionId),
        choice = col.fields
            .where((f) => f.type == FieldType.choice)
            .firstOrNull;
    final create = adapter.spec.actions
        .where(
          (a) =>
              a.collectionId == col.id &&
              a.capability == 'records.create.v1' &&
              adapter.permits(a),
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adapter.preview && _VisualEditScope.of(context) == null)
          const MaterialBanner(
            content: Text(
              'Preview · Synthetic records. Actions stay in this preview.',
            ),
            actions: [SizedBox.shrink()],
          ),
        if (adapter.readOnly)
          MaterialBanner(
            content: Text(
              adapter.role == 'viewer'
                  ? 'Read-only · Viewer access'
                  : 'Archived · This app is read-only',
            ),
            actions: const [SizedBox.shrink()],
          ),
        if (reconnecting)
          TextButton.icon(
            onPressed: connect,
            icon: const Icon(Icons.sync),
            label: const Text('Reconnecting — refresh connection'),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: viewId,
                items: adapter.spec.views
                    .map(
                      (v) =>
                          DropdownMenuItem(value: v.id, child: Text(v.label)),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null)
                    setState(() {
                      viewId = id;
                      page = null;
                      filterChoice = null;
                      search = '';
                    });
                  refresh();
                },
              ),
              if (create != null)
                FilledButton.icon(
                  onPressed: loading ? null : () => run(create, null),
                  icon: const Icon(Icons.add),
                  label: Text(create.label),
                ),
              if (choice != null && _VisualEditScope.of(context) == null)
                DropdownButton<String>(
                  hint: const Text('All statuses'),
                  value: filterChoice,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All statuses'),
                    ),
                    ...choice.choices.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => filterChoice = v == '' ? null : v);
                    refresh();
                  },
                ),
              IconButton(
                tooltip: 'Refresh records',
                onPressed: () => refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_VisualEditScope.of(context) == null &&
            view.titleFieldId != null &&
            col.field(view.titleFieldId!).type == FieldType.text)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter records…',
              ),
              onSubmitted: (v) {
                search = v;
                refresh();
              },
            ),
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Could not complete the request. $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _EditTarget(
            target: MiniAppEditTarget(MiniAppEditKind.section, view.id),
            child: _VisualEditScope.of(context) != null && view.type == 'form'
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _editForm(adapter.spec, view),
                  )
                : page == null
                ? Center(
                    child: Text(loading ? 'Loading…' : 'Refresh to try again.'),
                  )
                : view.type == 'form'
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          view.label,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        for (final a
                            in view.actionIds
                                .map(adapter.spec.action)
                                .where(
                                  (a) =>
                                      a.capability == 'records.create.v1' &&
                                      adapter.permits(a),
                                ))
                          ActionButton(
                            action: a,
                            onPressed: loading ? null : () => run(a, null),
                          ),
                      ],
                    ),
                  )
                : page!.items.isEmpty
                ? const Center(
                    child: Text('A fresh start. Add the first record.'),
                  )
                : AbsorbPointer(
                    absorbing: loading,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (view.type == 'summary')
                            Summary(
                              items: page!.items,
                              total: page!.total,
                              groupField: view.groupByFieldId,
                            )
                          else if (view.type == 'board')
                            StatusBoard(
                              spec: adapter.spec,
                              view: view,
                              items: page!.items,
                              onAction: run,
                            )
                          else
                            RecordList(
                              spec: adapter.spec,
                              view: view,
                              items: page!.items,
                              onAction: run,
                            ),
                          const SizedBox(height: 12),
                          Text('${page!.total} records'),
                          if (page!.cursor != null)
                            TextButton(
                              onPressed: () => refresh(next: true),
                              child: const Text('Next page'),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
