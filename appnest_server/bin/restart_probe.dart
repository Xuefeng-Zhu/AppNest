import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_server/src/generated/serverpod.dart';
import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';

Future<void> main() async {
  final tag = Platform.environment['APPNEST_RESTART_TAG'],
      phase = Platform.environment['APPNEST_RESTART_PHASE'];
  if (tag == null || !{'write', 'read'}.contains(phase)) {
    throw StateError('Use scripts/restart_smoke.dart.');
  }
  final pod = Serverpod(
    ['--mode', 'test', '--apply-migrations'],
    configOverride: (c) => c.copyWith(
      database: PostgresDatabaseConfig.embedded(
        name: 'appnest_restart_smoke',
        dataPath: '.serverpod/restart/pgdata',
        maxConnectionCount: 10,
      ),
    ),
  );
  await pod.start();
  final s = await pod.createSession();
  s.updateAuthenticated(
    AuthenticationInfo(
      'restart-$tag',
      {},
      authId: 'test-only-internal-session',
    ),
  );
  await Integrity.ensure(s);
  if (phase == 'write') {
    final w = await Apps.createWorkspace(s, 'Restart $tag'),
        app = await Apps.instantiate(s, w, 'volunteer'),
        m = await Apps.manifest(s, app);
    final r = await Commands.execute(
      s,
      ActionRequest(
        appId: app,
        actionId: 'addShift',
        expectedDefinitionVersionId: m.versionId!,
        input: {
          'data': {
            'title': 'Accelerated restart proof',
            'startsAt': clock().toIso8601String(),
          },
          'capacity': 1,
        },
        idempotencyKey: 'record',
      ),
    );
    await Commands.execute(
      s,
      ActionRequest(
        appId: app,
        actionId: 'join',
        targetRecordId: r.recordId,
        expectedDefinitionVersionId: m.versionId!,
        input: {},
        idempotencyKey: 'claim',
      ),
    );
    await Automation.db.insertRow(
      s,
      Automation(
        appId: app,
        workspaceId: w,
        ruleId: 'smoke',
        ruleVersion: 1,
        ruleJson: canonicalJson({
          'id': 'smoke',
          'trigger': {
            'type': 'beforeTimestamp',
            'collectionId': 'shifts',
            'fieldId': 'startsAt',
            'offsetSeconds': 0,
          },
          'effect': {'type': 'notifyActiveClaimants', 'channel': 'inApp'},
        }),
        enabled: true,
        executionActorId: actor(s),
        activateExisting: false,
        activatedAt: clock().subtract(const Duration(days: 1)),
      ),
    );
    final events = await OutboxEvent.db.find(
      s,
      where: (t) => t.appId.equals(app),
    );
    for (final e in events) {
      await Worker.plan(s, e.id!);
    }
    if (await AutomationRun.db.count(s, where: (t) => t.appId.equals(app)) !=
        1) {
      throw StateError('Missing committed run.');
    }
    stdout.writeln(
      'Committed run. Exiting immediately before scheduling a wake-up.',
    );
    exit(0); // Deliberate process interruption, after database commit.
  }
  final w = (await Workspace.db.findFirstRow(
    s,
    where: (t) => t.name.equals('Restart $tag'),
  ))!;
  final app = (await MiniApp.db.findFirstRow(
    s,
    where: (t) => t.workspaceId.equals(w.id!),
  ))!;
  final run = (await AutomationRun.db.findFirstRow(
    s,
    where: (t) => t.appId.equals(app.id!),
  ))!;
  await Worker.drain(s);
  await Worker.execute(s, run.id!);
  if (await Notification.db.count(s, where: (t) => t.appId.equals(app.id!)) !=
      1) {
    throw StateError('Notification was lost or duplicated.');
  }
  if ((await ResourcePool.db.findFirstRow(
        s,
        where: (t) => t.appId.equals(app.id!),
      ))!.allocated !=
      1) {
    throw StateError('Claim did not survive restart.');
  }
  stdout.writeln(
    'PASS: reconciler recovered the committed run; duplicate wake-up was harmless.',
  );
  await s.close();
  await pod.shutdown(exitProcess: false);
}
