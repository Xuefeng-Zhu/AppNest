import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter/material.dart';

import '../../client.dart';
import '../media/image_upload.dart';
import 'builder_chat.dart';
import 'idea_guidance.dart';
import 'page_editor.dart';
import 'visual_edit_session.dart';
import 'visual_inspector.dart';

class BuilderScreen extends StatefulWidget {
  final BuilderSnapshot initial;
  final String? initialPrompt;
  final bool startFromScratch;
  const BuilderScreen({
    super.key,
    required this.initial,
    this.initialPrompt,
    this.startFromScratch = false,
  });
  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  late BuilderSnapshot draft;
  late PreviewRuntimeAdapter preview;
  final prompt = TextEditingController();
  final guidancePanelKey = GlobalKey();
  final conversationScroll = ScrollController();
  final conversation = <BuilderMessage>[];
  Timer? timer;
  Object? error;
  Object? platformError;
  bool busy = false;
  bool assessing = false;
  List<GuidanceQuestion>? guidanceQuestions;
  String? guidanceSource;
  String? guidanceContextId;
  bool guidanceFallback = false;
  String? guidanceNotice;
  String? preparedGuidanceContext;
  String? preparedGuidanceText;
  String? assessedIdea;
  String? assessedContext;
  bool polling = false;
  bool mobilePreview = false;
  late bool hasPreview;
  String? lastRequest;
  bool? ai;
  final enabled = <String>{};
  final previewController = MiniAppController();
  VisualEditSession? visualSession;
  MiniAppEditTarget? visualTarget;
  bool visualEditing = false;
  bool changingTarget = false;
  bool allowPop = false;
  BuildContext? inspectorSheet;
  final inspectorRevision = ValueNotifier(0);
  int inspectorReset = 0;
  final _previewImages = <String, Uint8List>{};
  final _loadingPreviewImages = <String>{};

  PreviewRuntimeAdapter newPreview(AppSpec spec) {
    final adapter = PreviewRuntimeAdapter(
      spec,
      pickImage: pickAppImage,
      imageAssets: _previewImages,
    );
    unawaited(loadPreviewImages(spec));
    return adapter;
  }

  Future<void> loadPreviewImages(AppSpec spec) async {
    for (final id
        in spec.views
            .map((view) => view.options['imageAssetId'])
            .whereType<String>()
            .toSet()) {
      if (_previewImages.containsKey(id) || !_loadingPreviewImages.add(id)) {
        continue;
      }
      try {
        final bytes = await client.media.readImage(draft.appId, id, 'display');
        if (!mounted) return;
        final image = Uint8List.sublistView(bytes);
        _previewImages[id] = image;
        preview.setImageAsset(id, image);
      } catch (_) {
        // The shared renderer shows an unavailable image; no public URL fallback.
      } finally {
        _loadingPreviewImages.remove(id);
      }
    }
  }

  Future<String?> uploadDraftImage() async {
    final bytes = await pickAppImage();
    if (bytes == null || !mounted) return null;
    final id = await uploadAppImage(
      client,
      bytes,
      appId: draft.appId,
      draftId: draft.draftId,
    );
    final sanitized = await client.media.readImage(draft.appId, id, 'display');
    if (mounted) {
      final image = Uint8List.sublistView(sanitized);
      _previewImages[id] = image;
      preview.setImageAsset(id, image);
    }
    return id;
  }

  bool get generating =>
      {'queued', 'generating', 'validating'}.contains(draft.stage);
  bool get canEdit =>
      !busy &&
      !generating &&
      hasPreview &&
      draft.stage != 'stale' &&
      draft.publishedVersionId == null;
  bool get canPublish =>
      canEdit &&
      draft.stage == 'preview ready' &&
      draft.publishedVersionId == null;

  @override
  void initState() {
    super.initState();
    draft = widget.initial;
    enabled.addAll(draft.enabledRuleIds);
    preview = newPreview(AppSpec.parse(draft.candidateJson));
    hasPreview =
        !widget.startFromScratch ||
        (draft.stage == 'preview ready' && draft.jobId != null);
    lastRequest = widget.initialPrompt;
    prompt.addListener(onPromptChanged);
    if (lastRequest?.isNotEmpty == true) {
      conversation.add(BuilderMessage(text: lastRequest!, fromUser: true));
    }
    if (draft.stage == 'failed') {
      conversation.add(
        BuilderMessage(
          text: builderFailureMessage(
            draft.diagnostics,
            hasPreview: hasPreview,
          ),
        ),
      );
    } else if (hasPreview) {
      conversation.add(
        BuilderMessage(
          text: widget.initialPrompt == null
              ? 'Your app is ready to shape. Try the preview, then tell me what you would like to change.'
              : 'Your first preview is ready. Try it out, then ask for a change.',
          changes: widget.initialPrompt == null
              ? const []
              : describeChanges(draft),
        ),
      );
    }
    loadPlatform();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (generating) poll();
    });
  }

  Future<void> loadPlatform() async {
    try {
      final platform = await client.builder.platform();
      if (mounted) {
        setState(() {
          ai = platform.aiAvailable;
          platformError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => platformError = e);
    }
  }

  void update(BuilderSnapshot d) {
    if (!mounted || d.mutation < draft.mutation) return;
    final completed = generating && d.stage == 'preview ready';
    final failed =
        d.stage == 'failed' &&
        (draft.stage != 'failed' ||
            d.jobId != draft.jobId ||
            d.mutation != draft.mutation);
    setState(() {
      if (d.mutation != draft.mutation ||
          d.candidateHash != draft.candidateHash) {
        guidanceQuestions = null;
      }
      if (d.candidateHash != draft.candidateHash) {
        final nextSpec = AppSpec.parse(d.candidateJson);
        try {
          // AI changes and direct controls share the same presentation guard.
          // Keeping this adapter retains sample data, location and filters.
          preview.applyPresentationSpec(nextSpec);
          unawaited(loadPreviewImages(nextSpec));
        } on Object catch (issue) {
          if (issue is! SpecException && issue is! ArgumentError) rethrow;
          preview.dispose();
          preview = newPreview(nextSpec);
        }
        enabled.removeWhere(
          (id) => !preview.spec.automationRequests.any((r) => r.id == id),
        );
      }
      draft = d;
      if (d.stage == 'preview ready') hasPreview = true;
      if (completed) {
        conversation.add(
          BuilderMessage(
            text: 'Your preview is ready. Try it out, or tell me what to adjust next.',
            changes: describeChanges(d),
          ),
        );
      } else if (failed) {
        conversation.add(
          BuilderMessage(
            text: builderFailureMessage(d.diagnostics, hasPreview: hasPreview),
          ),
        );
      }
    });
    if (completed || failed) scrollConversation();
  }

  Future<void> poll() async {
    if (polling || busy) return;
    polling = true;
    final mutation = draft.mutation;
    try {
      final next = await client.builder.get(draft.draftId);
      if (!mounted || busy || mutation != draft.mutation) return;
      update(next);
      setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      polling = false;
    }
  }

  void scrollConversation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && conversationScroll.hasClients) {
        conversationScroll.animateTo(
          conversationScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String currentGuidanceContext() =>
      '${draft.draftId}:${draft.mutation}:${draft.candidateHash}';

  void onPromptChanged() {
    if (guidanceQuestions != null && prompt.text.trim() != guidanceSource) {
      setState(() => guidanceQuestions = null);
    }
  }

  void showGuidance(
    List<GuidanceQuestion> questions,
    String request,
    String contextId, {
    required bool fallback,
    String? notice,
  }) {
    setState(() {
      guidanceQuestions = questions;
      guidanceSource = request;
      guidanceContextId = contextId;
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

  Future<void> send({String? retry}) async {
    final request = (retry ?? prompt.text).trim();
    if (busy ||
        assessing ||
        generating ||
        draft.stage == 'stale' ||
        ai != true ||
        request.isEmpty) {
      return;
    }
    setState(() => assessing = true);
    try {
      if (!await finishVisualEdit() || !mounted) return;
      final contextId = currentGuidanceContext();
      if (retry == null &&
          !(preparedGuidanceContext == contextId &&
              preparedGuidanceText != null &&
              request.startsWith(preparedGuidanceText!)) &&
          !(assessedContext == contextId && assessedIdea == request) &&
          canAssessIdea(request)) {
        try {
          final questions = cleanGuidanceQuestions(
            await client.builder.suggestQuestions(request, null, draft.draftId),
          );
          if (!mounted ||
              currentGuidanceContext() != contextId ||
              prompt.text.trim() != request) {
            return;
          }
          if (questions == null || questions.isNotEmpty) {
            showGuidance(
              questions ?? builtInEditGuidanceQuestions,
              request,
              contextId,
              fallback: questions == null,
              notice: questions == null
                  ? 'AI questions were incomplete. Try these built-in questions.'
                  : null,
            );
            return;
          }
          assessedContext = contextId;
          assessedIdea = request;
        } catch (e) {
          if (!mounted ||
              currentGuidanceContext() != contextId ||
              prompt.text.trim() != request) {
            return;
          }
          if (!canOfferBuiltInGuidance(e)) {
            setState(() => error = e);
            return;
          }
          showGuidance(
            builtInEditGuidanceQuestions,
            request,
            contextId,
            fallback: true,
            notice: 'AI questions are unavailable. Try these built-in questions, or continue with your original idea.',
          );
          return;
        }
      }
      if (!mounted ||
          currentGuidanceContext() != contextId ||
          (retry == null && prompt.text.trim() != request)) {
        return;
      }
      await perform(() async {
        final next = await client.builder.generate(
          draft.draftId,
          draft.mutation,
          request,
          startFromScratch: widget.startFromScratch,
        );
        if (!mounted) return;
        setState(() {
          conversation.add(BuilderMessage(text: request, fromUser: true));
          lastRequest = request;
          preparedGuidanceContext = null;
          preparedGuidanceText = null;
          guidanceQuestions = null;
          prompt.clear();
        });
        update(next);
        scrollConversation();
      });
    } finally {
      if (mounted) setState(() => assessing = false);
    }
  }

  @override
  void dispose() {
    inspectorRevision.dispose();
    visualSession?.dispose();
    previewController.dispose();
    timer?.cancel();
    preview.dispose();
    prompt.dispose();
    conversationScroll.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
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
    if (!await finishVisualEdit() || !mounted) return;
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
    if (!await finishVisualEdit()) return;
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
                  ...describeChanges(reviewed).map((c) => Text('• $c')),
                  const SizedBox(height: 16),
                  Text(switch (reviewedSpec.policyPresetRequest) {
                    'personalTracker.v1' => 'Personal app · You manage its records. Shared members can view them.',
                    'groupWorkflow.v1' => 'Shared workflow · Members can create and update records and use approved actions.',
                    _ => 'Shared sign-ups · Members can claim and release their own places.',
                  }),
                  Text(
                    'Enabled reminders: ${rules.isEmpty ? 'None' : rules.map((id) => reminderName(id)).join(', ')}',
                  ),
                  for (final rule in reviewedSpec.automationRequests.where(
                    (rule) => rules.contains(rule.id),
                  ))
                    Text(reminderDescription(rule, reviewedSpec)),
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

  String? get errorMessage {
    final issue = error ?? platformError;
    if (issue == null) return null;
    if (issue is NestError) return issue.message;
    if (issue is String) return issue;
    return 'Couldn’t connect to AppNest. Your request is still here. Check your connection and try again.';
  }

  Future<void> editPages() async {
    if (!await finishVisualEdit() || !mounted) return;
    final patch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PageEditor(
        spec: preview.spec,
        uploadImage: uploadDraftImage,
        preview: preview,
        location: previewController.location,
      ),
    );
    if (patch != null && mounted) {
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

  Widget chat() {
    return BuilderChat(
      messages: conversation,
      scrollController: conversationScroll,
      controller: prompt,
      stage: draft.stage,
      generating: generating,
      busy: busy || assessing,
      assessing: assessing,
      aiAvailable: ai,
      hasPreview: hasPreview,
      error: errorMessage,
      diagnostics: draft.diagnostics,
      onSend: send,
      guidanceQuestions: guidanceQuestions,
      guidancePanelKey: guidancePanelKey,
      guidanceSource: guidanceSource,
      guidanceContextId: guidanceContextId,
      guidanceFallback: guidanceFallback,
      guidanceNotice: guidanceNotice,
      guidanceContext: currentGuidanceContext,
      onUseGuidanceAnswers: (combined) {
        setState(() {
          guidanceQuestions = null;
          preparedGuidanceContext = currentGuidanceContext();
          preparedGuidanceText = combined;
        });
        prompt.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
      },
      onContinueOriginal: () {
        setState(() {
          guidanceQuestions = null;
          preparedGuidanceContext = currentGuidanceContext();
          preparedGuidanceText = prompt.text.trim();
        });
        unawaited(send());
      },
      onEditIdea: () => setState(() => guidanceQuestions = null),
      onRetry:
          !generating &&
              draft.stage != 'stale' &&
              ai == true &&
              lastRequest != null
          ? () => send(retry: lastRequest)
          : null,
      onReconnect: () async {
        await loadPlatform();
        await poll();
      },
    );
  }

  Future<void> showChanges() async {
    if (!await finishVisualEdit() || !mounted) return;
    final review = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ready to make it yours?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review your app and choose which reminders to enable before publishing to your workspace.',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'In this preview',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ...describeChanges(draft).map(
                    (change) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(change)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  Text(
                    'Reminders',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (preview.spec.automationRequests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No reminders requested by this app.'),
                    ),
                  ...preview.spec.automationRequests.map(
                    (rule) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(reminderName(rule.id)),
                      subtitle: Text(reminderDescription(rule, preview.spec)),
                      value: enabled.contains(rule.id),
                      onChanged: canEdit
                          ? (value) {
                              setState(() {
                                if (value == true) {
                                  enabled.add(rule.id);
                                } else {
                                  enabled.remove(rule.id);
                                }
                              });
                              refresh(() {});
                            }
                          : null,
                    ),
                  ),
                  if (preview.spec.automationRequests.isNotEmpty)
                    const Text(
                      'Reminders need your approval. You can choose existing records to include in the next step.',
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: canPublish
                        ? () => Navigator.pop(context, true)
                        : null,
                    icon: const Icon(Icons.publish_outlined),
                    label: const Text('Review & publish'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (review == true && mounted && canPublish) await publish();
  }

  String reminderName(String id) {
    final rule = preview.spec.automationRequests.firstWhere((r) => r.id == id);
    final collection = preview.spec.collection(rule.collectionId);
    return '${collection.label} · ${collection.field(rule.fieldId).label}';
  }

  List<String> describeChanges(BuilderSnapshot snapshot) {
    final spec = AppSpec.parse(snapshot.candidateJson);
    if (snapshot.baseVersionId == null) {
      return [
        'Create ${spec.name}',
        'Track ${spec.collections.map((collection) => collection.label).join(', ')}',
        if (spec.navigation != null)
          'Pages: ${spec.navigation!.pages.map((page) => page.title).join(', ')}'
        else
          'Views: ${spec.views.map((view) => view.label).join(', ')}',
        if (spec.automationRequests.isNotEmpty)
          '${spec.automationRequests.length} ${spec.automationRequests.length == 1 ? 'reminder' : 'reminders'} available for your approval',
      ];
    }
    return {
      for (final change in snapshot.changes)
        change.startsWith('Request capability:')
            ? 'Update supported app features'
            : change,
    }.toList();
  }

  String reminderDescription(AutomationSpec rule, AppSpec spec) {
    final recipient = switch (rule.effect) {
      'notifyOwner' => 'App owner',
      'notifyAssignee' => 'Assigned member',
      _ => 'Members with an active place',
    };
    final seconds = rule.offsetSeconds;
    final timing = seconds == 0
        ? 'At the selected time'
        : seconds % 60 == 0
        ? '${seconds ~/ 60} minutes before'
        : '$seconds seconds before';
    final condition = rule.condition;
    final when = condition == null
        ? ''
        : ' · When ${spec.collection(rule.collectionId).field(condition.fieldId).label} is ${condition.value}';
    return '$recipient · $timing · In-app only$when';
  }

  Future<bool> flushVisualEdit() async {
    final session = visualSession;
    if (session == null || await session.flush()) return true;
    if (!mounted) return false;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your changes haven’t saved'),
        content: Text(session.status),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing'),
          ),
          if (!session.conflict && session.validationError == null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'retry'),
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard local changes'),
          ),
        ],
      ),
    );
    if (decision == 'retry') return session.flush(retry: true);
    if (decision == 'discard') return reloadVisualEdit();
    return false;
  }

  Future<bool> reloadVisualEdit() async {
    try {
      final latest = await visualSession!.reload();
      if (!mounted) return false;
      update(latest);
      if (!canEdit) return await finishVisualEdit();
      setState(() {
        visualTarget = const MiniAppEditTarget(MiniAppEditKind.app, 'app');
        inspectorReset++;
      });
      inspectorRevision.value++;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn’t reload the draft. Your local edits are still here.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> finishVisualEdit() async {
    if (!await flushVisualEdit() || !mounted) return false;
    final sheet = inspectorSheet;
    inspectorSheet = null;
    if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
    setState(() {
      visualEditing = false;
      visualTarget = null;
    });
    visualSession?.dispose();
    visualSession = null;
    return true;
  }

  Future<void> closeMobileInspector() async {
    if (!await flushVisualEdit() || !mounted) return;
    final sheet = inspectorSheet;
    inspectorSheet = null;
    if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
  }

  Future<void> selectVisualTarget(MiniAppEditTarget target) async {
    if (changingTarget || !canEdit) return;
    changingTarget = true;
    try {
      if (!await flushVisualEdit() || !mounted) return;
      if (!canEdit) return;
      // An explicit reload can remove the definition the user had clicked.
      try {
        switch (target.kind) {
          case MiniAppEditKind.app:
            break;
          case MiniAppEditKind.page:
            preview.spec.page(target.id);
          case MiniAppEditKind.section:
            preview.spec.view(target.id);
          case MiniAppEditKind.field:
            preview.spec.collection(target.collectionId!).field(target.id);
        }
        if (target.pageId != null) preview.spec.page(target.pageId!);
      } catch (_) {
        target = const MiniAppEditTarget(MiniAppEditKind.app, 'app');
      }
      if (!visualEditing) {
        if (!await previewController.canLeave() || !mounted) return;
        visualSession = VisualEditSession(
          snapshot: draft,
          read: () => client.builder.get(draft.draftId),
          write: (mutation, patch) =>
              client.builder.patch(draft.draftId, mutation, patch),
          onSaved: (next, _) => update(next),
        );
      }
      setState(() {
        visualEditing = true;
        visualTarget = target;
      });
      inspectorRevision.value++;
      if (MediaQuery.sizeOf(context).width < 850 && inspectorSheet == null) {
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            enableDrag: false,
            constraints: const BoxConstraints(maxWidth: 640),
            builder: (sheetContext) {
              inspectorSheet = sheetContext;
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) closeMobileInspector();
                },
                child: SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(sheetContext).height * .8,
                    child: ListenableBuilder(
                      listenable: inspectorRevision,
                      builder: (_, _) => inspector(mobile: true),
                    ),
                  ),
                ),
              );
            },
          ).whenComplete(() => inspectorSheet = null),
        );
      }
    } finally {
      changingTarget = false;
    }
  }

  Widget inspector({bool mobile = false}) =>
      visualSession == null || visualTarget == null
      ? const SizedBox.shrink()
      : VisualInspector(
          key: ValueKey((visualTarget, inspectorReset)),
          target: visualTarget!,
          session: visualSession!,
          mobile: mobile,
          onClose: () => mobile ? closeMobileInspector() : finishVisualEdit(),
          onReload: () => reloadVisualEdit(),
          uploadImage: uploadDraftImage,
          preview: preview,
          location: previewController.location,
          onSelectTarget: selectVisualTarget,
        );

  Widget previewPane() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xffe2e5df))),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 500) {
              return Row(
                children: [
                  if (visualEditing)
                    IconButton(
                      tooltip: 'Done editing',
                      onPressed: canEdit ? finishVisualEdit : null,
                      icon: const Icon(Icons.check, size: 18),
                    )
                  else
                    TextButton.icon(
                      onPressed: canEdit
                          ? () => selectVisualTarget(
                              const MiniAppEditTarget(
                                MiniAppEditKind.app,
                                'app',
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.ads_click, size: 18),
                      label: const Text('Edit'),
                    ),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('open-appearance'),
                      onPressed: canEdit
                          ? () => selectVisualTarget(
                              const MiniAppEditTarget(
                                MiniAppEditKind.app,
                                'app',
                              ),
                            )
                          : null,
                      child: const Text('Appearance'),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Preview options',
                    onSelected: (value) => setState(() {
                      if (value == 'desktop') mobilePreview = false;
                      if (value == 'mobile') mobilePreview = true;
                      if (value == 'reset') {
                        preview.dispose();
                        preview = newPreview(
                          AppSpec.parse(draft.candidateJson),
                        );
                      }
                    }),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'desktop',
                        child: Text('Desktop preview'),
                      ),
                      const PopupMenuItem(
                        value: 'mobile',
                        child: Text('Mobile preview'),
                      ),
                      if (hasPreview)
                        PopupMenuItem(
                          value: 'reset',
                          enabled: !busy && !visualEditing,
                          child: const Text('Reset sample data'),
                        ),
                    ],
                  ),
                ],
              );
            }
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: canEdit
                          ? () => visualEditing
                                ? finishVisualEdit()
                                : selectVisualTarget(
                                    const MiniAppEditTarget(
                                      MiniAppEditKind.app,
                                      'app',
                                    ),
                                  )
                          : null,
                      icon: Icon(
                        visualEditing ? Icons.check : Icons.ads_click,
                        size: 18,
                      ),
                      label: Text(visualEditing ? 'Done editing' : 'Edit'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('open-appearance'),
                      onPressed: canEdit
                          ? () => selectVisualTarget(
                              const MiniAppEditTarget(
                                MiniAppEditKind.app,
                                'app',
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('Appearance'),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Desktop preview',
                      isSelected: !mobilePreview,
                      onPressed: () => setState(() => mobilePreview = false),
                      icon: const Icon(
                        Icons.desktop_windows_outlined,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mobile preview',
                      isSelected: mobilePreview,
                      onPressed: () => setState(() => mobilePreview = true),
                      icon: const Icon(Icons.smartphone_outlined, size: 20),
                    ),
                    if (hasPreview)
                      IconButton(
                        tooltip: 'Reset sample data',
                        onPressed: busy || visualEditing
                            ? null
                            : () => setState(() {
                                preview.dispose();
                                preview = newPreview(
                                  AppSpec.parse(draft.candidateJson),
                                );
                              }),
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      Expanded(
        child: hasPreview
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final inset = constraints.maxWidth > 600 ? 24.0 : 10.0;
                  return Container(
                    color: const Color(0xffe9ede7),
                    padding: EdgeInsets.all(inset),
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: mobilePreview ? 390 : double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          mobilePreview ? 24 : 12,
                        ),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(color: Colors.white),
                          child: MiniAppRuntime(
                            key: ObjectKey(preview),
                            adapter: preview,
                            controller: previewController,
                            editConfiguration: visualEditing
                                ? MiniAppEditConfiguration(
                                    selected: visualTarget,
                                    onSelect: selectVisualTarget,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            color: Color(0xffe2eeea),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            generating
                                ? Icons.auto_awesome_outlined
                                : Icons.edit_note,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          generating
                              ? 'Your app is taking shape'
                              : 'Let’s shape your first preview',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          generating
                              ? 'Your interactive preview will appear here when it’s ready. Then you can try it and keep building together.'
                              : 'Send a description in the chat to build your app. A ready preview will appear here.',
                          textAlign: TextAlign.center,
                        ),
                        if (generating) ...[
                          const SizedBox(height: 32),
                          const LinearProgressIndicator(minHeight: 3),
                          const SizedBox(height: 12),
                          Text(builderStageLabel(draft.stage)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
      if (hasPreview)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            generating
                ? 'Building your changes · Showing your last ready preview'
                : visualEditing
                ? 'Click a heading, section or field to edit · Autosaved to draft'
                : 'Interactive preview · Sample data · Only published changes reach your app',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || !visualEditing,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await finishVisualEdit() && mounted) {
        setState(() => allowPop = true);
        if (context.mounted) Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      // The inspector sheet scrolls around the keyboard itself. Keep the
      // underlying preview at full height while that keyboard is open.
      resizeToAvoidBottomInset: !visualEditing,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: canEdit
                  ? () => selectVisualTarget(
                      const MiniAppEditTarget(MiniAppEditKind.app, 'app'),
                    )
                  : null,
              child: Text(
                hasPreview ? preview.spec.name : 'New app',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              draft.stage == 'preview ready'
                  ? 'Unpublished changes'
                  : builderStageLabel(draft.stage),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Edit app',
            enabled: canEdit,
            onSelected: (value) {
              if (value == 'manual') manual();
              if (value == 'pages') editPages();
              if (value == 'changes') showChanges();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manual', child: Text('Edit manually')),
              PopupMenuItem(value: 'pages', child: Text('Pages & navigation')),
              PopupMenuItem(value: 'changes', child: Text('Changes')),
            ],
            icon: const Icon(Icons.tune_outlined, size: 20),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: canPublish ? showChanges : null,
              child: const Text('Publish'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 850) {
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Chat'),
                      Tab(text: 'Preview'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(children: [chat(), previewPane()]),
                  ),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: constraints.maxWidth < 1100 ? 330 : 380,
                child: visualEditing ? inspector() : chat(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: previewPane()),
            ],
          );
        },
      ),
    ),
  );
}
