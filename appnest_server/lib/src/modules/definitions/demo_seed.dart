import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_idp_server/core.dart';
import 'package:serverpod_auth_idp_server/providers/email.dart';

import '../../generated/protocol.dart';
import '../runtime/access.dart';
import '../runtime/commands.dart';
import '../collaboration/sharing.dart';
import 'apps.dart';

class DemoSeed {
  static const password = 'AppNest-local-demo-2026!';
  static Future<void> run(Session s) async {
    if (s.serverpod.runMode != 'development') {
      throw StateError('Demo seeding is development-only.');
    }
    final ids = <String>[];
    for (final name in ['morgan', 'alex', 'sam']) {
      final email = '$name@appnest.local';
      var account = await EmailAccount.db.findFirstRow(
        s,
        where: (t) => t.email.equals(email),
      );
      if (account == null) {
        final user = await AuthServices.instance.authUsers.create(s);
        await AuthServices.instance.emailIdp.admin.createEmailAuthentication(
          s,
          authUserId: user.id,
          email: email,
          password: password,
        );
        account = await EmailAccount.db.findFirstRow(
          s,
          where: (t) => t.email.equals(email),
        );
      }
      ids.add(account!.authUserId.toString());
      s.updateAuthenticated(
        AuthenticationInfo(ids.last, {}, authId: 'development-seed'),
      );
      await Apps.workspaces(s);
    }
    s.updateAuthenticated(
      AuthenticationInfo(ids.first, {}, authId: 'development-seed'),
    );
    final existing = await Workspace.db.findFirstRow(
      s,
      where: (t) => t.ownerId.equals(ids.first) & t.name.equals('AppNest demo'),
    );
    final workspace =
        existing?.id ?? await Apps.createWorkspace(s, 'AppNest demo');
    for (final entry in starterTemplates().entries) {
      var app = await MiniApp.db.findFirstRow(
        s,
        where: (t) =>
            t.workspaceId.equals(workspace) & t.name.equals(entry.value.name),
      );
      final id = app?.id ?? await Apps.instantiate(s, workspace, entry.key);
      app = await MiniApp.db.findById(s, id);
      final spec = entry.value,
          col = spec.collections.first,
          create = spec.actions.firstWhere(
            (a) => a.capability == 'records.create.v1',
          );
      for (var i = 0; i < 3; i++) {
        final data = syntheticRecords(col)[i];
        for (final field in col.fields) {
          if (field.type == FieldType.member) data[field.id] = ids.first;
          if (field.type == FieldType.timestamp) {
            data[field.id] = clock()
                .add(Duration(days: i + 1))
                .toIso8601String();
          }
        }
        for (final b in col.behaviors.where((b) => b.type == 'workflow.v1')) {
          data[b.fieldId!] = col.field(b.fieldId!).choices.first;
        }
        // Stable idempotency key makes repeat seeds non-destructive, including changed clock values.
        final receipt = await ActionReceipt.db.findFirstRow(
          s,
          where: (t) =>
              t.appId.equals(id) &
              t.actorId.equals(ids.first) &
              t.idempotencyKey.equals('seed-$i'),
        );
        if (receipt == null) {
          await Commands.execute(
            s,
            ActionRequest(
              appId: id,
              actionId: create.id,
              expectedDefinitionVersionId: app!.activeVersionId!,
              input: {
                'data': data,
                if (col.behaviors.any((b) => b.type == 'capacity.v1'))
                  'capacity': i == 0 ? 1 : 3,
              },
              idempotencyKey: 'seed-$i',
            ),
          );
        }
      }
      if (spec.policyPresetRequest != 'personalTracker.v1') {
        for (final member in ids.skip(1)) {
          if (await MiniAppGrant.db.findFirstRow(
                s,
                where: (t) => t.appId.equals(id) & t.actorId.equals(member),
              ) !=
              null) {
            continue;
          }
          final token = await Sharing.invite(s, id, 'member', member);
          s.updateAuthenticated(
            AuthenticationInfo(member, {}, authId: 'development-seed'),
          );
          await Sharing.accept(s, token);
          s.updateAuthenticated(
            AuthenticationInfo(ids.first, {}, authId: 'development-seed'),
          );
        }
      }
    }
    for (final t in Apps.templates()) {
      if (await Template.db.findFirstRow(
            s,
            where: (r) => r.key.equals(t.key),
          ) ==
          null) {
        await Template.db.insertRow(
          s,
          Template(
            key: t.key,
            specJson: t.specJson,
            description: t.description,
          ),
        );
      }
    }
    s.updateAuthenticated(null);
    s.log('development_seed_complete accounts=3 templates=3');
  }
}
