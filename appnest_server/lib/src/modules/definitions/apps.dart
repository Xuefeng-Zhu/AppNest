import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import '../runtime/access.dart';

class Apps {
  static Future<List<WorkspaceInfo>> workspaces(Session s) async {
    final id = actor(s);
    var memberships = await WorkspaceMember.db.find(
      s,
      where: (t) => t.actorId.equals(id),
      limit: 100,
    );
    if (memberships.isEmpty) {
      await createWorkspace(s, 'My workspace', personal: true);
      memberships = await WorkspaceMember.db.find(
        s,
        where: (t) => t.actorId.equals(id),
        limit: 100,
      );
    }
    final result = <WorkspaceInfo>[];
    for (final m in memberships) {
      final w = await Workspace.db.findById(s, m.workspaceId);
      if (w != null) {
        result.add(WorkspaceInfo(id: w.id!, name: w.name, role: m.role));
      }
    }
    return result;
  }

  static Future<int> createWorkspace(
    Session s,
    String name, {
    bool personal = false,
  }) => validated(
    () => s.db.transaction((tx) async {
      // Serialize bootstrap per actor without retaining network-spanning locks.
      await s.db.unsafeQuery(
        'SELECT pg_advisory_xact_lock(hashtextextended(@actor, 0))',
        parameters: QueryParameters.named({'actor': actor(s)}),
        transaction: tx,
      );
      if (personal) {
        final existing = await Workspace.db.findFirstRow(
          s,
          where: (t) => t.ownerId.equals(actor(s)) & t.personal.equals(true),
          transaction: tx,
        );
        if (existing != null) return existing.id!;
      }
      if (await WorkspaceMember.db.count(
            s,
            where: (t) => t.actorId.equals(actor(s)),
            transaction: tx,
          ) >=
          100) {
        fail('quotaExceeded', 'Workspace limit reached.');
      }
      final w = await Workspace.db.insertRow(
        s,
        Workspace(
          name: str(name, 'workspace name', max: 80),
          ownerId: actor(s),
          personal: personal,
          createdAt: clock(),
        ),
        transaction: tx,
      );
      await WorkspaceMember.db.insertRow(
        s,
        WorkspaceMember(workspaceId: w.id!, actorId: actor(s), role: 'owner'),
        transaction: tx,
      );
      return w.id!;
    }),
  );
  static List<TemplateInfo> templates() => starterTemplates().entries
      .map(
        (e) => TemplateInfo(
          key: e.key,
          name: e.value.name,
          specJson: e.value.canonical,
          description: switch (e.key) {
            'reading' => 'Keep your reading life in one place.',
            'chores' => 'Make shared responsibilities clear.',
            'planner' =>
              'Plan today, track tasks, and choose personal reminders.',
            _ => 'Bring people together, one place at a time.',
          },
        ),
      )
      .toList();
  static Future<int> instantiate(
    Session s,
    int workspaceId,
    String templateKey,
  ) => create(
    s,
    workspaceId,
    starterTemplates()[templateKey] ??
        (throw const SpecException('Unknown template')),
  );
  static Future<int> create(Session s, int workspaceId, AppSpec spec) =>
      s.db.transaction((tx) async {
        await workspaceAccess(s, workspaceId, tx: tx);
        await reserveAppSlot(s, workspaceId, tx);
        final app = await MiniApp.db.insertRow(
          s,
          MiniApp(
            workspaceId: workspaceId,
            ownerId: actor(s),
            name: spec.name,
            createdAt: clock(),
          ),
          transaction: tx,
        );
        final version = await AppVersion.db.insertRow(
          s,
          AppVersion(
            appId: app.id!,
            workspaceId: workspaceId,
            number: 1,
            specJson: spec.canonical,
            candidateHash: spec.hash,
            publisherId: actor(s),
            createdAt: clock(),
          ),
          transaction: tx,
        );
        app.activeVersionId = version.id;
        await MiniApp.db.updateRow(s, app, transaction: tx);
        await AppShortcut.db.insertRow(
          s,
          AppShortcut(appId: app.id!, actorId: actor(s)),
          transaction: tx,
        );
        await changed(s, Access(app, 'owner'), 'instantiate', tx);
        return app.id!;
      });
  static Future<List<AppManifest>> list(Session s, int workspaceId) async {
    await workspaceAccess(s, workspaceId);
    // One bounded authorization-aware query for every launcher summary.
    final rows = await s.db.unsafeQuery(
      '''SELECT a.id,a."workspaceId",a.name,a."activeVersionId",a.archived,
      CASE WHEN a."ownerId"=@actor THEN 'owner' ELSE g.role END,
      EXISTS(SELECT 1 FROM nest_shortcut p WHERE p."appId"=a.id AND p."actorId"=@actor),
      (SELECT count(*) FROM nest_record r WHERE r."appId"=a.id AND NOT r.deleted),
      (SELECT coalesce(sum(p.capacity-p.allocated),0)::bigint FROM nest_pool p WHERE p."appId"=a.id),v."specJson",
      (SELECT coalesce(json_agg(u."ruleId" ORDER BY u."ruleId"),'[]'::json)::text FROM nest_automation u WHERE u."appId"=a.id AND u.enabled)
      FROM nest_app a LEFT JOIN nest_grant g ON g."appId"=a.id AND g."actorId"=@actor AND NOT g.revoked
      JOIN nest_version v ON v.id=a."activeVersionId"
      WHERE a."workspaceId"=@workspace AND (a."ownerId"=@actor OR g.id IS NOT NULL) ORDER BY a.id DESC LIMIT 100''',
      parameters: QueryParameters.named({
        'actor': actor(s),
        'workspace': workspaceId,
      }),
    );
    return rows
        .map(
          (r) => AppManifest(
            appId: r[0] as int,
            workspaceId: r[1] as int,
            name: r[2] as String,
            versionId: r[3] as int?,
            archived: r[4] as bool,
            role: r[5] as String,
            pinned: r[6] as bool,
            recordCount: r[7] as int,
            availablePlaces: r[8] as int,
            specJson: r[9] as String,
            approvedRuleIds: List<String>.from(
              jsonDecode(r[10] as String) as List,
            ),
          ),
        )
        .toList();
  }

  static Future<AppManifest> manifest(Session s, int id) =>
      s.db.transaction((tx) async {
        final a = await access(s, id, tx: tx, lock: true),
            spec = await a.spec(s, tx: tx);
        final rules = await Automation.db.find(
          s,
          where: (t) => t.appId.equals(id) & t.enabled.equals(true),
          transaction: tx,
        );
        return AppManifest(
          appId: id,
          workspaceId: a.app.workspaceId,
          name: a.app.name,
          versionId: a.app.activeVersionId,
          specJson: spec.canonical,
          role: a.role,
          archived: a.app.archived,
          pinned:
              await AppShortcut.db.findFirstRow(
                s,
                where: (t) => t.appId.equals(id) & t.actorId.equals(actor(s)),
                transaction: tx,
              ) !=
              null,
          recordCount: 0,
          availablePlaces: 0,
          approvedRuleIds: rules.map((rule) => rule.ruleId).toList()..sort(),
        );
      });

  static Future<int> remix(Session s, int appId, int workspaceId) async {
    final a = await access(s, appId);
    return create(s, workspaceId, await a.spec(s));
  }

  static Future<void> pin(Session s, int appId, bool pinned) =>
      s.db.transaction((tx) async {
        await access(s, appId, tx: tx, lock: true);
        await AppShortcut.db.deleteWhere(
          s,
          where: (t) => t.appId.equals(appId) & t.actorId.equals(actor(s)),
          transaction: tx,
        );
        if (pinned) {
          await AppShortcut.db.insertRow(
            s,
            AppShortcut(appId: appId, actorId: actor(s)),
            transaction: tx,
          );
        }
      });
  static Future<void> archive(Session s, int appId) =>
      s.db.transaction((tx) async {
        final a = await access(s, appId, tx: tx, lock: true);
        if (a.role != 'owner') {
          fail('forbidden', 'Only the owner can archive this app.');
        }
        a.app.archived = true;
        await changed(s, a, 'archive', tx);
      });
}
