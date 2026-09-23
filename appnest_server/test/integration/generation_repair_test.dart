import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const _repairKey = '_appnestRepair';
const _privateMarker = 'PRIVATE_REJECTED_GENERATION_TEST_ONLY';

/// Records only synthetic test outputs. There is no configured-provider access.
class _CapturingProvider implements AiProvider {
  final List<String> outputs;
  final Map<String, dynamic> usage;
  final List<String?> rejected = [];
  final List<List<String>> diagnostics = [];
  _CapturingProvider(this.outputs, {this.usage = const {}});

  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    rejected.add(rejectedOutput);
    this.diagnostics.add(List.of(diagnostics));
    final index = rejected.length - 1;
    return AiResult(
      outputs[index < outputs.length ? index : outputs.length - 1],
      'repair-test-only',
      'deterministic',
      usage,
    );
  }
}

Future<GenerationJob> _queue(
  Session session,
  BuilderSnapshot draft, {
  int attempts = 0,
}) async {
  final job = await GenerationJob.db.insertRow(
    session,
    GenerationJob(
      appId: draft.appId,
      draftId: draft.draftId,
      actorId: actor(session),
      mutation: draft.mutation,
      status: 'queued',
      requestText: 'Synthetic repair isolation test',
      mode: 'create',
      promptVersion: 'repair-test',
      attempts: attempts,
      nextAttemptAt: clock(),
      diagnostics: '',
      usageJson: '{}',
      createdAt: clock(),
      updatedAt: clock(),
    ),
  );
  final row = (await AppDraft.db.findById(session, draft.draftId))!
    ..activeJobId = job.id;
  await AppDraft.db.updateRow(session, row);
  return job;
}

Future<GenerationJob> _stored(Session session, GenerationJob job) async =>
    (await GenerationJob.db.findById(session, job.id!))!;

Map<String, dynamic> _usage(GenerationJob job) =>
    Map<String, dynamic>.from(jsonDecode(job.usageJson) as Map);

Map<String, dynamic> _context(GenerationJob job) =>
    Map<String, dynamic>.from(_usage(job)[_repairKey] as Map);

void _expectNoLeak(BuilderSnapshot current, BuilderSnapshot original) {
  expect(current.candidateJson, original.candidateJson);
  expect(current.candidateHash, original.candidateHash);
  expect(jsonEncode(current.toJson()), isNot(contains(_privateMarker)));
  expect(current.diagnostics.join('\n'), isNot(contains(_privateMarker)));
}

void main() {
  withServerpod('Private generation repair retries', (sessions, endpoints) {
    Future<(Session, BuilderSnapshot)> fixture() async {
      final owner = sessions
          .copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'repair-${randomToken()}',
              {},
            ),
          )
          .build();
      final workspace = await Apps.createWorkspace(owner, 'Repair tests');
      return (owner, await Builder.begin(owner, workspace, 'volunteer', null));
    }

    final invalidSpec = starterTemplates()['planner']!.toJson()
      ..['name'] = _privateMarker
      ..['requires'] = <String>[];
    for (final (label, rejectedText) in [
      ('invalid JSON', 'not JSON: $_privateMarker'),
      ('invalid AppSpec', jsonEncode(invalidSpec)),
    ]) {
      test(
        '$label stays private and repairs the same job on its next attempt',
        () async {
          final (owner, draft) = await fixture();
          final job = await _queue(owner, draft);
          final valid = starterTemplates()['planner']!;
          final provider = _CapturingProvider(
            [rejectedText, valid.canonical],
            usage: {
              'completion_tokens': 42,
              _repairKey: {'output': 'provider-controlled collision'},
            },
          );
          await Worker.generate(owner, job.id!, provider: provider);
          final rejectedJob = await _stored(owner, job);
          expect(rejectedJob.status, 'queued');
          expect(rejectedJob.attempts, 1);
          expect(_context(rejectedJob), {
            'jobId': job.id,
            'draftId': draft.draftId,
            'mutation': draft.mutation,
            'baseCandidateHash': draft.candidateHash,
            'baseVersionId': draft.baseVersionId,
            'mode': 'create',
            'attempt': 1,
            'output': rejectedText,
          });
          expect(_usage(rejectedJob)['completion_tokens'], 42);
          _expectNoLeak(await Builder.get(owner, draft.draftId), draft);
          expect(rejectedJob.diagnostics, isNot(contains(_privateMarker)));
          expect(provider.rejected, [null]);

          await Worker.generate(owner, job.id!, provider: provider);
          final repairedJob = await _stored(owner, job);
          expect(repairedJob.status, 'preview ready');
          expect(repairedJob.attempts, 2);
          expect(provider.rejected, [null, rejectedText]);
          expect(provider.diagnostics.last, isNotEmpty);
          expect(_usage(repairedJob), {'completion_tokens': 42});
          final repairedDraft = await Builder.get(owner, draft.draftId);
          final expected = valid.patch({
            'type': 'SetAppearance',
            'appearance': {'style': 'clean'},
          }, () => throw StateError('No new IDs'));
          expect(repairedDraft.candidateHash, expected.hash);
          expect(repairedDraft.diagnostics, isEmpty);
          expect(
            jsonEncode(repairedDraft.toJson()),
            isNot(contains(_privateMarker)),
          );
        },
      );
    }

    test('oversized UTF-8 output is never retained for queued repair', () async {
      final (owner, draft) = await fixture();
      final job = await _queue(owner, draft);
      final oversized =
          '$_privateMarker${List.filled(Limits.definitionBytes ~/ 3, '猫').join()}';
      expect(oversized.length, lessThan(Limits.definitionBytes));
      expect(
        utf8.encode(oversized).length,
        greaterThan(Limits.definitionBytes),
      );
      final provider = _CapturingProvider(
        [oversized, starterTemplates()['planner']!.canonical],
        usage: {
          _repairKey: {'output': 'provider-controlled collision'},
        },
      );
      await Worker.generate(owner, job.id!, provider: provider);
      final rejected = await _stored(owner, job);
      expect(rejected.status, 'queued');
      expect(rejected.attempts, 1);
      expect(_usage(rejected), isNot(contains(_repairKey)));
      expect(rejected.usageJson, isNot(contains(_privateMarker)));
      expect(rejected.diagnostics, isNot(contains(_privateMarker)));
      _expectNoLeak(await Builder.get(owner, draft.draftId), draft);
      await Worker.generate(owner, job.id!, provider: provider);
      expect(provider.rejected, [null, null]);
      expect((await _stored(owner, job)).status, 'preview ready');
    });

    test('oversized UTF-8 text in an otherwise valid envelope is ignored', () async {
      final (owner, draft) = await fixture();
      final job = await _queue(owner, draft);
      final provider = _CapturingProvider([
        'invalid JSON $_privateMarker',
        starterTemplates()['planner']!.canonical,
      ]);
      await Worker.generate(owner, job.id!, provider: provider);
      final stored = await _stored(owner, job);
      final usage = _usage(stored);
      final context = _context(stored);
      final oversized =
          '$_privateMarker${List.filled(Limits.definitionBytes ~/ 3, '猫').join()}';
      expect(oversized.length, lessThan(Limits.definitionBytes));
      expect(
        utf8.encode(oversized).length,
        greaterThan(Limits.definitionBytes),
      );
      context['output'] = oversized;
      usage[_repairKey] = context;
      stored.usageJson = jsonEncode(usage);
      await GenerationJob.db.updateRow(owner, stored);
      await Worker.generate(owner, job.id!, provider: provider);
      expect(provider.rejected, [null, null]);
      final completed = await _stored(owner, job);
      expect(completed.status, 'preview ready');
      expect(_usage(completed), isNot(contains(_repairKey)));
      expect(completed.usageJson, isNot(contains(_privateMarker)));
    });

    test('manual edits stale the rejected job and a fresh job gets no prior output', () async {
      final (owner, draft) = await fixture();
      final job = await _queue(owner, draft);
      final prior = _CapturingProvider(['invalid JSON $_privateMarker']);
      await Worker.generate(owner, job.id!, provider: prior);
      expect(_usage(await _stored(owner, job)), contains(_repairKey));
      final changed = await Builder.patch(
        owner,
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'RenameLabel',
          'targetId': 'app',
          'label': 'Manual change to keep',
        }),
      );
      expect(changed.jobId, isNull);
      final notCalled = _CapturingProvider([
        starterTemplates()['planner']!.canonical,
      ]);
      await Worker.generate(owner, job.id!, provider: notCalled);
      expect(notCalled.rejected, isEmpty);
      final stale = await _stored(owner, job);
      expect(stale.status, 'stale');
      expect(_usage(stale), isNot(contains(_repairKey)));
      expect(
        (await Builder.get(owner, draft.draftId)).candidateHash,
        changed.candidateHash,
      );

      final fresh = await _queue(owner, changed);
      final next = _CapturingProvider([
        starterTemplates()['planner']!.canonical,
      ]);
      await Worker.generate(owner, fresh.id!, provider: next);
      expect(next.rejected, [null]);
      expect((await _stored(owner, fresh)).status, 'preview ready');
    });

    for (final field in [
      'jobId',
      'draftId',
      'mutation',
      'baseCandidateHash',
      'baseVersionId',
      'mode',
      'attempt',
    ]) {
      test(
        'repair context with mismatched $field is never sent to the provider',
        () async {
          final (owner, draft) = await fixture();
          final job = await _queue(owner, draft);
          final provider = _CapturingProvider([
            'invalid JSON $_privateMarker',
            starterTemplates()['planner']!.canonical,
          ]);
          await Worker.generate(owner, job.id!, provider: provider);
          final stored = await _stored(owner, job);
          final usage = _usage(stored);
          final context = _context(stored);
          context[field] = switch (field) {
            'baseCandidateHash' => 'different-base-definition',
            'mode' => 'edit',
            'baseVersionId' => 999999,
            'attempt' => 0,
            _ => (context[field] as int) + 999999,
          };
          usage[_repairKey] = context;
          stored.usageJson = jsonEncode(usage);
          await GenerationJob.db.updateRow(owner, stored);
          await Worker.generate(owner, job.id!, provider: provider);
          expect(provider.rejected, [null, null]);
          final completed = await _stored(owner, job);
          expect(completed.status, 'preview ready');
          expect(_usage(completed), isNot(contains(_repairKey)));
        },
      );
    }

    test(
      'third rejected attempt is terminal and erases private repair output',
      () async {
        final (owner, draft) = await fixture();
        final job = await _queue(owner, draft);
        final provider = _CapturingProvider([
          'invalid first $_privateMarker',
          'invalid second $_privateMarker',
          'invalid third $_privateMarker',
        ]);
        for (var attempt = 1; attempt <= Limits.generationAttempts; attempt++) {
          await Worker.generate(owner, job.id!, provider: provider);
          final current = await _stored(owner, job);
          expect(current.attempts, attempt);
          expect(
            current.status,
            attempt == Limits.generationAttempts ? 'failed' : 'queued',
          );
          _expectNoLeak(await Builder.get(owner, draft.draftId), draft);
          if (attempt < Limits.generationAttempts) {
            expect(_context(current)['attempt'], attempt);
            expect(_context(current)['output'], provider.outputs[attempt - 1]);
          } else {
            expect(_usage(current), isNot(contains(_repairKey)));
            expect(current.usageJson, isNot(contains(_privateMarker)));
          }
        }
        expect(provider.rejected, [
          null,
          provider.outputs[0],
          provider.outputs[1],
        ]);
        await Worker.generate(owner, job.id!, provider: provider);
        expect(provider.rejected.length, Limits.generationAttempts);
      },
    );

    test('preclaim attempt limit also erases retained repair context without calling AI', () async {
      final (owner, draft) = await fixture();
      final job = await _queue(owner, draft);
      await Worker.generate(
        owner,
        job.id!,
        provider: _CapturingProvider(['invalid $_privateMarker']),
      );
      final exhausted = await _stored(owner, job)
        ..attempts = Limits.generationAttempts;
      await GenerationJob.db.updateRow(owner, exhausted);
      final provider = _CapturingProvider([
        starterTemplates()['planner']!.canonical,
      ]);
      await Worker.generate(owner, job.id!, provider: provider);
      expect(provider.rejected, isEmpty);
      final terminal = await _stored(owner, job);
      expect(terminal.status, 'failed');
      expect(_usage(terminal), isNot(contains(_repairKey)));
      _expectNoLeak(await Builder.get(owner, draft.draftId), draft);
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}
