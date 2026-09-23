import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../modules/builder/builder.dart';
import '../modules/builder/provider.dart';
import '../modules/runtime/access.dart';

class BuilderEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;
  Future<PlatformInfo> platform(Session session) async => PlatformInfo(
    aiAvailable: ChatCompletionProvider.configured(session) != null,
    aiMode: ChatCompletionProvider.configured(session) == null
        ? 'Template mode — AI provider not configured'
        : 'Live AI',
    development: session.serverpod.runMode == 'development',
    actorId: actor(session),
  );
  Future<BuilderSnapshot> begin(
    Session session,
    int workspaceId,
    String templateKey,
    int? appId,
  ) => Builder.begin(session, workspaceId, templateKey, appId);
  Future<BuilderSnapshot> get(Session session, int draftId) =>
      Builder.get(session, draftId);
  Future<List<GuidanceQuestion>> suggestQuestions(
    Session session,
    String idea,
    int? workspaceId,
    int? draftId,
  ) => Builder.suggestQuestions(session, idea, workspaceId, draftId);
  Future<BuilderSnapshot> patch(
    Session session,
    int draftId,
    int mutation,
    String patchJson,
  ) => Builder.patch(session, draftId, mutation, patchJson);
  Future<BuilderSnapshot> generate(
    Session session,
    int draftId,
    int mutation,
    String request, {
    bool? startFromScratch,
  }) => Builder.generate(
    session,
    draftId,
    mutation,
    request,
    startFromScratch: startFromScratch ?? true,
  );
  Future<int> publish(Session session, PublishRequest request) =>
      Builder.publish(session, request);
  Future<BuilderSnapshot> abandonFailedEdit(
    Session session,
    int draftId,
    int mutation,
    int jobId,
  ) => Builder.abandonFailedEdit(session, draftId, mutation, jobId);
  Future<List<ActivityItem>> runs(Session session, int appId) async {
    final a = await access(session, appId);
    a.requireBuilder();
    final rows = await AutomationRun.db.find(
      session,
      where: (t) => t.appId.equals(appId),
      limit: 100,
    );
    return rows
        .map(
          (r) => ActivityItem(
            id: r.id!,
            action: 'Reminder · ${r.dueAt.toIso8601String()}',
            createdAt: r.createdAt,
            status: r.status,
          ),
        )
        .toList();
  }
}
