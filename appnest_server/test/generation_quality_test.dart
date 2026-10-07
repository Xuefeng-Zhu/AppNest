import 'dart:convert';

import 'package:appnest_server/src/modules/builder/generation_quality.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  test('device-only generated apps need visible device components', () {
    expect(
      () => validateGeneratedExperience(phoneToolkitTemplate()),
      returnsNormally,
    );
    final json = phoneToolkitTemplate().toJson();
    json['views'].add({
      'id': 'intro',
      'type': 'richText',
      'label': 'Intro',
      'options': {'markdown': 'Hello'},
    });
    json['requires'].add('views.richText.v1');
    json['navigation']['pages'].add({
      'id': 'introPage',
      'title': 'Intro',
      'viewIds': ['intro'],
    });
    json['navigation']['entryPageId'] = 'introPage';
    json['navigation']['tabs'] = [
      {'pageId': 'introPage', 'label': 'Intro', 'icon': 'today'},
    ];
    final hidden = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(hidden),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => validateGeneratedExperience(hidden, baseline: hidden),
      returnsNormally,
    );
  });

  test('existing starter experiences expose their editable collections', () {
    for (final entry in starterTemplates().entries) {
      expect(
        () => validateGeneratedExperience(entry.value),
        returnsNormally,
        reason: entry.key,
      );
    }
  });

  test('a schema-valid hidden create control is rejected for generation', () {
    final json = starterTemplates()['planner']!.toJson();
    for (final page in json['navigation']['pages'] as List) {
      (page as Map).remove('primaryActionId');
    }
    for (final view in json['views'] as List) {
      if (view['type'] != 'form') {
        (view['actionIds'] as List).remove('addTask');
      }
    }
    final spec = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(spec),
      throwsA(isA<SpecException>()),
    );
  });

  test('a hidden edit form alone is not a reachable record edit', () {
    final json = starterTemplates()['planner']!.toJson();
    for (final view in json['views'] as List) {
      if (view['type'] != 'form') {
        (view['actionIds'] as List).remove('editTask');
      }
    }
    final spec = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(spec),
      throwsA(isA<SpecException>()),
    );
  });

  test('read-only collections are not required to offer CRUD', () {
    final json = starterTemplates()['reading']!.toJson();
    json['actions'] = <Object>[];
    for (final view in json['views'] as List) {
      view['actionIds'] = <Object>[];
    }
    // The legacy list/details fixture renders read-only records directly.
    (json['views'] as List).removeWhere((view) => view['type'] == 'form');
    final spec = AppSpec.parse(jsonEncode(json));
    expect(() => validateGeneratedExperience(spec), returnsNormally);
  });

  test(
    'summary action IDs and summary detail links do not expose a record editor',
    () {
      final json = starterTemplates()['planner']!.toJson();
      for (final view in json['views'] as List) {
        if (view['type'] != 'form') {
          (view['actionIds'] as List).remove('editTask');
        }
      }
      final summary = (json['views'] as List).firstWhere(
        (view) => view['id'] == 'todaySummary',
      );
      (summary['actionIds'] as List).add('editTask');
      summary['detailPageId'] = 'taskDetailPage';
      final hidden = AppSpec.parse(jsonEncode(json));
      expect(
        () => validateGeneratedExperience(hidden),
        throwsA(isA<SpecException>()),
      );
      expect(
        () => validateGeneratedExperience(
          hidden,
          baseline: starterTemplates()['planner']!,
        ),
        throwsA(isA<SpecException>()),
      );
    },
  );

  test(
    'existing append-only apps can be renamed without new CRUD requirements',
    () {
      final json = starterTemplates()['reading']!.toJson();
      final removed = (json['actions'] as List)
          .where((action) => action['capability'] == 'records.patch.v1')
          .map((action) => action['id'])
          .toSet();
      (json['actions'] as List).removeWhere(
        (action) => removed.contains(action['id']),
      );
      for (final view in json['views'] as List) {
        (view['actionIds'] as List).removeWhere(removed.contains);
      }
      final original = AppSpec.parse(jsonEncode(json));
      final renamed = original.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'My existing collection',
      }, () => throw StateError('No IDs'));
      expect(
        () => validateGeneratedExperience(renamed),
        throwsA(isA<SpecException>()),
      );
      expect(
        () => validateGeneratedExperience(renamed, baseline: original),
        returnsNormally,
      );
    },
  );
}
