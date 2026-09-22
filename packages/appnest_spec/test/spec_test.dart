import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  test(
    'broken view and behavior bindings, version types and policy requests fail',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (j) => j['formatVersion'] = 1.0,
        (j) => j['policyPresetRequest'] = 'administrator',
        (j) => j['views'][0]['collectionId'] = 'missing',
        (j) => j['views'][0]['groupByFieldId'] = 'missing',
        (j) => j['actions'][1]['behaviorId'] = 'missing',
        (j) => j['collections'][0]['fields'][0]['type'] = 'javascript',
        (j) => j['collections'][0]['behaviors'].add({
          'id': 'secondPool',
          'type': 'capacity.v1',
        }),
      ]) {
        final j = starterTemplates()['volunteer']!.toJson();
        change(j);
        expect(
          () => AppSpec.parse(jsonEncode(j)),
          throwsA(isA<SpecException>()),
        );
      }
    },
  );
  test('label edits do not change canonical IDs; required removals and type conversion are rejected', () {
    final base = starterTemplates()['reading']!;
    final renamed = base.patch({
      'type': 'RenameLabel',
      'targetId': 'app',
      'label': 'Plant diary',
    }, () => throw StateError('No ID allocation for labels'));
    expect(base.compatibilityErrors(renamed), isEmpty);
    expect(
      renamed.collections.first.fields.map((f) => f.id),
      base.collections.first.fields.map((f) => f.id),
    );
    final j = base.toJson();
    j['collections'][0]['fields'][0]['type'] = 'integer';
    expect(base.compatibilityErrors(AppSpec.parse(jsonEncode(j))), isNotEmpty);
  });
  test('all families round trip with canonical stable IDs', () {
    for (final s in starterTemplates().values) {
      expect(AppSpec.parse(s.canonical).hash, s.hash);
    }
  });
  test(
    'unknown keys, capabilities, malformed JSON and excessive size fail',
    () {
      final j = starterTemplates()['reading']!.toJson()
        ..['tenantId'] = 'untrusted';
      expect(() => AppSpec.parse(jsonEncode(j)), throwsA(isA<SpecException>()));
      expect(() => AppSpec.parse('not JSON'), throwsA(isA<SpecException>()));
      expect(() => AppSpec.parse(' ' * 131073), throwsA(isA<SpecException>()));
      final unsupported = starterTemplates()['reading']!.toJson();
      (unsupported['requires'] as List).add('arbitrary.code');
      expect(
        () => AppSpec.parse(jsonEncode(unsupported)),
        throwsA(isA<SpecException>()),
      );
    },
  );
  test('semantic patches preserve IDs and compatible optional additions', () {
    final s = starterTemplates()['volunteer']!;
    final next = s.patch({
      'type': 'AddField',
      'collectionId': 'shifts',
      'field': {'label': 'Meeting point', 'type': 'text', 'required': false},
    }, () => 'f_trusted');
    expect(s.compatibilityErrors(next), isEmpty);
    expect(next.collection('shifts').field('title').id, 'title');
    expect(next.collection('shifts').field('f_trusted').label, 'Meeting point');
    final renamed = next.patch({
      'type': 'RenameLabel',
      'targetId': 'title',
      'label': 'Session',
    }, () => 'unused');
    expect(renamed.collection('shifts').field('title').label, 'Session');
    final required = s.patch({
      'type': 'AddField',
      'collectionId': 'shifts',
      'field': {'label': 'Mandatory', 'type': 'text', 'required': true},
    }, () => 'newId');
    expect(s.compatibilityErrors(required), isNotEmpty);
  });
  test('required, null, numeric and timestamp rules', () {
    final col = starterTemplates()['volunteer']!.collections.first;
    expect(
      () => col.normalizeRecord({'title': 'x'}),
      throwsA(isA<SpecException>()),
    );
    final data = col.normalizeRecord({
      'title': 'x',
      'startsAt': '2030-01-01T10:00:00-08:00',
      'notes': null,
    });
    expect(data['startsAt'], '2030-01-01T18:00:00.000Z');
    expect(data.containsKey('notes'), false);
    expect(
      () => col.normalizeRecord({...data, 'allocated': 8}),
      throwsA(isA<SpecException>()),
    );
  });
  test('query language rejects unsupported operators, fields and limits', () {
    final col = starterTemplates()['reading']!.collections.first;
    expect(
      () => RecordQuery.parse(col, {'limit': 101}),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => RecordQuery.parse(col, {
        'filters': [
          {'fieldId': 'title', 'operator': 'sql', 'value': 'x'},
        ],
      }),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => RecordQuery.parse(col, {
        'sort': [
          {'fieldId': 'missing', 'descending': false},
        ],
      }),
      throwsA(isA<SpecException>()),
    );
    expect(
      RecordQuery.parse(col, {
        'filters': [
          {'fieldId': 'status', 'operator': 'eq', 'value': 'Reading'},
        ],
      }).limit,
      50,
    );
  });
}
