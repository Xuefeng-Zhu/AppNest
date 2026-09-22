part of '../appnest_spec.dart';

enum FieldType { text, integer, number, boolean, choice, timestamp, member }

class FieldSpec {
  final String id, label;
  final FieldType type;
  final bool required;
  final List<String> choices;
  FieldSpec(this.id, this.label, this.type, this.required, this.choices);
  factory FieldSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'label', 'type', 'required', 'choices'}, 'field');
    final type = FieldType.values.where((t) => t.name == j['type']).firstOrNull;
    if (type == null) throw const SpecException('Unsupported field type');
    if (j['required'] is! bool)
      throw const SpecException('Field required must be boolean');
    final choices = array(
      j['choices'] ?? [],
      'choices',
      30,
    ).map((c) => str(c, 'choice', max: 80)).toList();
    unique(choices, 'choices');
    if ((type == FieldType.choice) != choices.isNotEmpty) {
      throw const SpecException('Only choice fields require choices');
    }
    return FieldSpec(
      stableId(j['id']),
      str(j['label'], 'label'),
      type,
      j['required'],
      choices,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'required': required,
    if (choices.isNotEmpty) 'choices': choices,
  };
  Object? normalize(Object? value) {
    if (value == null) {
      if (required) throw SpecException('$label is required');
      return null;
    }
    switch (type) {
      case FieldType.text:
        if (value is! String ||
            value.length > 10000 ||
            (required && value.trim().isEmpty))
          throw SpecException('$label must be text');
      case FieldType.integer:
        if (value is! int || value.abs() > 9007199254740991)
          throw SpecException('$label must be a safe integer');
      case FieldType.number:
        if (value is! num || !value.isFinite || value.abs() > 1e15)
          throw SpecException('$label must be a finite number');
      case FieldType.boolean:
        if (value is! bool) throw SpecException('$label must be true or false');
      case FieldType.choice:
        if (value is! String || !choices.contains(value))
          throw SpecException('$label has an unsupported choice');
      case FieldType.timestamp:
        if (value is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value))
          throw SpecException('$label needs a timestamp with timezone');
        final date = DateTime.tryParse(value);
        if (date == null)
          throw SpecException('$label must be a valid timestamp');
        return date.toUtc().toIso8601String();
      case FieldType.member:
        if (value is! String || value.isEmpty || value.length > 100)
          throw SpecException('$label must reference an eligible member');
    }
    return value;
  }
}

class BehaviorSpec {
  final String id, type;
  final String? fieldId;
  final Map<String, List<String>> transitions;
  BehaviorSpec(this.id, this.type, this.fieldId, this.transitions);
  factory BehaviorSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'type', 'fieldId', 'transitions'}, 'behavior');
    final type = str(j['type'], 'behavior type');
    if (!{'capacity.v1', 'workflow.v1', 'assignment.v1'}.contains(type))
      throw const SpecException('Unsupported behavior');
    final transitions = <String, List<String>>{};
    if (j['transitions'] != null) {
      final map = object(j['transitions'], 'transitions');
      if (map.length > 30) throw const SpecException('Too many transitions');
      for (final e in map.entries) {
        transitions[e.key] = array(
          e.value,
          'transition targets',
          30,
        ).map((x) => str(x, 'target')).toList();
      }
    }
    if (type == 'capacity.v1' &&
        (j['fieldId'] != null || transitions.isNotEmpty))
      throw const SpecException('Capacity is typed state, not a payload field');
    return BehaviorSpec(
      stableId(j['id']),
      type,
      j['fieldId'] == null ? null : stableId(j['fieldId']),
      transitions,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (fieldId != null) 'fieldId': fieldId,
    if (transitions.isNotEmpty) 'transitions': transitions,
  };
}

class CollectionSpec {
  final String id, label;
  final List<FieldSpec> fields;
  final List<BehaviorSpec> behaviors;
  CollectionSpec(this.id, this.label, this.fields, this.behaviors);
  factory CollectionSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'label', 'fields', 'behaviors'}, 'collection');
    final f = array(
      j['fields'],
      'fields',
      Limits.fields,
    ).map((v) => FieldSpec.fromJson(object(v, 'field'))).toList();
    if (f.isEmpty) throw const SpecException('A collection needs fields');
    final b = array(
      j['behaviors'] ?? [],
      'behaviors',
      8,
    ).map((v) => BehaviorSpec.fromJson(object(v, 'behavior'))).toList();
    unique(f.map((v) => v.id), 'fields');
    unique(b.map((v) => v.id), 'behaviors');
    if (b.where((v) => v.type == 'capacity.v1').length > 1)
      throw const SpecException(
        'Only one capacity pool per collection is supported by this renderer.',
      );
    final result = CollectionSpec(
      stableId(j['id']),
      str(j['label'], 'collection label'),
      f,
      b,
    );
    for (final behavior in b) {
      if (behavior.type == 'capacity.v1') continue;
      final field = result.field(behavior.fieldId ?? '');
      if (behavior.type == 'assignment.v1' && field.type != FieldType.member)
        throw const SpecException('Assignment needs a member field');
      if (behavior.type == 'workflow.v1') {
        if (field.type != FieldType.choice || behavior.transitions.isEmpty)
          throw const SpecException(
            'Workflow needs a choice field and transitions',
          );
        for (final e in behavior.transitions.entries) {
          if (!field.choices.contains(e.key) ||
              e.value.any((x) => !field.choices.contains(x)))
            throw const SpecException('Unknown transition status');
        }
      }
    }
    return result;
  }
  FieldSpec field(String id) =>
      fields.where((f) => f.id == id).firstOrNull ??
      (throw SpecException('Unknown field $id'));
  BehaviorSpec behavior(String id) =>
      behaviors.where((b) => b.id == id).firstOrNull ??
      (throw SpecException('Unknown behavior $id'));
  Map<String, dynamic> normalizeRecord(Map<String, dynamic> data) {
    keys(data, fields.map((x) => x.id).toSet(), 'record');
    return {
      for (final f in fields)
        if (f.normalize(data[f.id]) != null) f.id: f.normalize(data[f.id]),
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'fields': fields.map((f) => f.toJson()).toList(),
    'behaviors': behaviors.map((b) => b.toJson()).toList(),
  };
}

class ViewSpec {
  final String id, type, collectionId, label;
  final String? titleFieldId, groupByFieldId;
  final List<String> actionIds;
  ViewSpec(
    this.id,
    this.type,
    this.collectionId,
    this.label,
    this.titleFieldId,
    this.groupByFieldId,
    this.actionIds,
  );
  factory ViewSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {
      'id',
      'type',
      'collectionId',
      'label',
      'titleFieldId',
      'groupByFieldId',
      'actionIds',
    }, 'view');
    final type = str(j['type'], 'view type');
    if (!{
      'list',
      'form',
      'details',
      'board',
      'summary',
      'capacity',
      'action',
    }.contains(type))
      throw const SpecException('Unsupported view');
    return ViewSpec(
      stableId(j['id']),
      type,
      stableId(j['collectionId']),
      str(j['label'] ?? j['id'], 'view label'),
      j['titleFieldId'] == null ? null : stableId(j['titleFieldId']),
      j['groupByFieldId'] == null ? null : stableId(j['groupByFieldId']),
      array(j['actionIds'] ?? [], 'view actions', 32).map(stableId).toList(),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'collectionId': collectionId,
    'label': label,
    if (titleFieldId != null) 'titleFieldId': titleFieldId,
    if (groupByFieldId != null) 'groupByFieldId': groupByFieldId,
    'actionIds': actionIds,
  };
}

class ActionSpec {
  final String id, label, capability, collectionId;
  final String? behaviorId;
  ActionSpec(
    this.id,
    this.label,
    this.capability,
    this.collectionId,
    this.behaviorId,
  );
  factory ActionSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {
      'id',
      'label',
      'capability',
      'collectionId',
      'behaviorId',
    }, 'action');
    final capability = str(j['capability'], 'capability');
    if (!actionCapabilities.contains(capability))
      throw SpecException('Unsupported capability $capability');
    return ActionSpec(
      stableId(j['id']),
      str(j['label'], 'action label'),
      capability,
      stableId(j['collectionId']),
      j['behaviorId'] == null ? null : stableId(j['behaviorId']),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'capability': capability,
    'collectionId': collectionId,
    if (behaviorId != null) 'behaviorId': behaviorId,
  };
}

const actionCapabilities = {
  'records.create.v1',
  'records.patch.v1',
  'assignment.assign.v1',
  'workflow.transition.v1',
  'capacity.configure.v1',
  'capacity.claim.v1',
  'capacity.release.v1',
};
const capabilities = {
  'collections.v1',
  'views.list.v1',
  'views.form.v1',
  'views.details.v1',
  'views.board.v1',
  'views.summary.v1',
  'views.capacity.v1',
  'views.action.v1',
  'capacity.v1',
  'workflow.v1',
  'assignment.v1',
  'notifications.inApp.v1',
  ...actionCapabilities,
};
const policyPresets = {
  'personalTracker.v1',
  'groupWorkflow.v1',
  'groupCapacitySignup.v1',
};

class AutomationSpec {
  final String id, collectionId, fieldId, effect;
  final int offsetSeconds;
  AutomationSpec(
    this.id,
    this.collectionId,
    this.fieldId,
    this.offsetSeconds,
    this.effect,
  );
  factory AutomationSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'trigger', 'effect'}, 'automation');
    final t = object(j['trigger'], 'trigger'),
        e = object(j['effect'], 'effect');
    keys(t, {'type', 'collectionId', 'fieldId', 'offsetSeconds'}, 'trigger');
    keys(e, {'type', 'channel'}, 'effect');
    if (t['type'] != 'beforeTimestamp' ||
        t['offsetSeconds'] is! int ||
        t['offsetSeconds'] < 0 ||
        t['offsetSeconds'] > 604800)
      throw const SpecException(
        'Only bounded one-time reminders are supported',
      );
    if (e['channel'] != 'inApp' ||
        !{'notifyActiveClaimants', 'notifyAssignee'}.contains(e['type']))
      throw const SpecException('Only approved in-app effects are supported');
    return AutomationSpec(
      stableId(j['id']),
      stableId(t['collectionId']),
      stableId(t['fieldId']),
      t['offsetSeconds'],
      e['type'],
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'trigger': {
      'type': 'beforeTimestamp',
      'collectionId': collectionId,
      'fieldId': fieldId,
      'offsetSeconds': offsetSeconds,
    },
    'effect': {'type': effect, 'channel': 'inApp'},
  };
}

class AppSpec {
  final String name, theme, icon, policyPresetRequest;
  final List<String> requires;
  final List<CollectionSpec> collections;
  final List<ViewSpec> views;
  final List<ActionSpec> actions;
  final List<AutomationSpec> automationRequests;
  AppSpec._(
    this.name,
    this.theme,
    this.icon,
    this.policyPresetRequest,
    this.requires,
    this.collections,
    this.views,
    this.actions,
    this.automationRequests,
  );
  factory AppSpec.parse(String source) {
    if (utf8.encode(source).length > Limits.definitionBytes)
      throw const SpecException('Definition is too large');
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const SpecException('Definition must be valid JSON');
    }
    void depth(Object? x, int d) {
      if (d > Limits.depth)
        throw const SpecException('Definition is too deeply nested');
      if (x is Map)
        for (final v in x.values) {
          depth(v, d + 1);
        }
      if (x is List)
        for (final v in x) {
          depth(v, d + 1);
        }
    }

    depth(decoded, 0);
    final j = object(decoded, 'AppSpec');
    keys(j, {
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
    }, 'AppSpec');
    if (j['formatVersion'] is! int || j['formatVersion'] != 1)
      throw const SpecException('Unsupported AppSpec format version');
    final theme = str(j['theme'], 'theme'),
        icon = str(j['icon'], 'icon'),
        policy = str(j['policyPresetRequest'], 'policy');
    if (!{'teal', 'amber', 'blue', 'rose', 'sage'}.contains(theme) ||
        !{'book', 'board', 'people', 'spark', 'check'}.contains(icon))
      throw const SpecException('Choose an approved theme and icon');
    if (!policyPresets.contains(policy))
      throw const SpecException('Unsupported policy request');
    final requires = array(
      j['requires'],
      'requires',
      40,
    ).map((v) => str(v, 'capability')).toList();
    if (requires.any((v) => !capabilities.contains(v)))
      throw const SpecException('Unsupported required capability');
    final c = array(
      j['collections'],
      'collections',
      Limits.collections,
    ).map((v) => CollectionSpec.fromJson(object(v, 'collection'))).toList();
    final v = array(
      j['views'],
      'views',
      Limits.views,
    ).map((v) => ViewSpec.fromJson(object(v, 'view'))).toList();
    final a = array(
      j['actions'],
      'actions',
      Limits.actions,
    ).map((v) => ActionSpec.fromJson(object(v, 'action'))).toList();
    final r = array(
      j['automationRequests'],
      'automationRequests',
      Limits.rules,
    ).map((v) => AutomationSpec.fromJson(object(v, 'rule'))).toList();
    if (c.isEmpty || v.isEmpty)
      throw const SpecException('An app needs collections and views');
    unique(c.map((x) => x.id), 'collections');
    unique(v.map((x) => x.id), 'views');
    unique(a.map((x) => x.id), 'actions');
    unique(r.map((x) => x.id), 'automations');
    final spec = AppSpec._(
      str(j['name'], 'name', max: 80),
      theme,
      icon,
      policy,
      requires,
      c,
      v,
      a,
      r,
    );
    final needed = <String>{'collections.v1'};
    for (final col in c) {
      needed.addAll(col.behaviors.map((b) => b.type));
    }
    for (final view in v) {
      needed.add('views.${view.type}.v1');
      final col = spec.collection(view.collectionId);
      if (view.titleFieldId != null) col.field(view.titleFieldId!);
      if (view.groupByFieldId != null) col.field(view.groupByFieldId!);
      if (view.type == 'form' &&
          !view.actionIds.any(
            (id) => spec.action(id).capability == 'records.create.v1',
          ))
        throw const SpecException('Form views need a record creation action');
      if (view.type == 'action' && view.actionIds.isEmpty)
        throw const SpecException('Action views need an action');
      if (view.type == 'board' &&
          (view.groupByFieldId == null ||
              col.field(view.groupByFieldId!).type != FieldType.choice))
        throw const SpecException('Boards need a choice field');
      if (view.type == 'capacity' &&
          !col.behaviors.any((x) => x.type == 'capacity.v1'))
        throw const SpecException('Capacity view needs capacity behavior');
      for (final id in view.actionIds) {
        if (spec.action(id).collectionId != col.id)
          throw const SpecException(
            'View action belongs to another collection',
          );
      }
    }
    for (final action in a) {
      needed.add(action.capability);
      final col = spec.collection(action.collectionId);
      final expected = action.capability.startsWith('capacity.')
          ? 'capacity.v1'
          : action.capability.startsWith('workflow.')
          ? 'workflow.v1'
          : action.capability.startsWith('assignment.')
          ? 'assignment.v1'
          : null;
      if (expected != null &&
          (action.behaviorId == null ||
              col.behavior(action.behaviorId!).type != expected))
        throw const SpecException('Action behavior binding is invalid');
      if (expected == null && action.behaviorId != null)
        throw const SpecException('Record actions do not bind behaviors');
    }
    for (final rule in r) {
      needed.add('notifications.inApp.v1');
      final col = spec.collection(rule.collectionId);
      if (col.field(rule.fieldId).type != FieldType.timestamp)
        throw const SpecException('Reminder needs a timestamp');
      final behavior = rule.effect == 'notifyActiveClaimants'
          ? 'capacity.v1'
          : 'assignment.v1';
      if (!col.behaviors.any((b) => b.type == behavior))
        throw const SpecException('Reminder recipient binding is invalid');
    }
    if (!requires.toSet().containsAll(needed))
      throw SpecException(
        'Missing required capabilities: ${needed.difference(requires.toSet()).join(", ")}',
      );
    return spec;
  }
  CollectionSpec collection(String id) =>
      collections.where((c) => c.id == id).firstOrNull ??
      (throw SpecException('Unknown collection $id'));
  ActionSpec action(String id) =>
      actions.where((a) => a.id == id).firstOrNull ??
      (throw SpecException('Unknown action $id'));
  Map<String, dynamic> toJson() => {
    'formatVersion': 1,
    'name': name,
    'theme': theme,
    'icon': icon,
    'requires': requires,
    'collections': collections.map((x) => x.toJson()).toList(),
    'views': views.map((x) => x.toJson()).toList(),
    'actions': actions.map((x) => x.toJson()).toList(),
    'policyPresetRequest': policyPresetRequest,
    'automationRequests': automationRequests.map((x) => x.toJson()).toList(),
  };
  String get canonical => canonicalJson(toJson());
  String get hash => hashJson(toJson());

  List<String> compatibilityErrors(AppSpec next) {
    final errors = <String>[];
    if (policyPresetRequest != next.policyPresetRequest)
      errors.add('Changing the permission preset is unsupported');
    for (final old in collections) {
      final col = next.collections.where((c) => c.id == old.id).firstOrNull;
      if (col == null) {
        errors.add('Removing collection ${old.label} is unsupported');
        continue;
      }
      for (final field in old.fields) {
        final f = col.fields.where((x) => x.id == field.id).firstOrNull;
        if (f == null ||
            f.type != field.type ||
            (!field.required && f.required) ||
            !f.choices.toSet().containsAll(field.choices))
          errors.add('Destructive change to ${field.label}');
      }
      for (final f in col.fields) {
        if (f.required && !old.fields.any((x) => x.id == f.id))
          errors.add('Required field ${f.label} needs a backfill');
      }
      if (canonicalJson(old.behaviors.map((b) => b.toJson()).toList()) !=
          canonicalJson(col.behaviors.map((b) => b.toJson()).toList()))
        errors.add('Changing existing behaviors is unsupported');
    }
    return errors;
  }

  List<String> diff(AppSpec? previous) {
    if (previous == null)
      return [
        'Create $name',
        'Policy: $policyPresetRequest',
        ...requires.map((r) => 'Capability: $r'),
        ...automationRequests.map((r) => 'Request reminder: ${r.id}'),
      ];
    final result = <String>[];
    if (name != previous.name) result.add('Rename ${previous.name} to $name');
    for (final col in collections) {
      final old = previous.collections.where((x) => x.id == col.id).firstOrNull;
      for (final f in col.fields) {
        final before = old?.fields.where((x) => x.id == f.id).firstOrNull;
        if (before == null)
          result.add('Add ${f.required ? "required" : "optional"} ${f.label}');
        else if (canonicalJson(before.toJson()) != canonicalJson(f.toJson()))
          result.add('Update ${before.label}: ${f.label}');
      }
    }
    if (canonicalJson(views.map((v) => v.toJson()).toList()) !=
        canonicalJson(previous.views.map((v) => v.toJson()).toList()))
      result.add('Update views or view order');
    for (final c in requires.toSet().difference(previous.requires.toSet()))
      result.add('Request capability: $c');
    if (canonicalJson(automationRequests.map((r) => r.toJson()).toList()) !=
        canonicalJson(
          previous.automationRequests.map((r) => r.toJson()).toList(),
        ))
      result.add('Change requested reminders');
    return result.isEmpty ? ['No structural changes'] : result;
  }

  AppSpec patch(Map<String, dynamic> patch, String Function() allocateId) {
    final j = toJson(), type = patch['type'];
    switch (type) {
      case 'RenameLabel':
        keys(patch, {'type', 'targetId', 'label'}, 'RenameLabel');
        final label = str(patch['label'], 'label');
        if (patch['targetId'] == 'app') {
          j['name'] = label;
          break;
        }
        var found = 0;
        for (final c in j['collections']) {
          if (c['id'] == patch['targetId']) {
            c['label'] = label;
            found++;
          }
          for (final f in c['fields']) {
            if (f['id'] == patch['targetId']) {
              f['label'] = label;
              found++;
            }
          }
        }
        for (final key in ['views', 'actions']) {
          for (final x in j[key]) {
            if (x['id'] == patch['targetId']) {
              x['label'] = label;
              found++;
            }
          }
        }
        if (found == 0) throw const SpecException('Label target not found');
        if (found > 1)
          throw const SpecException(
            'Label target is ambiguous; use globally distinct IDs for manual label editing.',
          );
      case 'AddField':
        keys(patch, {'type', 'collectionId', 'field'}, 'AddField');
        final f = Map<String, dynamic>.from(object(patch['field'], 'field'))
          ..['id'] = allocateId();
        f['required'] ??= false;
        final col = (j['collections'] as List)
            .cast<Map<String, dynamic>>()
            .where((c) => c['id'] == patch['collectionId'])
            .firstOrNull;
        if (col == null) throw const SpecException('Collection not found');
        (col['fields'] as List).add(FieldSpec.fromJson(f).toJson());
      case 'AddChoice':
        keys(patch, {'type', 'collectionId', 'fieldId', 'choice'}, 'AddChoice');
        collection(patch['collectionId']).field(patch['fieldId']);
        final col = (j['collections'] as List).firstWhere(
          (c) => c['id'] == patch['collectionId'],
        );
        final f = (col['fields'] as List).firstWhere(
          (f) => f['id'] == patch['fieldId'],
        );
        (f['choices'] as List).add(str(patch['choice'], 'choice'));
      case 'AddView':
        keys(patch, {'type', 'view'}, 'AddView');
        final view = Map<String, dynamic>.from(object(patch['view'], 'view'))
          ..['id'] = allocateId();
        (j['views'] as List).add(view);
        final capability = 'views.${view['type']}.v1';
        if (!(j['requires'] as List).contains(capability))
          (j['requires'] as List).add(capability);
      case 'ReorderView':
        keys(patch, {'type', 'viewIds'}, 'ReorderView');
        final ids = array(
          patch['viewIds'],
          'viewIds',
          Limits.views,
        ).cast<String>();
        if (ids.length != views.length ||
            ids.toSet().length != views.length ||
            !ids.toSet().containsAll(views.map((v) => v.id)))
          throw const SpecException('View order must include each view once');
        j['views'] = ids
            .map((id) => (j['views'] as List).firstWhere((v) => v['id'] == id))
            .toList();
      case 'ProposeReminder':
        keys(patch, {'type', 'rule'}, 'ProposeReminder');
        final rule = Map<String, dynamic>.from(object(patch['rule'], 'rule'))
          ..['id'] = allocateId();
        (j['automationRequests'] as List).add(rule);
        if (!(j['requires'] as List).contains('notifications.inApp.v1'))
          (j['requires'] as List).add('notifications.inApp.v1');
      default:
        throw const SpecException('Unsupported semantic patch');
    }
    return AppSpec.parse(jsonEncode(j));
  }
}

class RecordQuery {
  final List<Map<String, dynamic>> filters, sort;
  final int limit;
  final String? cursor;
  RecordQuery(this.filters, this.sort, this.limit, this.cursor);
  factory RecordQuery.parse(CollectionSpec collection, Map<String, dynamic> j) {
    keys(j, {'filters', 'sort', 'limit', 'cursor'}, 'query');
    final limit = j['limit'] ?? 50;
    if (limit is! int || limit < 1 || limit > Limits.pageSize)
      throw const SpecException('Page size must be 1–100');
    final filters = array(
      j['filters'] ?? [],
      'filters',
      Limits.filters,
    ).map((f) => object(f, 'filter')).toList();
    for (final f in filters) {
      keys(f, {'fieldId', 'operator', 'value'}, 'filter');
      final field = collection.field(str(f['fieldId'], 'fieldId'));
      final op = f['operator'];
      if (!{'eq', 'in', 'gte', 'lte', 'contains'}.contains(op))
        throw const SpecException('Unsupported query operator');
      if (op == 'contains' && field.type != FieldType.text)
        throw const SpecException('Contains requires text');
      if ((op == 'gte' || op == 'lte') &&
          !{
            FieldType.integer,
            FieldType.number,
            FieldType.timestamp,
          }.contains(field.type))
        throw const SpecException('Range requires number or timestamp');
      if (op == 'in') {
        for (final v in array(f['value'], 'filter values', 30)) {
          field.normalize(v);
        }
      } else {
        field.normalize(f['value']);
      }
    }
    final sorts = array(
      j['sort'] ?? [],
      'sort',
      2,
    ).map((s) => object(s, 'sort')).toList();
    for (final s in sorts) {
      keys(s, {'fieldId', 'descending'}, 'sort');
      collection.field(str(s['fieldId'], 'fieldId'));
      if (s['descending'] is! bool)
        throw const SpecException('Sort descending must be boolean');
    }
    if (j['cursor'] != null) str(j['cursor'], 'cursor', max: 4096);
    return RecordQuery(filters, sorts, limit, j['cursor']);
  }
}
