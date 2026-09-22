import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Unpublished AI generation context', (sessions, endpoints) {
    test(
      'success establishes edit context across later failures and manual edits',
      () async {
        final owner = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'generation-${randomToken()}',
                {},
              ),
            )
            .build();
        final workspace = await Apps.createWorkspace(owner, 'Generation tests');
        var draft = await Builder.begin(owner, workspace, 'volunteer', null);
        Future<String> mode({bool startFromScratch = true}) =>
            owner.db.transaction(
              (tx) async => Builder.generationMode(
                owner,
                (await AppDraft.db.findById(
                  owner,
                  draft.draftId,
                  transaction: tx,
                ))!,
                tx: tx,
                startFromScratch: startFromScratch,
              ),
            );
        Future<void> attempt(
          String output, {
          bool startFromScratch = true,
        }) async {
          final job = await GenerationJob.db.insertRow(
            owner,
            GenerationJob(
              appId: draft.appId,
              draftId: draft.draftId,
              actorId: actor(owner),
              mutation: draft.mutation,
              status: 'queued',
              requestText: 'Synthetic generation context test',
              mode: await mode(startFromScratch: startFromScratch),
              promptVersion: 'test',
              attempts: Limits.generationAttempts - 1,
              nextAttemptAt: clock(),
              diagnostics: '',
              usageJson: '{}',
              createdAt: clock(),
              updatedAt: clock(),
            ),
          );
          final row = (await AppDraft.db.findById(owner, draft.draftId))!
            ..activeJobId = job.id;
          await AppDraft.db.updateRow(owner, row);
          await Worker.generate(
            owner,
            job.id!,
            provider: FakeAiProvider(output),
          );
          draft = await Builder.get(owner, draft.draftId);
        }

        expect(await mode(), 'create');
        await attempt('invalid JSON');
        expect(draft.stage, 'failed');
        expect(await mode(), 'create');
        final planner = starterTemplates()['planner']!;
        await attempt('```json\n${planner.canonical}\n```');
        expect(
          draft.stage,
          'preview ready',
          reason: draft.diagnostics.join('; '),
        );
        expect(draft.candidateHash, planner.hash);
        expect(await mode(), 'edit');
        await attempt('invalid JSON');
        expect(draft.stage, 'failed');
        expect(draft.candidateHash, planner.hash);
        expect(await mode(), 'edit');
        draft = await Builder.patch(
          owner,
          draft.draftId,
          draft.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'todayPage',
            'label': 'My day',
          }),
        );
        expect(draft.jobId, isNull);
        expect(await mode(), 'edit');
        await attempt(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'todayPage',
                'label': 'Focus today',
              },
            ],
          }),
        );
        expect(
          draft.stage,
          'preview ready',
          reason: draft.diagnostics.join('; '),
        );
        expect(
          AppSpec.parse(draft.candidateJson).page('todayPage').title,
          'Focus today',
        );

        // A successful generation in another draft cannot turn this placeholder
        // into an edit request, even when the owner is the same.
        draft = await Builder.begin(owner, workspace, 'volunteer', null);
        expect(await mode(), 'create');
        expect(await mode(startFromScratch: false), 'edit');
        await attempt('invalid JSON', startFromScratch: false);
        expect(draft.stage, 'failed');
        expect(await mode(startFromScratch: false), 'edit');
        final selectedTemplate = AppSpec.parse(draft.candidateJson);
        await attempt(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'app',
                'label': 'Neighborhood Helpers',
              },
            ],
          }),
          startFromScratch: false,
        );
        expect(
          draft.stage,
          'preview ready',
          reason: draft.diagnostics.join('; '),
        );
        final editedTemplate = AppSpec.parse(draft.candidateJson);
        expect(editedTemplate.name, 'Neighborhood Helpers');
        expect(
          editedTemplate.collections.map((c) => c.toJson()).toList(),
          selectedTemplate.collections.map((c) => c.toJson()).toList(),
        );
        expect(
          editedTemplate.views.map((v) => v.toJson()).toList(),
          selectedTemplate.views.map((v) => v.toJson()).toList(),
        );
        expect(await mode(), 'edit');
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}
