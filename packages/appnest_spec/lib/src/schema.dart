part of '../appnest_spec.dart';

Map<String, dynamic> appSpecSchema() {
  Map<String, dynamic> obj(
    Map<String, dynamic> properties,
    List<String> required,
  ) => {
    'type': 'object',
    'additionalProperties': false,
    'properties': properties,
    'required': required,
  };
  Map<String, dynamic> arr(Object items, int max) => {
    'type': 'array',
    'items': items,
    'maxItems': max,
  };
  final id = {
        'type': 'string',
        'pattern': r'^[a-zA-Z][a-zA-Z0-9_]*$',
        'maxLength': 64,
      },
      label = {'type': 'string', 'minLength': 1, 'maxLength': 160};
  final field = obj(
    {
      'id': id,
      'label': label,
      'type': {'enum': FieldType.values.map((t) => t.name).toList()},
      'required': {'type': 'boolean'},
      'choices': arr({'type': 'string', 'minLength': 1, 'maxLength': 80}, 30),
    },
    ['id', 'label', 'type', 'required'],
  );
  final behavior = obj(
    {
      'id': id,
      'type': {
        'enum': ['capacity.v1', 'workflow.v1', 'assignment.v1'],
      },
      'fieldId': id,
      'transitions': {
        'type': 'object',
        'maxProperties': 30,
        'additionalProperties': arr(label, 30),
      },
    },
    ['id', 'type'],
  );
  final collection = obj(
    {
      'id': id,
      'label': label,
      'fields': {...arr(field, Limits.fields), 'minItems': 1},
      'behaviors': arr(behavior, 8),
    },
    ['id', 'label', 'fields'],
  );
  final view = obj(
    {
      'id': id,
      'type': {
        'enum': [
          'list',
          'form',
          'details',
          'board',
          'summary',
          'capacity',
          'action',
        ],
      },
      'collectionId': id,
      'label': label,
      'titleFieldId': id,
      'groupByFieldId': id,
      'actionIds': arr(id, 32),
    },
    ['id', 'type', 'collectionId'],
  );
  final action = obj(
    {
      'id': id,
      'label': label,
      'capability': {'enum': actionCapabilities.toList()},
      'collectionId': id,
      'behaviorId': id,
    },
    ['id', 'label', 'capability', 'collectionId'],
  );
  final rule = obj(
    {
      'id': id,
      'trigger': obj(
        {
          'type': {'const': 'beforeTimestamp'},
          'collectionId': id,
          'fieldId': id,
          'offsetSeconds': {'type': 'integer', 'minimum': 0, 'maximum': 604800},
        },
        ['type', 'collectionId', 'fieldId', 'offsetSeconds'],
      ),
      'effect': obj(
        {
          'type': {
            'enum': ['notifyActiveClaimants', 'notifyAssignee'],
          },
          'channel': {'const': 'inApp'},
        },
        ['type', 'channel'],
      ),
    },
    ['id', 'trigger', 'effect'],
  );
  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': 'https://appnest.local/schema/appspec-v1.json',
    'title': 'AppNest AppSpec v1',
    ...obj(
      {
        'formatVersion': {'const': 1},
        'name': {'type': 'string', 'minLength': 1, 'maxLength': 80},
        'theme': {
          'enum': ['teal', 'amber', 'blue', 'rose', 'sage'],
        },
        'icon': {
          'enum': ['book', 'board', 'people', 'spark', 'check'],
        },
        'requires': arr({'enum': capabilities.toList()}, 40),
        'collections': {...arr(collection, Limits.collections), 'minItems': 1},
        'views': {...arr(view, Limits.views), 'minItems': 1},
        'actions': arr(action, Limits.actions),
        'policyPresetRequest': {'enum': policyPresets.toList()},
        'automationRequests': arr(rule, Limits.rules),
      },
      [
        'formatVersion',
        'name',
        'theme',
        'icon',
        'requires',
        'collections',
        'views',
        'actions',
        'policyPresetRequest',
        'automationRequests',
      ],
    ),
  };
}
