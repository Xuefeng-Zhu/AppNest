part of '../appnest_spec.dart';

Map<String, dynamic> _field(
  String id,
  String label,
  String type, {
  bool required = false,
  List<String>? choices,
}) => {
  'id': id,
  'label': label,
  'type': type,
  'required': required,
  if (choices != null) 'choices': choices,
};
Map<String, dynamic> _action(
  String id,
  String label,
  String capability,
  String collection, {
  String? behavior,
}) => {
  'id': id,
  'label': label,
  'capability': capability,
  'collectionId': collection,
  if (behavior != null) 'behaviorId': behavior,
};

AppSpec _template(
  String name,
  String theme,
  String icon,
  String policy,
  String collection,
  String label,
  List<Map<String, dynamic>> fields,
  List<Map<String, dynamic>> behaviors,
  List<Map<String, dynamic>> actions,
  List<Map<String, dynamic>> views,
  List<Map<String, dynamic>> rules,
) {
  final required = <String>{
    'collections.v1',
    ...behaviors.map((b) => b['type'] as String),
    ...actions.map((a) => a['capability'] as String),
    ...views.map((v) => 'views.${v['type']}.v1'),
    if (rules.isNotEmpty) 'notifications.inApp.v1',
  };
  return AppSpec.parse(
    jsonEncode({
      'formatVersion': 1,
      'name': name,
      'theme': theme,
      'icon': icon,
      'requires': required.toList(),
      'collections': [
        {
          'id': collection,
          'label': label,
          'fields': fields,
          'behaviors': behaviors,
        },
      ],
      'actions': actions,
      'views': views,
      'policyPresetRequest': policy,
      'automationRequests': rules,
    }),
  );
}

Map<String, AppSpec> starterTemplates() => {
  'reading': _template(
    'Reading Journal',
    'amber',
    'book',
    'personalTracker.v1',
    'books',
    'Books',
    [
      _field('title', 'Title', 'text', required: true),
      _field('author', 'Author', 'text'),
      _field(
        'status',
        'Status',
        'choice',
        required: true,
        choices: ['Want to read', 'Reading', 'Finished'],
      ),
      _field('rating', 'Rating', 'integer'),
      _field('notes', 'Notes', 'text'),
    ],
    [],
    [
      _action('addBook', 'Add book', 'records.create.v1', 'books'),
      _action('editBook', 'Edit book', 'records.patch.v1', 'books'),
    ],
    [
      {
        'id': 'library',
        'type': 'list',
        'collectionId': 'books',
        'label': 'Library',
        'titleFieldId': 'title',
        'actionIds': ['addBook', 'editBook'],
      },
      {
        'id': 'readingSummary',
        'type': 'summary',
        'collectionId': 'books',
        'label': 'Overview',
        'groupByFieldId': 'status',
      },
    ],
    [],
  ),
  'chores': _template(
    'Chore Board',
    'sage',
    'board',
    'groupWorkflow.v1',
    'chores',
    'Chores',
    [
      _field('title', 'Chore', 'text', required: true),
      _field('assignee', 'Assigned to', 'member'),
      _field('dueAt', 'Due date', 'timestamp'),
      _field(
        'status',
        'Status',
        'choice',
        required: true,
        choices: ['Open', 'Doing', 'Done'],
      ),
      _field('notes', 'Notes', 'text'),
    ],
    [
      {
        'id': 'progress',
        'type': 'workflow.v1',
        'fieldId': 'status',
        'transitions': {
          'Open': ['Doing'],
          'Doing': ['Open', 'Done'],
          'Done': ['Open'],
        },
      },
      {'id': 'assignment', 'type': 'assignment.v1', 'fieldId': 'assignee'},
    ],
    [
      _action('addChore', 'Add chore', 'records.create.v1', 'chores'),
      _action('editChore', 'Edit notes', 'records.patch.v1', 'chores'),
      _action(
        'assignChore',
        'Assign',
        'assignment.assign.v1',
        'chores',
        behavior: 'assignment',
      ),
      _action(
        'moveChore',
        'Change status',
        'workflow.transition.v1',
        'chores',
        behavior: 'progress',
      ),
    ],
    [
      {
        'id': 'board',
        'type': 'board',
        'collectionId': 'chores',
        'label': 'Board',
        'titleFieldId': 'title',
        'groupByFieldId': 'status',
        'actionIds': ['addChore', 'editChore', 'assignChore', 'moveChore'],
      },
      {
        'id': 'allChores',
        'type': 'list',
        'collectionId': 'chores',
        'label': 'All chores',
        'titleFieldId': 'title',
        'actionIds': ['addChore', 'editChore', 'assignChore', 'moveChore'],
      },
    ],
    [
      {
        'id': 'dueReminder',
        'trigger': {
          'type': 'beforeTimestamp',
          'collectionId': 'chores',
          'fieldId': 'dueAt',
          'offsetSeconds': 3600,
        },
        'effect': {'type': 'notifyAssignee', 'channel': 'inApp'},
      },
    ],
  ),
  'volunteer': _template(
    'Volunteer Shifts',
    'teal',
    'people',
    'groupCapacitySignup.v1',
    'shifts',
    'Shifts',
    [
      _field('title', 'Shift', 'text', required: true),
      _field('startsAt', 'Starts', 'timestamp', required: true),
      _field('notes', 'Preparation notes', 'text'),
    ],
    [
      {'id': 'places', 'type': 'capacity.v1'},
    ],
    [
      _action('addShift', 'Create shift', 'records.create.v1', 'shifts'),
      _action('editShift', 'Edit shift', 'records.patch.v1', 'shifts'),
      _action(
        'configure',
        'Set capacity',
        'capacity.configure.v1',
        'shifts',
        behavior: 'places',
      ),
      _action(
        'join',
        'Join shift',
        'capacity.claim.v1',
        'shifts',
        behavior: 'places',
      ),
      _action(
        'leave',
        'Cancel sign-up',
        'capacity.release.v1',
        'shifts',
        behavior: 'places',
      ),
    ],
    [
      {
        'id': 'allShifts',
        'type': 'list',
        'collectionId': 'shifts',
        'label': 'Shifts',
        'titleFieldId': 'title',
        'actionIds': ['addShift', 'editShift', 'join', 'leave', 'configure'],
      },
      {
        'id': 'placesSummary',
        'type': 'capacity',
        'collectionId': 'shifts',
        'label': 'Places',
        'titleFieldId': 'title',
        'actionIds': ['join', 'leave'],
      },
    ],
    [
      {
        'id': 'shiftReminder',
        'trigger': {
          'type': 'beforeTimestamp',
          'collectionId': 'shifts',
          'fieldId': 'startsAt',
          'offsetSeconds': 3600,
        },
        'effect': {'type': 'notifyActiveClaimants', 'channel': 'inApp'},
      },
    ],
  ),
};

List<Map<String, dynamic>> syntheticRecords(CollectionSpec c) => List.generate(
  3,
  (i) => {
    for (final f in c.fields)
      f.id: switch (f.type) {
        FieldType.text =>
          f.id == 'title'
              ? [
                  'Community morning',
                  'A small beginning',
                  'Make room for good',
                ][i]
              : 'Example ${f.label.toLowerCase()}',
        FieldType.integer => i + 1,
        FieldType.number => (i + 1) * 1.5,
        FieldType.boolean => i.isEven,
        FieldType.choice => f.choices[i % f.choices.length],
        FieldType.timestamp => DateTime.utc(
          2030,
          1,
          5 + i,
          10,
        ).toIso8601String(),
        FieldType.member => 'preview_member',
      },
  },
);
