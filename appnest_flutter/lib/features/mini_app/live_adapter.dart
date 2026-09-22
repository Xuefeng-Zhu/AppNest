import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_renderer/appnest_renderer.dart';

import 'dart:convert';

class LiveRuntimeAdapter extends RuntimeAdapter {
  final Client client;
  final AppManifest manifest;
  @override
  final AppSpec spec;
  LiveRuntimeAdapter(this.client, this.manifest)
    : spec = AppSpec.parse(manifest.specJson!);
  @override
  bool get preview => false;
  @override
  bool get readOnly =>
      manifest.archived ||
      role == 'viewer' ||
      (role == 'member' && spec.policyPresetRequest == 'personalTracker.v1');
  @override
  String get role => manifest.role;
  @override
  bool permits(ActionSpec a) {
    if (readOnly) return false;
    if (role == 'owner' || role == 'builder') return true;
    if (a.capability == 'records.create.v1' &&
        spec
            .collection(a.collectionId)
            .behaviors
            .any((b) => b.type == 'capacity.v1')) {
      return false;
    }
    return spec.policyPresetRequest == 'groupWorkflow.v1' &&
            {
              'records.create.v1',
              'records.patch.v1',
              'assignment.assign.v1',
              'workflow.transition.v1',
            }.contains(a.capability) ||
        spec.policyPresetRequest == 'groupCapacitySignup.v1' &&
            {'capacity.claim.v1', 'capacity.release.v1'}.contains(a.capability);
  }

  @override
  Future<RuntimePage> query(
    String collectionId,
    Map<String, dynamic> query,
  ) async {
    final current = await client.apps.manifest(manifest.appId);
    manifest.role = current.role;
    manifest.archived = current.archived;
    if (current.versionId != manifest.versionId) {
      throw NestError(
        category: 'staleDefinition',
        message:
            'The app definition changed. Close and reopen the app to refresh.',
      );
    }
    final page = await client.runtime.query(
      manifest.appId,
      collectionId,
      jsonEncode(query),
    );
    return RuntimePage(
      page.records
          .map(
            (r) => RuntimeItem(
              r.id,
              r.collectionId,
              Map<String, dynamic>.from(r.data as Map),
              revision: r.revision,
              capacity: r.capacity,
              allocated: r.allocated,
              claimed: r.claimed,
              allowedActions: r.allowedActions,
            ),
          )
          .toList(),
      page.total,
      page.nextCursor,
    );
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    await client.runtime.execute(
      ActionRequest(
        appId: manifest.appId,
        actionId: action.id,
        targetRecordId: record?.id,
        expectedDefinitionVersionId: manifest.versionId!,
        expectedRecordRevision: record?.revision,
        input: input,
        idempotencyKey: key,
      ),
    );
  }

  @override
  Future<List<String>> members() async => (await client.apps.members(
    manifest.appId,
  )).map((m) => m.actorId).toList();
  @override
  Stream<void> watch() => client.runtime.events(manifest.appId).map((event) {});
}
