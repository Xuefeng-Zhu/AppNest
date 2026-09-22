library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:appnest_spec/appnest_spec.dart';
part 'src/runtime.dart';
part 'src/components.dart';
part 'src/navigation.dart';
part 'src/rich_runtime.dart';
part 'src/editor.dart';

class RuntimeItem {
  final int id, revision;
  final String collectionId;
  final Map<String, dynamic> data;
  final int? capacity, allocated;
  final bool claimed;
  final List<String> allowedActions;
  RuntimeItem(
    this.id,
    this.collectionId,
    this.data, {
    this.revision = 1,
    this.capacity,
    this.allocated,
    this.claimed = false,
    this.allowedActions = const [],
  });
}

class RuntimePage {
  final List<RuntimeItem> items;
  final int total;
  final String? cursor;
  RuntimePage(this.items, this.total, this.cursor);
}

abstract class RuntimeAdapter {
  AppSpec get spec;
  bool get preview;
  bool get readOnly;
  String get role;
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> query);
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  );
  Future<List<String>> members();
  Stream<void> watch();
  bool permits(ActionSpec action);
  List<String> get approvedRuleIds => const [];
  Future<RuntimeItem> get(int recordId) =>
      Future.error(UnsupportedError('Record lookup is unavailable.'));
  Future<RuntimeSummary> summary(
    String collectionId,
    Map<String, dynamic> query,
    String groupFieldId,
  ) => Future.error(UnsupportedError('Grouped summaries are unavailable.'));
  Future<List<RuntimeReminderState>> reminderState(int recordId) =>
      Future.error(UnsupportedError('Reminder state is unavailable.'));
}

class RuntimeSummary {
  final int total;
  final Map<String, int> groups;
  const RuntimeSummary(this.total, this.groups);
}

class RuntimeReminderState {
  final String ruleId, state;
  final DateTime? scheduledAt;
  final bool eligible;
  const RuntimeReminderState(
    this.ruleId,
    this.state, {
    this.scheduledAt,
    this.eligible = true,
  });
}

/// Deliberately has no Client, HTTP, invitations, storage, or scheduler dependency.
class PreviewRuntimeAdapter extends RuntimeAdapter {
  @override
  final AppSpec spec;
  final _changes = StreamController<void>.broadcast();
  final _items = <RuntimeItem>[];
  final _receipts = <String, String>{};
  PreviewRuntimeAdapter(this.spec, {DateTime? now}) {
    for (final col in spec.collections) {
      for (final data in syntheticRecords(col, now: now)) {
        _items.add(
          RuntimeItem(
            _items.length + 1,
            col.id,
            data,
            capacity: col.behaviors.any((b) => b.type == 'capacity.v1')
                ? 4
                : null,
            allocated: 0,
            allowedActions: spec.actions
                .where((a) => a.collectionId == col.id)
                .map((a) => a.id)
                .toList(),
          ),
        );
      }
    }
  }
  @override
  bool get preview => true;
  @override
  bool get readOnly => false;
  @override
  String get role => 'owner';
  @override
  List<String> get approvedRuleIds =>
      spec.automationRequests.map((r) => r.id).toList();
  @override
  bool permits(ActionSpec action) => true;
  @override
  Stream<void> watch() => _changes.stream;
  @override
  Future<List<String>> members() async => ['preview_member'];
  @override
  Future<RuntimePage> query(
    String collectionId,
    Map<String, dynamic> query,
  ) async {
    final collection = spec.collection(collectionId);
    final parsed = RecordQuery.parse(collection, query);
    var items = _matchingItems(collection, parsed);
    final total = items.length;
    final fingerprint = hashJson({
      'collection': collectionId,
      'filters': parsed.filters,
      'sort': parsed.sort,
    });
    if (parsed.cursor != null) {
      final index = items.indexWhere(
        (r) => 'preview-$fingerprint-${r.id}' == parsed.cursor,
      );
      if (index < 0)
        throw const SpecException('Preview cursor is stale. Refresh the view.');
      items = items.skip(index + 1).toList();
    }
    final more = items.length > parsed.limit;
    items = items.take(parsed.limit).toList();
    return RuntimePage(
      items,
      total,
      more ? 'preview-$fingerprint-${items.last.id}' : null,
    );
  }

  List<RuntimeItem> _matchingItems(
    CollectionSpec collection,
    RecordQuery parsed,
  ) {
    Object? comparable(String fieldId, Object? value) =>
        value != null && collection.field(fieldId).type == FieldType.timestamp
        ? DateTime.parse(value as String).toUtc()
        : value;
    var items = _items.where((r) => r.collectionId == collection.id).toList();
    for (final f in parsed.filters) {
      items = items.where((r) {
        final fieldId = f['fieldId'] as String;
        final value = comparable(fieldId, r.data[fieldId]);
        final expected = comparable(
          fieldId,
          f['operator'] == 'in' ? null : f['value'],
        );
        return switch (f['operator']) {
          'eq' => value == expected,
          'in' =>
            (f['value'] as List)
                .map((item) => comparable(fieldId, item))
                .contains(value),
          'contains' =>
            value is String &&
                value.toLowerCase().contains(expected.toString().toLowerCase()),
          'gte' =>
            value != null &&
                expected != null &&
                (value as Comparable).compareTo(expected) >= 0,
          'lt' =>
            value != null &&
                expected != null &&
                (value as Comparable).compareTo(expected) < 0,
          'lte' =>
            value != null &&
                expected != null &&
                (value as Comparable).compareTo(expected) <= 0,
          _ => false,
        };
      }).toList();
    }
    items.sort((a, b) {
      for (final sort in parsed.sort) {
        final fieldId = sort['fieldId'] as String;
        final x = comparable(fieldId, a.data[fieldId]),
            y = comparable(fieldId, b.data[fieldId]);
        // PostgreSQL's runtime compiler uses NULLS LAST in both directions.
        if (x == null && y != null) return 1;
        if (y == null && x != null) return -1;
        if (x == null) continue;
        final compared = x is bool
            ? x.toString().compareTo(y.toString())
            : (x as Comparable).compareTo(y);
        if (compared != 0)
          return sort['descending'] == true ? -compared : compared;
      }
      return a.id.compareTo(b.id);
    });
    return items;
  }

  @override
  Future<RuntimeItem> get(int recordId) async =>
      _items.where((r) => r.id == recordId).firstOrNull ??
      (throw const SpecException('Record unavailable.'));

  @override
  Future<RuntimeSummary> summary(
    String collectionId,
    Map<String, dynamic> query,
    String groupFieldId,
  ) async {
    final field = spec.collection(collectionId).field(groupFieldId);
    if (field.type != FieldType.choice) {
      throw const SpecException('Summaries require a choice field.');
    }
    final groups = {for (final choice in field.choices) choice: 0};
    // Capture one synchronous snapshot, just as the live adapter aggregates in
    // one transaction. Neither pagination nor concurrent preview edits narrow it.
    final items = _matchingItems(
      spec.collection(collectionId),
      RecordQuery.parse(spec.collection(collectionId), query),
    );
    for (final item in items) {
      final value = item.data[groupFieldId];
      if (value != null) groups['$value'] = (groups['$value'] ?? 0) + 1;
    }
    return RuntimeSummary(items.length, groups);
  }

  @override
  Future<List<RuntimeReminderState>> reminderState(int recordId) async {
    final item = await get(recordId);
    return [
      for (final rule in spec.automationRequests.where(
        (r) => r.collectionId == item.collectionId,
      ))
        _previewReminder(rule, item),
    ];
  }

  RuntimeReminderState _previewReminder(AutomationSpec rule, RuntimeItem item) {
    final date = DateTime.tryParse('${item.data[rule.fieldId]}');
    final condition = rule.condition;
    final eligible =
        condition == null || item.data[condition.fieldId] == condition.value;
    return RuntimeReminderState(
      rule.id,
      date == null ? 'unset' : 'pending',
      scheduledAt: date?.subtract(Duration(seconds: rule.offsetSeconds)),
      eligible: eligible,
    );
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    final requestHash = hashJson({
      'action': action.id,
      'record': record?.id,
      'revision': record?.revision,
      'input': input,
    });
    if (_receipts.containsKey(key)) {
      if (_receipts[key] != requestHash)
        throw const SpecException(
          'This command key was already used for different input.',
        );
      return;
    }
    if (!permits(action) ||
        readOnly ||
        hashJson(spec.action(action.id).toJson()) !=
            hashJson(action.toJson())) {
      throw const SpecException('This action is unavailable.');
    }
    final col = spec.collection(action.collectionId);
    if (record != null) {
      final current = await get(record.id);
      if (current.collectionId != col.id ||
          current.revision != record.revision) {
        throw const SpecException(
          'This record changed. Refresh before saving.',
        );
      }
    }
    if (action.capability == 'records.create.v1') {
      final data = col.normalizeRecord(
        Map<String, dynamic>.from(input['data']),
      );
      for (final behavior in col.behaviors.where(
        (b) => b.type == 'workflow.v1',
      )) {
        if (data[behavior.fieldId] !=
            col.field(behavior.fieldId!).choices.first) {
          throw const SpecException(
            'New records must start in the initial status.',
          );
        }
      }
      _items.add(
        RuntimeItem(
          _items.length + 1,
          col.id,
          data,
          capacity: input['capacity'] as int?,
          allocated: 0,
          allowedActions: spec.actions
              .where((a) => a.collectionId == col.id)
              .map((a) => a.id)
              .toList(),
        ),
      );
    } else if (record != null) {
      final data = {...record.data};
      var cap = record.capacity,
          allocated = record.allocated,
          claimed = record.claimed;
      switch (action.capability) {
        case 'records.patch.v1':
          final patch = Map<String, dynamic>.from(input['data']);
          if (col.behaviors.any(
            (b) => b.fieldId != null && patch.containsKey(b.fieldId),
          )) {
            throw const SpecException(
              'Use the approved status or assignment action.',
            );
          }
          data.addAll(patch);
        case 'assignment.assign.v1' || 'workflow.transition.v1':
          final behavior = col.behavior(action.behaviorId!);
          if (action.capability == 'workflow.transition.v1' &&
              !(behavior.transitions[data[behavior.fieldId]] ?? []).contains(
                input['value'],
              )) {
            throw const SpecException('That status transition is not allowed.');
          }
          if (action.capability == 'assignment.assign.v1' &&
              !(await members()).contains(input['value'])) {
            throw const SpecException('Choose an eligible member.');
          }
          data[behavior.fieldId!] = input['value'];
        case 'capacity.configure.v1':
          cap = input['capacity'] as int;
          if (cap < (allocated ?? 0))
            throw const SpecException('Capacity cannot be below sign-ups.');
        case 'capacity.claim.v1':
          if (!claimed) {
            if ((allocated ?? 0) >= (cap ?? 0))
              throw const SpecException('This preview shift is full.');
            claimed = true;
            allocated = (allocated ?? 0) + 1;
          }
        case 'capacity.release.v1':
          if (claimed) {
            claimed = false;
            allocated = (allocated ?? 1) - 1;
          }
      }
      _items[_items.indexWhere((r) => r.id == record.id)] = RuntimeItem(
        record.id,
        col.id,
        col.normalizeRecord(data),
        revision: record.revision + 1,
        capacity: cap,
        allocated: allocated,
        claimed: claimed,
        allowedActions: record.allowedActions,
      );
    }
    _receipts[key] = requestHash;
    _changes.add(null);
  }

  void dispose() => _changes.close();
}
