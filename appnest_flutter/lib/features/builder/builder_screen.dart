import 'dart:async';
import 'dart:convert';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter/material.dart';

import '../../client.dart';
import 'page_editor.dart';

class BuilderScreen extends StatefulWidget {
  final BuilderSnapshot initial;
  const BuilderScreen({super.key, required this.initial});
  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  late BuilderSnapshot draft;
  late PreviewRuntimeAdapter preview;
  final prompt = TextEditingController();
  Timer? timer;
  Object? error;
  bool busy = false;
  bool? ai;
  final enabled = <String>{};
  @override
  void initState() {
    super.initState();
    draft = widget.initial;
    enabled.addAll(draft.enabledRuleIds);
    preview = PreviewRuntimeAdapter(AppSpec.parse(draft.candidateJson));
    client.builder.platform().then((p) {
      if (mounted) setState(() => ai = p.aiAvailable);
    });
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if ({'queued', 'generating', 'validating'}.contains(draft.stage)) poll();
    });
  }

  void update(BuilderSnapshot d) {
    if (!mounted) return;
    setState(() {
      if (d.candidateHash != draft.candidateHash) {
        preview.dispose();
        preview = PreviewRuntimeAdapter(AppSpec.parse(d.candidateJson));
        enabled.removeWhere(
          (id) => !preview.spec.automationRequests.any((r) => r.id == id),
        );
      }
      draft = d;
    });
  }

  Future<void> poll() async {
    try {
      update(await client.builder.get(draft.draftId));
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    preview.dispose();
    prompt.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> manual() async {
    final label = TextEditingController(), choice = TextEditingController();
    var type = 'RenameLabel',
        target = 'app',
        collection = preview.spec.collections.first.id,
        fieldType = 'text';
    final patch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Make a small edit'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: type,
                    items:
                        ['RenameLabel', 'AddField', 'AddChoice', 'ReorderView']
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                    onChanged: (v) => set(() => type = v!),
                  ),
                  if (type == 'RenameLabel')
                    DropdownButtonFormField<String>(
                      initialValue: target,
                      items: [
                        const DropdownMenuItem(
                          value: 'app',
                          child: Text('App name'),
                        ),
                        ...preview.spec.collections.expand(
                          (c) => c.fields.map(
                            (f) => DropdownMenuItem(
                              value: f.id,
                              child: Text(f.label),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => target = v!,
                    ),
                  if (type == 'AddField' || type == 'AddChoice')
                    DropdownButton<String>(
                      value: collection,
                      items: preview.spec.collections
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => set(() => collection = v!),
                    ),
                  if (type == 'AddField')
                    DropdownButton<String>(
                      value: fieldType,
                      items: FieldType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.name,
                              child: Text(t.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => set(() => fieldType = v!),
                    ),
                  if (type == 'AddChoice')
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Choice field',
                      ),
                      items: preview.spec
                          .collection(collection)
                          .fields
                          .where((f) => f.type == FieldType.choice)
                          .map(
                            (f) => DropdownMenuItem(
                              value: f.id,
                              child: Text(f.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => target = v!,
                    ),
                  if (type != 'ReorderView')
                    TextField(
                      controller: label,
                      decoration: InputDecoration(
                        labelText: type == 'AddChoice' ? 'New choice' : 'Label',
                      ),
                    ),
                  if (type == 'AddField' && fieldType == 'choice')
                    TextField(
                      controller: choice,
                      decoration: const InputDecoration(
                        labelText: 'Choices, separated by commas',
                      ),
                    ),
                  if (type == 'ReorderView')
                    const Text(
                      'Move the last view to the first position. Existing view IDs stay unchanged.',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, switch (type) {
                  'RenameLabel' => {
                    'type': type,
                    'targetId': target,
                    'label': label.text,
                  },
                  'AddField' => {
                    'type': type,
                    'collectionId': collection,
                    'field': {
                      'label': label.text,
                      'type': fieldType,
                      'required': false,
                      if (fieldType == 'choice')
                        'choices': choice.text
                            .split(',')
                            .map((x) => x.trim())
                            .toList(),
                    },
                  },
                  'AddChoice' => {
                    'type': type,
                    'collectionId': collection,
                    'fieldId': target,
                    'choice': label.text,
                  },
                  _ => {
                    'type': 'ReorderView',
                    'viewIds': [
                      preview.spec.views.last.id,
                      ...preview.spec.views
                          .take(preview.spec.views.length - 1)
                          .map((v) => v.id),
                    ],
                  },
                });
              },
              child: const Text('Update preview'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    choice.dispose();
    if (patch != null) {
      await perform(
        () async => update(
          await client.builder.patch(
            draft.draftId,
            draft.mutation,
            jsonEncode(patch),
          ),
        ),
      );
    }
  }

  Future<void> publish() async {
    final reviewed = draft;
    final reviewedSpec = AppSpec.parse(reviewed.candidateJson);
    final rules = enabled.toList()..sort();
    final scope = <int>{};
    final candidates = <RuntimeRecord>[];
    if (reviewed.baseVersionId != null && rules.isNotEmpty) {
      try {
        final collections = reviewedSpec.automationRequests
            .where((r) => enabled.contains(r.id))
            .map((r) => r.collectionId)
            .toSet();
        for (final collection in collections) {
          candidates.addAll(
            (await client.runtime.query(
              reviewed.appId,
              collection,
              jsonEncode({'limit': 50}),
            )).records,
          );
        }
      } catch (e) {
        if (mounted) setState(() => error = e);
        return;
      }
    }
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setReview) => AlertDialog(
          title: const Text('Publish this exact preview?'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...reviewed.changes.map((c) => Text('• $c')),
                  const SizedBox(height: 16),
                  Text('Policy request: ${reviewedSpec.policyPresetRequest}'),
                  Text('Capabilities: ${reviewedSpec.requires.join(', ')}'),
                  Text(
                    'Enabled reminders: ${rules.isEmpty ? 'None' : rules.join(', ')}',
                  ),
                  const Text(
                    'Existing records are preserved. Unchanged, enabled reminders retain their schedules. New or changed rules enroll only new records and the records you explicitly select below.',
                  ),
                  if (candidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Optional: enroll existing records (up to 50 per collection shown). This may create a reminder immediately if its due time has passed.',
                    ),
                    for (final record in candidates)
                      CheckboxListTile(
                        value: scope.contains(record.id),
                        title: Text(
                          '#${record.id} · ${(record.data as Map).values.firstOrNull ?? record.collectionId}',
                        ),
                        onChanged: (v) => setReview(() {
                          if (v == true) {
                            scope.add(record.id);
                          } else {
                            scope.remove(record.id);
                          }
                        }),
                      ),
                  ],
                  const Text(
                    'This publishes structure only. Synthetic preview records are never copied.',
                  ),
                  SelectableText(
                    'Candidate: ${reviewed.candidateHash}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back to preview'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (yes != true) return;
    if (draft.candidateHash != reviewed.candidateHash ||
        draft.mutation != reviewed.mutation) {
      setState(
        () => error = 'The preview changed during review. Review the updated preview before publishing.',
      );
      return;
    }
    await perform(() async {
      await client.builder.publish(
        PublishRequest(
          draftId: reviewed.draftId,
          candidateHash: reviewed.candidateHash,
          expectedCurrentVersionId: reviewed.baseVersionId,
          enabledRuleIds: rules,
          activateExistingRecordIds: scope.toList()..sort(),
          reviewHash: hashJson({
            'candidateHash': reviewed.candidateHash,
            'enabledRuleIds': rules,
            'activateExistingRecordIds': scope.toList()..sort(),
          }),
          idempotencyKey:
              'publish-${reviewed.draftId}-${reviewed.candidateHash}',
        ),
      );
      if (mounted) {
        Navigator.pop(context, reviewed.appId);
      }
    });
  }

  Widget chat() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Shape your app', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          ai == true
              ? 'Describe what to create or change. AI proposes; you approve.'
              : 'Template mode · AI provider not configured. Your preview and manual edits still work.',
        ),
        const SizedBox(height: 20),
        Text('Status: ${draft.stage}'),
        ...draft.diagnostics.map((d) => Text(d)),
        const SizedBox(height: 16),
        TextField(
          controller: prompt,
          maxLines: 5,
          maxLength: 4000,
          decoration: const InputDecoration(
            hintText: 'Describe an app or a small change…',
          ),
        ),
        FilledButton(
          onPressed: busy || ai != true
              ? null
              : () => perform(
                  () async => update(
                    await client.builder.generate(
                      draft.draftId,
                      draft.mutation,
                      prompt.text,
                      startFromScratch: widget.initial.jobId != null,
                    ),
                  ),
                ),
          child: const Text('Generate preview'),
        ),
        TextButton.icon(
          onPressed: busy ? null : manual,
          icon: const Icon(Icons.tune),
          label: const Text('Edit manually'),
        ),
        TextButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final patch = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => PageEditor(spec: preview.spec),
                  );
                  if (patch != null) {
                    await perform(
                      () async => update(
                        await client.builder.patch(
                          draft.draftId,
                          draft.mutation,
                          jsonEncode(patch),
                        ),
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.dashboard_customize_outlined),
          label: const Text('Pages & navigation'),
        ),
        if (error != null)
          Text(
            '$error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
  Widget changes() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Changes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...draft.changes.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(c),
          ),
        ),
        const Divider(),
        const Text('Approve reminders'),
        ...preview.spec.automationRequests.map(
          (r) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r.id),
            subtitle: Text(
              '${r.offsetSeconds ~/ 60} minutes before · In-app only',
            ),
            value: enabled.contains(r.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                enabled.add(r.id);
              } else {
                enabled.remove(r.id);
              }
            }),
          ),
        ),
        const Text(
          'Reminders require approval. In review, you can explicitly enroll existing records; otherwise only new records join new rules.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || draft.stage != 'preview ready' ? null : publish,
          child: const Text('Review & publish'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Builder · ${preview.spec.name}')),
    body: LayoutBuilder(
      builder: (context, c) {
        final live = MiniAppRuntime(
          key: ValueKey(draft.candidateHash),
          adapter: preview,
        );
        if (c.maxWidth < 950) {
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Chat'),
                    Tab(text: 'Preview'),
                    Tab(text: 'Changes'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SingleChildScrollView(child: chat()),
                      live,
                      changes(),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 280, child: SingleChildScrollView(child: chat())),
            const VerticalDivider(width: 1),
            Expanded(child: live),
            const VerticalDivider(width: 1),
            SizedBox(width: 260, child: changes()),
          ],
        );
      },
    ),
  );
}
