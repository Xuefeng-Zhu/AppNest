import 'dart:convert';

import 'package:appnest_server/src/modules/builder/generation_requirements.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

Map<String, dynamic> _reading() =>
    jsonDecode(creationReferenceJson) as Map<String, dynamic>;
AppSpec _spec(Map<String, dynamic> json) => AppSpec.parse(jsonEncode(json));

const _inboxRequest =
    'Build a personal reminders app with open and completed items, optional due '
    'dates, and a separate optional reminder time for my AppNest inbox.';
const _potluckRequest =
    'Help me organize a neighborhood potluck. I want everyone to add their dish, '
    'how many it serves, any allergy notes, and whether it is planned, confirmed '
    'or delivered. Show me a dish list and a progress summary.';

Map<String, dynamic> _ownerReminders() {
  final json = _reading();
  json['collections'][0]['fields'][1]['choices'] = ['Open', 'Completed'];
  json['collections'][0]['behaviors'][0]['transitions'] = {
    'Open': ['Completed'],
    'Completed': ['Open'],
  };
  json['collections'][0]['fields'].addAll([
    {
      'id': 'targetMoment',
      'label': 'Target',
      'type': 'timestamp',
      'required': false,
    },
    {
      'id': 'nudgeMoment',
      'label': 'Ping',
      'type': 'timestamp',
      'required': false,
    },
  ]);
  json['views'][2]['fieldIds'] = ['title', 'targetMoment', 'nudgeMoment'];
  json['requires'].addAll([
    'notifications.inApp.v1',
    'notifications.owner.v1',
    'automations.conditions.v1',
  ]);
  json['automationRequests'] = <dynamic>[
    {
      'id': 'scheduledPing',
      'trigger': {
        'type': 'beforeTimestamp',
        'collectionId': 'books',
        'fieldId': 'nudgeMoment',
        'offsetSeconds': 0,
      },
      'effect': {'type': 'notifyOwner', 'channel': 'inApp'},
      'condition': {'fieldId': 'status', 'value': 'Open'},
    },
  ];
  return json;
}

void main() {
  final mismatch = throwsA(isA<SpecException>());

  test('record grammar guards require literal affirmative single-collection routes', () {
    const one = 'Use one Tasks collection with Title (required text). ';
    const routes =
        'Include dedicated Task details and shared Add/Edit task pages.';
    final exact = GenerationRequirements.fromRequest('$one$routes');
    expect(exact.singleRecordCollection, isTrue);
    expect(exact.dedicatedRecordRoutes, isTrue);
    expect(
      GenerationRequirements.fromRequest('$one Do not $routes')
          .dedicatedRecordRoutes,
      isFalse,
    );
    for (final request in [
      'A useful records app. $routes',
      'Do not $one$routes',
      '${one}Use one People collection with Name (required text). $routes',
      '${one}Add another People collection. $routes',
      '${one}Also add a People collection with Name (required text). $routes',
    ]) {
      final ambiguous = GenerationRequirements.fromRequest(request);
      expect(ambiguous.singleRecordCollection, isFalse, reason: request);
      expect(ambiguous.dedicatedRecordRoutes, isFalse, reason: request);
    }
    expect(
      GenerationRequirements.fromRequest(
        'Use a single Ledger collection with Entry (required text). '
        'Include dedicated Entry details and a shared Add/Edit entry page.',
      ).dedicatedRecordRoutes,
      isTrue,
    );
  });

  test('literal participant creation requires a shared member-write policy without assigning identities', () {
    for (final request in [
      _potluckRequest,
      'Build a reading log where friends can create their reviews.',
      'Let members add their own records to the tracker.',
      'Everyone adds their recipe.',
      'Participants should submit their suggestions.',
    ]) {
      final requirements = GenerationRequirements.fromRequest(request);
      expect(requirements.sharedRecordCreation, isTrue, reason: request);
      expect(requirements.policy, isNull);
      expect(requirements.preferredPolicy, 'groupWorkflow.v1');
      expect(requirements.toJson(), {
        'policyPresetRequest': 'groupWorkflow.v1',
        'sharedRecordCreation': true,
      });
      expect(() => requirements.validate(_spec(_reading())), mismatch);
      final shared = _reading()..['policyPresetRequest'] = 'groupWorkflow.v1';
      expect(() => requirements.validate(_spec(shared)), returnsNormally);
      // No workflow behavior, capacity pool or membership grant is inferred
      // from the access request; a shared journal can use ordinary CRUD.
      shared['collections'][0]['behaviors'] = [];
      shared['collections'][0]['fields'][1]['required'] = false;
      shared['actions'].removeLast();
      for (final view in shared['views'] as List) {
        (view['actionIds'] as List).remove('changeReadingStatus');
      }
      expect(() => requirements.validate(_spec(shared)), returnsNormally);
    }
  });

  test('schema-valid personal potluck159 is rejected for the exact shared creation request', () {
    // Cohort5 app159 declared personalTracker despite the explicit everyone
    // add-their-dish request. This reproduces its access defect independently
    // of unrelated fields, pages and progress presentation.
    final personal = _spec(_reading());
    expect(personal.policyPresetRequest, 'personalTracker.v1');
    expect(
      () =>
          GenerationRequirements.fromRequest(_potluckRequest)
              .validate(personal),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'shared member writes',
          contains(
            'participant record creation needs policyPresetRequest groupWorkflow.v1',
          ),
        ),
      ),
    );
  });

  test('shared creation skips negatives, examples, viewing-only friends and ambiguous scopes', () {
    for (final request in [
      'Do not let everyone add their dish.',
      'Never let members create their records.',
      'For example, friends can create their reviews.',
      'Maybe everyone can add their dish.',
      'Everyone can add their dish only as an example.',
      'I track the recipes my friends give me.',
      'My friends can view my records.',
      'Build a shared neighborhood cookbook.',
      'Everyone can add their dish. Build another private notes app.',
      'Build a potluck app where everyone can add their dish and a separate notes app.',
      'Let members add their records across two collections.',
    ]) {
      final requirements = GenerationRequirements.fromRequest(request);
      expect(requirements.sharedRecordCreation, isFalse, reason: request);
      expect(requirements.preferredPolicy, isNull, reason: request);
    }
  });

  test('explicit policies retain precedence and shared contracts are creation-only in provider requests', () {
    for (final policy in policyPresets) {
      final request = 'Use $policy. Let members add their records.';
      final requirements = GenerationRequirements.fromRequest(request);
      expect(requirements.sharedRecordCreation, isFalse);
      expect(requirements.policy, policy);
      expect(requirements.preferredPolicy, policy);
      expect(requirements.toJson(), {'policyPresetRequest': policy});
    }
    for (final request in [
      'Use personalTracker.v1 or use groupWorkflow.v1. Let everyone add their dish.',
      'Use personalTracker.v1 or groupWorkflow.v1. Let everyone add their dish.',
      'Use groupWorkflow.v1 versus groupCapacitySignup.v1. Let members add their records.',
    ]) {
      final ambiguous = GenerationRequirements.fromRequest(request);
      expect(ambiguous.sharedRecordCreation, isFalse, reason: request);
      expect(ambiguous.preferredPolicy, isNull, reason: request);
    }
    final single = GenerationRequirements.fromRequest(
      'Use groupWorkflow.v1. Do not use personalTracker.v1. Let members add their records.',
    );
    expect(single.preferredPolicy, 'groupWorkflow.v1');
    final creation = buildAiRequest(
      'test',
      _potluckRequest,
      _spec(_reading()),
      editing: false,
    );
    final user =
        jsonDecode(creation['messages'].last['content'] as String) as Map;
    expect(user['explicitRequirements'], {
      'policyPresetRequest': 'groupWorkflow.v1',
      'sharedRecordCreation': true,
    });
    final edit = buildAiRequest(
      'test',
      _potluckRequest,
      _spec(_reading()),
      editing: true,
    );
    expect(
      jsonDecode(edit['messages'].last['content'] as String),
      isNot(contains('explicitRequirements')),
    );
  });

  test('explicit personal inbox scheduling serializes requirements without authored identities', () {
    final requirements = GenerationRequirements.fromRequest(_inboxRequest);
    expect(requirements.isEmpty, isFalse);
    expect(requirements.toJson(), {
      'ownerInboxReminder': {
        'effect': 'notifyOwner',
        'optionalTimestamp': true,
        'distinctOptionalDueDate': true,
        'openCompletedCondition': true,
      },
    });
    expect(
      () => requirements.validate(_spec(_ownerReminders())),
      returnsNormally,
    );
    final simple = GenerationRequirements.fromRequest(
      'Add reminders for my AppNest inbox.',
    ).ownerInboxReminder!;
    expect(simple.optionalTimestamp, isFalse);
    expect(simple.distinctOptionalDueDate, isFalse);
    expect(simple.openCompletedCondition, isFalse);
  });

  test('negative examples and ambiguous reminder scopes remain provider interpretation', () {
    for (final request in [
      'Do not $_inboxRequest',
      'Never $_inboxRequest',
      'For example, $_inboxRequest',
      'A sample request: $_inboxRequest',
      'Maybe $_inboxRequest',
      '$_inboxRequest Build another recipes app.',
      '$_inboxRequest Add two household collections.',
      'Build shared team reminders for my AppNest inbox.',
      'Add reminders for my AppNest inbox and owner inbox.',
      'Build a personal reminder app with an email inbox.',
      'Build an inbox record view with reminder times.',
      'Add reminders to my AppNest inbox only as an example.',
    ]) {
      expect(
        GenerationRequirements.fromRequest(request).ownerInboxReminder,
        isNull,
        reason: request,
      );
    }
    final optionalNegative = GenerationRequirements.fromRequest(
      'Add reminders for my AppNest inbox. Do not add optional due dates. '
      'No separate optional reminder time. No open and completed states.',
    ).ownerInboxReminder!;
    expect(optionalNegative.optionalTimestamp, isFalse);
    expect(optionalNegative.distinctOptionalDueDate, isFalse);
    expect(optionalNegative.openCompletedCondition, isFalse);
  });

  test('schema-valid reminder158 omission cannot satisfy the explicit inbox request', () {
    // Cohort4 app158 reached preview with personal policy, Open/Completed,
    // optional due/reminder timestamps, and automationRequests: []. The
    // scheduling omission is independent of the candidate's display widgets.
    final json = _ownerReminders()..['automationRequests'] = <dynamic>[];
    final spec = _spec(json);
    expect(spec.policyPresetRequest, 'personalTracker.v1');
    expect(spec.automationRequests, isEmpty);
    expect(
      () => GenerationRequirements.fromRequest(_inboxRequest).validate(spec),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'missing delivery rule',
          contains('notifyOwner inApp effect'),
        ),
      ),
    );
    expect(
      () => const GenerationRequirements().validate(spec),
      returnsNormally,
    );
  });

  test('owner inbox gate requires optional separate dates and the declared Open condition', () {
    final requirements = GenerationRequirements.fromRequest(_inboxRequest);
    final requiredTime = _ownerReminders();
    requiredTime['collections'][0]['fields'][3]['required'] = true;
    expect(() => requirements.validate(_spec(requiredTime)), mismatch);
    final requiredDue = _ownerReminders();
    requiredDue['collections'][0]['fields'][2]['required'] = true;
    expect(() => requirements.validate(_spec(requiredDue)), mismatch);
    final noCondition = _ownerReminders();
    (noCondition['automationRequests'][0] as Map).remove('condition');
    expect(() => requirements.validate(_spec(noCondition)), mismatch);
    final completedCondition = _ownerReminders();
    completedCondition['automationRequests'][0]['condition']['value'] =
        'Completed';
    expect(() => requirements.validate(_spec(completedCondition)), mismatch);
    final otherVocabulary = _ownerReminders();
    otherVocabulary['collections'][0]['fields'][1]['choices'] = [
      'Open',
      'Done',
    ];
    otherVocabulary['collections'][0]['behaviors'][0]['transitions'] = {
      'Open': ['Done'],
      'Done': ['Open'],
    };
    expect(() => requirements.validate(_spec(otherVocabulary)), mismatch);
    final casing = _ownerReminders();
    casing['collections'][0]['fields'][1]['choices'] = ['open', 'completed'];
    casing['collections'][0]['behaviors'][0]['transitions'] = {
      'open': ['completed'],
      'completed': ['open'],
    };
    casing['automationRequests'][0]['condition']['value'] = 'open';
    expect(() => requirements.validate(_spec(casing)), returnsNormally);
  });

  test('an explicit separate reminder time cannot reuse the optional due-date calendar field', () {
    final json = _ownerReminders();
    json['requires'].add('views.calendar.v1');
    json['views'].add({
      'id': 'dueDates',
      'type': 'calendar',
      'collectionId': 'books',
      'titleFieldId': 'title',
      'options': {'dateFieldId': 'targetMoment'},
      'actionIds': <dynamic>[],
    });
    json['navigation']['pages'].add({
      'id': 'dueDatesPage',
      'title': 'Due dates',
      'viewIds': ['dueDates'],
    });
    json['navigation']['tabs'].add({
      'pageId': 'dueDatesPage',
      'label': 'Due dates',
      'icon': 'today',
    });
    final requirements = GenerationRequirements.fromRequest(_inboxRequest);
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['automationRequests'][0]['trigger']['fieldId'] = 'targetMoment';
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test('literal standalone search supports visible text lists and tables without choice filters', () {
    final requirements = GenerationRequirements.fromRequest(
      'I want a searchable list without choice filters.',
    );
    expect(requirements.searchableList, isTrue);
    expect(requirements.filters, isEmpty);
    final json = _reading();
    expect(json['views'][0]['filterFieldIds'], isNull);
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['views'][0].remove('titleFieldId');
    expect(() => requirements.validate(_spec(json)), mismatch);
    // Text on the dedicated hidden details view does not expose Search.
    json['views'][1]['titleFieldId'] = 'title';
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'][0]['type'] = 'table';
    json['views'][0]['titleFieldId'] = 'title';
    json['requires'].add('views.table.v1');
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    final tableRequest = GenerationRequirements.fromRequest(
      'Add a searchable table.',
    );
    expect(tableRequest.searchableList, isTrue);
    expect(() => tableRequest.validate(_spec(json)), returnsNormally);
    for (final request in [
      'Do not add a searchable list.',
      'For example, add a searchable list.',
      'Maybe add a searchable table.',
      'A searchable list is not needed.',
      'Let me find books by name.',
    ]) {
      expect(
        GenerationRequirements.fromRequest(request).searchableList,
        isFalse,
        reason: request,
      );
    }
  });

  test('provider gets explicit inbox requirements for creation while edits retain their existing contract', () {
    final creation = buildAiRequest(
      'test',
      _inboxRequest,
      _spec(_reading()),
      editing: false,
    );
    final user =
        jsonDecode(creation['messages'].last['content'] as String) as Map;
    expect(
      user['explicitRequirements'],
      GenerationRequirements.fromRequest(_inboxRequest).toJson(),
    );
    expect(user.containsKey('currentDefinition'), isFalse);
    final edit = buildAiRequest(
      'test',
      _inboxRequest,
      _spec(_reading()),
      editing: true,
    );
    final edited =
        jsonDecode(edit['messages'].last['content'] as String) as Map;
    expect(edited, isNot(contains('explicitRequirements')));
  });

  test('explicit policies are enforced without inferring ambiguous prose', () {
    final requirements = GenerationRequirements.fromRequest(
      'Use groupWorkflow.v1 for our shared reading journal.',
    );
    expect(() => requirements.validate(_spec(_reading())), mismatch);
    final shared = _reading()..['policyPresetRequest'] = 'groupWorkflow.v1';
    expect(() => requirements.validate(_spec(shared)), returnsNormally);
    expect(
      GenerationRequirements.fromRequest(
        'Build a packing app with the personalTracker.v1 policy.',
      ).policy,
      'personalTracker.v1',
    );
    for (final request in [
      'A household app',
      'Do not use personalTracker.v1.',
      'Never use personalTracker.v1.',
      'Do not build an app using personalTracker.v1.',
      'Use personalTracker.v1 or use groupWorkflow.v1; I have not decided.',
    ]) {
      expect(GenerationRequirements.fromRequest(request).policy, isNull);
    }
  });

  test('exact choice vocabulary and initial ordering survive defaults', () {
    final requirements = GenerationRequirements.fromRequest(
      'Use one Packing items collection with Item (required text), '
      'Category (required choice: Documents, Clothes, Other), Quantity (required integer), '
      'and Packing status (required choice: To pack, Packed).',
    );
    expect(requirements.choices, {
      'Category': ['Documents', 'Clothes', 'Other'],
      'Packing status': ['To pack', 'Packed'],
    });
    final json = _reading();
    json['collections'][0]['fields'][1]['label'] = 'Packing status';
    json['collections'][0]['fields'].add({
      'id': 'category',
      'label': 'Category',
      'type': 'choice',
      'required': false,
      'choices': ['Documents', 'Clothes', 'Other'],
    });
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['collections'][0]['fields'][1]['choices'] = ['To pack', 'Packed'];
    json['collections'][0]['behaviors'][0]['transitions'] = {
      'To pack': ['Packed'],
      'Packed': ['To pack'],
    };
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['collections'][0]['fields'][1]['choices'] = ['Packed', 'To pack'];
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test(
    'choice filters must be on a visible record view, not display fields',
    () {
      final requirements = GenerationRequirements.fromRequest(
        'Use fields Title (required text), and Status (required choice: To read, Read). '
        'Make a searchable list and Status filter.',
      );
      expect(requirements.filters, ['Status']);
      final json = _reading();
      expect(() => requirements.validate(_spec(json)), mismatch);
      json['views'][0]['filterFieldIds'] = ['status'];
      expect(() => requirements.validate(_spec(json)), returnsNormally);
      json['views'][0].remove('filterFieldIds');
      json['views'][1]['filterFieldIds'] = ['status'];
      expect(() => requirements.validate(_spec(json)), mismatch);
    },
  );

  test('slash-separated filters preserve each named field', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Category (required choice: Work, Home), and Packing status (required choice: To pack, Packed). '
      'Use a searchable list and Category/Packing status filters.',
    );
    expect(requirements.filters, ['Category', 'Packing status']);
  });

  test('negative filter and summary examples do not become requirements', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), and Status (required choice: To read, Read). '
      'Do not add Status filters. No grouped counts by Status.',
    );
    expect(requirements.choices.keys, ['Status']);
    expect(requirements.filters, isEmpty);
    expect(requirements.groupedSummaries, isEmpty);
  });

  test('negative field and filtered-tab examples are not inferred', () {
    expect(
      GenerationRequirements.fromRequest(
        'Do not add Status (required choice: Open, Done).',
      ).choices,
      isEmpty,
    );
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Do not add a Finished tab filtered to Read.',
    );
    expect(requirements.filteredTabs, isEmpty);
  });

  test('a requested searchable filtered list needs a text title binding', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add a searchable saved-item list with Status filters.',
    );
    expect(requirements.searchableList, isTrue);
    final json = _reading();
    json['views'][0]['filterFieldIds'] = ['status'];
    json['views'][0].remove('titleFieldId');
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'][0]['titleFieldId'] = 'title';
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    final negative = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add Status filters. Do not add a searchable list.',
    );
    expect(negative.searchableList, isFalse);
  });

  test('a total cannot satisfy a requested grouped summary', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add a Progress tab with grouped counts by Status.',
    );
    expect(requirements.groupedSummaries, ['Status']);
    final json = _reading();
    json['requires'].add('views.summary.v1');
    json['views'].add({
      'id': 'progress',
      'type': 'summary',
      'collectionId': 'books',
    });
    json['navigation']['pages'].add({
      'id': 'progressPage',
      'title': 'Progress',
      'viewIds': ['progress'],
    });
    json['navigation']['tabs'].add({
      'pageId': 'progressPage',
      'label': 'Progress',
      'icon': 'chart',
    });
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'].last['groupByFieldId'] = 'status';
    expect(() => requirements.validate(_spec(json)), returnsNormally);
  });

  test('a filtered tab must constrain every record view on that tab', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add a Finished tab filtered to Read and an Overview tab.',
    );
    expect(requirements.filteredTabs, {'Finished': 'Read'});
    final json = _reading();
    final list = Map<String, dynamic>.from(json['views'][0] as Map)
      ..['id'] = 'finishedList';
    json['views'].add(list);
    json['navigation']['pages'].add({
      'id': 'finishedPage',
      'title': 'Finished',
      'viewIds': ['finishedList'],
    });
    json['navigation']['tabs'].add({
      'pageId': 'finishedPage',
      'label': 'Finished',
      'icon': 'list',
    });
    expect(() => requirements.validate(_spec(json)), mismatch);
    list['query'] = {
      'filters': [
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Read'},
      ],
    };
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    final second = Map<String, dynamic>.from(json['views'][0] as Map)
      ..['id'] = 'unfilteredList';
    json['views'].add(second);
    json['navigation']['pages'].last['viewIds'].add('unfilteredList');
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test('shared log grouping request remains separate from task workflow', () {
    final requirements = GenerationRequirements.fromRequest(
      'Use groupWorkflow.v1. Fields Pet (required text), Activity (required choice: Feeding, Walk). '
      'A searchable list and Activity filter, and a Summary tab grouping saved entries by Activity. '
      'Do not add a task-status workflow.',
    );
    expect(requirements.policy, 'groupWorkflow.v1');
    expect(requirements.filters, ['Activity']);
    expect(requirements.groupedSummaries, ['Activity']);
  });

  test('provider receives literal creation requirements without draft content', () {
    const request =
        'Use groupWorkflow.v1. Fields Status (required choice: Started, Finished).';
    final body = buildAiRequest(
      'test',
      request,
      _spec(_reading()),
      editing: false,
    );
    final user = jsonDecode(body['messages'].last['content'] as String) as Map;
    expect(user['explicitRequirements'], {
      'policyPresetRequest': 'groupWorkflow.v1',
      'exactChoiceFields': {
        'Status': ['Started', 'Finished'],
      },
    });
    expect(user.containsKey('currentDefinition'), isFalse);
    final edit = buildAiRequest(
      'test',
      request,
      _spec(_reading()),
      editing: true,
    );
    expect(
      jsonDecode(edit['messages'].last['content'] as String),
      isNot(contains('explicitRequirements')),
    );
  });
}
