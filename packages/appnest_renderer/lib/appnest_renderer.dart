library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:appnest_spec/appnest_spec.dart';
part 'src/runtime.dart';
part 'src/components.dart';

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
}

/// Deliberately has no Client, HTTP, invitations, storage, or scheduler dependency.
class PreviewRuntimeAdapter extends RuntimeAdapter {
  @override
  final AppSpec spec;
  final _changes = StreamController<void>.broadcast();
  final _items = <RuntimeItem>[];
  PreviewRuntimeAdapter(this.spec) {
    for (final col in spec.collections) {
      for (final data in syntheticRecords(col)) {
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
    final parsed = RecordQuery.parse(spec.collection(collectionId), query);
    var items = _items.where((r) => r.collectionId == collectionId).toList();
    for (final f in (query['filters'] as List? ?? [])) {
      items = items.where((r) {
        final value = r.data[f['fieldId']], expected = f['value'];
        return switch (f['operator']) {
          'eq' => value == expected,
          'in' => (expected as List).contains(value),
          'contains' =>
            value is String &&
                value.toLowerCase().contains(expected.toString().toLowerCase()),
          'gte' =>
            value != null && (value as Comparable).compareTo(expected) >= 0,
          'lte' =>
            value != null && (value as Comparable).compareTo(expected) <= 0,
          _ => false,
        };
      }).toList();
    }
    items.sort((a, b) {
      for (final sort in parsed.sort) {
        final x = a.data[sort['fieldId']], y = b.data[sort['fieldId']];
        final compared = x == null
            ? (y == null ? 0 : 1)
            : y == null
            ? -1
            : (x is bool
                  ? x.toString().compareTo(y.toString())
                  : (x as Comparable).compareTo(y));
        if (compared != 0)
          return sort['descending'] == true ? -compared : compared;
      }
      return a.id.compareTo(b.id);
    });
    final total = items.length;
    if (parsed.cursor != null) {
      final index = items.indexWhere((r) => 'preview-${r.id}' == parsed.cursor);
      if (index < 0)
        throw const SpecException('Preview cursor is stale. Refresh the view.');
      items = items.skip(index + 1).toList();
    }
    final more = items.length > parsed.limit;
    items = items.take(parsed.limit).toList();
    return RuntimePage(items, total, more ? 'preview-${items.last.id}' : null);
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    final col = spec.collection(action.collectionId);
    if (action.capability == 'records.create.v1') {
      _items.add(
        RuntimeItem(
          _items.length + 1,
          col.id,
          col.normalizeRecord(Map<String, dynamic>.from(input['data'])),
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
          data.addAll(Map<String, dynamic>.from(input['data']));
        case 'assignment.assign.v1' || 'workflow.transition.v1':
          data[col.behavior(action.behaviorId!).fieldId!] = input['value'];
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
    _changes.add(null);
  }

  void dispose() => _changes.close();
}
