import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../modules/runtime/access.dart';
import '../modules/runtime/commands.dart';
import '../modules/runtime/queries.dart';
import '../modules/runtime/aggregates.dart';
import '../modules/collaboration/sharing.dart';

class RuntimeEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;
  Future<RecordPage> query(
    Session session,
    int appId,
    String collectionId,
    String queryJson,
  ) => Queries.query(session, appId, collectionId, queryJson);
  Future<RecordSummary> summary(
    Session session,
    int appId,
    String collectionId,
    String queryJson,
    String groupFieldId,
  ) => Queries.summary(session, appId, collectionId, queryJson, groupFieldId);
  Future<String> aggregate(
    Session session,
    int appId,
    String collectionId,
    String queryJson,
    String aggregateJson,
  ) => Aggregates.aggregate(
    session,
    appId,
    collectionId,
    queryJson,
    aggregateJson,
  );
  Future<List<ReminderState>> reminderState(
    Session session,
    int appId,
    int recordId,
  ) => Queries.reminderState(session, appId, recordId);
  Future<RuntimeRecord> get(Session session, int appId, int recordId) =>
      Queries.get(session, appId, recordId);
  Future<ActionOutcome> execute(Session session, ActionRequest request) =>
      Commands.execute(session, request);
  Future<List<InboxItem>> inbox(Session session) => Sharing.inbox(session);
  Future<void> readNotification(Session session, int id) =>
      Sharing.read(session, id);
  Stream<AppEvent> events(Session session, int appId) async* {
    // Small invalidations only. Recheck grants before every emission and every heartbeat.
    var revision = -1;
    while (true) {
      final a = await access(session, appId);
      if (a.app.controlRevision != revision) {
        revision = a.app.controlRevision;
        yield AppEvent(appId: appId, revision: revision, kind: 'refresh');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
