import 'package:appnest_spec/appnest_spec.dart';

/// A deliberately narrow extraction of explicit creation requirements. It does
/// not infer a product from keywords or substitute a template. Ambiguous prose
/// remains the provider's responsibility; supported, literal contracts can be
/// checked before an otherwise schema-valid definition reaches preview.
class GenerationRequirements {
  final String? policy;
  final Map<String, List<String>> choices;
  final List<String> filters, groupedSummaries;
  final Map<String, String> filteredTabs;
  final bool searchableList, singleRecordCollection, dedicatedRecordRoutes;
  final bool sharedRecordCreation;
  final OwnerInboxReminderRequirement? ownerInboxReminder;

  const GenerationRequirements({
    this.policy,
    this.choices = const {},
    this.filters = const [],
    this.groupedSummaries = const [],
    this.filteredTabs = const {},
    this.searchableList = false,
    this.singleRecordCollection = false,
    this.dedicatedRecordRoutes = false,
    this.sharedRecordCreation = false,
    this.ownerInboxReminder,
  });

  factory GenerationRequirements.fromRequest(String request) {
    final singleCollections =
        RegExp(
              r'\b(?:use|using)\s+(?:one|a single|single)\s+[A-Za-z][A-Za-z0-9 -]{0,60}?\s+collection\s+with\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .where(
              (match) => _affirmativeClause(request, match.start),
            )
            .toList();
    final otherCollections =
        RegExp(
              r'\b(?:another|second|two|multiple)\s+(?:[A-Za-z][A-Za-z0-9 -]{0,40}?\s+)?collections?\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .any(
              (match) => _affirmativeClause(request, match.start),
            );
    // More than one affirmative mention is ambiguous even when a second
    // collection is introduced as "add a People collection", not "another".
    // Falling back to the general grammar is safer than constraining that app.
    final collectionMentions =
        RegExp(
              r'\bcollections?\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .where(
              (match) => _affirmativeClause(request, match.start),
            )
            .length;
    final singleRecordCollection =
        singleCollections.length == 1 &&
        collectionMentions == 1 &&
        !otherCollections;
    final dedicatedRecordRoutes =
        singleRecordCollection &&
        RegExp(
              r'\b(?:include|use|add)\s+(?:a\s+)?dedicated\s+[A-Za-z][A-Za-z0-9 -]{0,40}?\s+details(?:\s+page)?\s+and\s+(?:a\s+)?shared\s+add/edit\s+[A-Za-z][A-Za-z0-9 -]{0,40}?\s+(?:form\s+)?pages?\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .any(
              (match) => _affirmativeClause(request, match.start),
            );
    final policies =
        RegExp(
              r'\b(?:use|using|with)\s+(?:the\s+)?(personalTracker\.v1|groupWorkflow\.v1|groupCapacitySignup\.v1)\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .where((match) => _affirmativeClause(request, match.start))
            .map(
              (match) => policyPresets.firstWhere(
                (value) => value.toLowerCase() == match.group(1)!.toLowerCase(),
              ),
            )
            .toSet();
    final choices = <String, List<String>>{};
    for (final match in RegExp(
      r'(?:^|[,.;]|\band\b|\bwith\b|\blabeled\b)\s*([A-Za-z][A-Za-z0-9 -]{0,60}?)\s*\((?:required|optional)\s+choice:\s*([^()]+)\)',
      caseSensitive: false,
    ).allMatches(request)) {
      // Include the field-label prefix when checking a negative example such
      // as "Do not add Status (required choice: Open, Done)".
      if (!_affirmativeClause(
        request,
        match.start + match.group(0)!.indexOf('('),
      )) {
        continue;
      }
      final label = match
          .group(1)!
          .trim()
          .replaceFirst(
            RegExp(r'^(?:(?:and|fields|field)\s+)+', caseSensitive: false),
            '',
          );
      final values = match
          .group(2)!
          .split(',')
          .map((value) => value.trim())
          .toList();
      if (values.isNotEmpty &&
          values.length <= 30 &&
          values.every((value) => value.isNotEmpty && value.length <= 80) &&
          values.toSet().length == values.length) {
        choices[label] = values;
      }
    }
    final filters = <String>[];
    final summaries = <String>[];
    for (final label in choices.keys) {
      final escaped = RegExp.escape(label);
      // Covers literal field lists such as "Category/Packing status filters".
      final filterPattern = RegExp(
        '\\b$escaped(?:(?:\\s*/\\s*|\\s+and\\s+)[A-Za-z][A-Za-z0-9 /-]{0,60})?\\s+filters?\\b',
        caseSensitive: false,
      );
      if (filterPattern
          .allMatches(request)
          .any(
            (match) => _affirmativeClause(request, match.start),
          )) {
        filters.add(label);
      }
      if (RegExp(
            '(?:grouped (?:count )?summary|grouped counts?|grouping saved (?:entries|records)|summary(?: grouped)?)\\s+by\\s+$escaped\\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any((match) => _affirmativeClause(request, match.start))) {
        summaries.add(label);
      }
    }
    final tabs = <String, String>{};
    for (final match in RegExp(
      r'\b(?:a|an|the)\s+([A-Za-z][A-Za-z0-9 -]{0,40}?)\s+(?:tab|page)\s+filtered\s+to\s+([^.;]+)',
      caseSensitive: false,
    ).allMatches(request)) {
      if (!_affirmativeClause(request, match.start)) continue;
      final text = match.group(2)!.trim();
      final values = choices.values
          .expand((value) => value)
          .where(
            (value) => RegExp(
              '^${RegExp.escape(value)}(?:\\b|\$)',
              caseSensitive: false,
            ).hasMatch(text),
          )
          .toSet();
      if (values.length == 1) tabs[match.group(1)!.trim()] = values.single;
    }
    return GenerationRequirements(
      policy: policies.length == 1 && !_ambiguousPolicyAlternatives(request)
          ? policies.single
          : null,
      choices: choices,
      filters: filters,
      groupedSummaries: summaries,
      filteredTabs: tabs,
      singleRecordCollection: singleRecordCollection,
      dedicatedRecordRoutes: dedicatedRecordRoutes,
      searchableList:
          RegExp(
                r'\bsearchable(?:\s+[A-Za-z][A-Za-z-]*){0,3}\s+(?:list|table)\b',
                caseSensitive: false,
              )
              .allMatches(request)
              .any(
                (match) => _literalAffirmativeSpan(
                  request,
                  match.start,
                  match.end,
                ),
              ),
      ownerInboxReminder: _ownerInboxReminder(request),
      sharedRecordCreation: _sharedRecordCreation(request, policies),
    );
  }

  bool get isEmpty =>
      policy == null &&
      choices.isEmpty &&
      filters.isEmpty &&
      groupedSummaries.isEmpty &&
      filteredTabs.isEmpty &&
      !searchableList &&
      !singleRecordCollection &&
      !dedicatedRecordRoutes &&
      !sharedRecordCreation &&
      ownerInboxReminder == null;

  String? get preferredPolicy =>
      policy ?? (sharedRecordCreation ? 'groupWorkflow.v1' : null);

  Map<String, dynamic> toJson() => {
    if (preferredPolicy != null) 'policyPresetRequest': preferredPolicy,
    if (sharedRecordCreation) 'sharedRecordCreation': true,
    if (choices.isNotEmpty) 'exactChoiceFields': choices,
    if (filters.isNotEmpty) 'visibleChoiceFilters': filters,
    if (groupedSummaries.isNotEmpty) 'groupedSummaries': groupedSummaries,
    if (filteredTabs.isNotEmpty) 'filteredTabs': filteredTabs,
    if (searchableList) 'searchableRecordList': true,
    if (singleRecordCollection) 'singleRecordCollection': true,
    if (dedicatedRecordRoutes) 'dedicatedRecordRoutes': true,
    if (ownerInboxReminder != null)
      'ownerInboxReminder': ownerInboxReminder!.toJson(),
  };

  void validate(AppSpec spec) {
    final issues = <String>[];
    if (singleRecordCollection && spec.collections.length != 1) {
      issues.add('Use exactly one collection as explicitly requested.');
    }
    if (policy != null && spec.policyPresetRequest != policy) {
      issues.add('Use the explicitly requested policyPresetRequest $policy.');
    }
    if (sharedRecordCreation &&
        spec.policyPresetRequest != 'groupWorkflow.v1') {
      issues.add(
        'The explicitly requested participant record creation needs '
        'policyPresetRequest groupWorkflow.v1 so approved members can add '
        'their records. A personalTracker.v1 app restricts writes to its owner.',
      );
    }
    final visibleViews = spec.navigation == null
        ? spec.views
        : {
                spec.navigation!.entryPageId,
                ...spec.navigation!.tabs.map((tab) => tab.pageId),
              }
              .expand((pageId) => spec.page(pageId).viewIds.map(spec.view))
              .toList();
    if (searchableList &&
        !visibleViews.any(
          (view) =>
              {'list', 'table'}.contains(view.type) &&
              view.titleFieldId != null &&
              spec
                      .collection(view.collectionId)
                      .field(view.titleFieldId!)
                      .type ==
                  FieldType.text,
        )) {
      issues.add(
        'A requested searchable record list needs a text titleFieldId on a visible list or table. Choice filters are optional.',
      );
    }
    ownerInboxReminder?.validate(spec, issues);
    for (final entry in choices.entries) {
      final matches = [
        for (final collection in spec.collections)
          for (final field in collection.fields)
            if (field.label.toLowerCase() == entry.key.toLowerCase())
              (collection, field),
      ];
      if (matches.length != 1) {
        issues.add(
          'Include the explicitly requested ${entry.key} choice field.',
        );
        continue;
      }
      final (collection, field) = matches.single;
      if (field.type != FieldType.choice ||
          field.choices.length != entry.value.length ||
          field.choices.asMap().entries.any(
            (item) => item.value != entry.value[item.key],
          )) {
        issues.add(
          '${entry.key} must preserve the requested choices in order: ${entry.value.join(', ')}.',
        );
      }
      if (filters.contains(entry.key) &&
          !visibleViews.any(
            (view) =>
                {
                  'list',
                  'board',
                  'table',
                  'calendar',
                  'timeline',
                  'imageCards',
                  'gallery',
                  'checklist',
                }.contains(view.type) &&
                view.collectionId == collection.id &&
                view.filterFieldIds.contains(field.id),
          )) {
        issues.add(
          'Expose ${entry.key} with filterFieldIds on its visible record list.',
        );
      }
      if (groupedSummaries.contains(entry.key) &&
          !visibleViews.any(
            (view) =>
                view.type == 'summary' &&
                view.collectionId == collection.id &&
                view.groupByFieldId == field.id,
          )) {
        issues.add(
          'A visible summary must groupByFieldId the requested ${entry.key} field.',
        );
      }
    }
    for (final entry in filteredTabs.entries) {
      final navigation = spec.navigation;
      final tabs =
          navigation?.tabs
              .where(
                (tab) => tab.label.toLowerCase() == entry.key.toLowerCase(),
              )
              .toList() ??
          [];
      final fields = [
        for (final collection in spec.collections)
          for (final field in collection.fields)
            if (field.type == FieldType.choice &&
                field.choices.contains(entry.value))
              (collection, field),
      ];
      // Do not guess which field was intended when two fields share this value.
      if (fields.length != 1) continue;
      final (collection, field) = fields.single;
      final views = tabs
          .expand((tab) => spec.page(tab.pageId).viewIds.map(spec.view))
          .where(
            (view) =>
                view.collectionId == collection.id &&
                !{'summary', 'metric', 'chart'}.contains(view.type),
          )
          .toList();
      if (views.isEmpty ||
          views.any(
            (view) => !(view.query?['filters'] as List? ?? []).any(
              (filter) =>
                  filter is Map &&
                  filter['fieldId'] == field.id &&
                  filter['operator'] == 'eq' &&
                  filter['value'] == entry.value,
            ),
          )) {
        issues.add(
          '${entry.key} must query only ${entry.value} records using an equality filter on ${field.label}.',
        );
      }
    }
    if (issues.isNotEmpty) throw SpecException(issues.join(' '));
  }
}

bool _sharedRecordCreation(String request, Set<String> explicitPolicies) {
  // Preserve engineered policy contracts and leave contradictory/undecided
  // policy prose to the provider. Sharing words alone never grant access.
  if (explicitPolicies.isNotEmpty ||
      RegExp(
            r'\b(?:personalTracker\.v1|groupWorkflow\.v1|groupCapacitySignup\.v1)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )) {
    return false;
  }
  final scopes =
      RegExp(
            r'\b(?:apps?|collections?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .where(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          );
  if (scopes
              .where((match) => match.group(0)!.toLowerCase().startsWith('app'))
              .length >
          1 ||
      scopes
              .where(
                (match) =>
                    match.group(0)!.toLowerCase().startsWith('collection'),
              )
              .length >
          1 ||
      RegExp(
            r'\b(?:another|second|multiple|two)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:apps?|collections?|trackers?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )) {
    return false;
  }
  return RegExp(
        r'\b(?:everyone|(?:all\s+)?(?:members|friends|participants|neighbors|people|teammates|family\s+members))\s+(?:(?:to|can|should|must|will)\s+|will\s+be\s+able\s+to\s+)?(?:add|create|submit|enter)s?\s+(?:their|our)\s+(?:own\s+)?[A-Za-z][A-Za-z-]{0,60}\b',
        caseSensitive: false,
      )
      .allMatches(request)
      .any(
        (match) => _literalAffirmativeSpan(request, match.start, match.end),
      );
}

bool _ambiguousPolicyAlternatives(String request) {
  const name =
      r'(personalTracker\.v1|groupWorkflow\.v1|groupCapacitySignup\.v1)';
  return RegExp(
        '$name\\s+(?:or|versus|vs\\.?)\\s+(?:(?:use|using|with)\\s+)?$name',
        caseSensitive: false,
      )
      .allMatches(request)
      .any(
        (match) =>
            match.group(1)!.toLowerCase() != match.group(2)!.toLowerCase() &&
            _literalAffirmativeSpan(request, match.start, match.end),
      );
}

/// Literal owner-inbox scheduling requirements, independent of authored IDs or
/// field labels. AppSpec has already validated every rule's references/types.
class OwnerInboxReminderRequirement {
  final bool optionalTimestamp, distinctOptionalDueDate, openCompletedCondition;
  const OwnerInboxReminderRequirement({
    this.optionalTimestamp = false,
    this.distinctOptionalDueDate = false,
    this.openCompletedCondition = false,
  });

  Map<String, dynamic> toJson() => {
    'effect': 'notifyOwner',
    'optionalTimestamp': optionalTimestamp,
    'distinctOptionalDueDate': distinctOptionalDueDate,
    'openCompletedCondition': openCompletedCondition,
  };

  void validate(AppSpec spec, List<String> issues) {
    if (spec.policyPresetRequest != 'personalTracker.v1') {
      issues.add(
        'Explicit personal inbox reminders need policyPresetRequest personalTracker.v1.',
      );
    }
    final rules = spec.automationRequests
        .where((rule) => rule.effect == 'notifyOwner')
        .toList();
    if (rules.isEmpty) {
      issues.add(
        'The explicit AppNest inbox reminder needs an automationRequests rule '
        'with a beforeTimestamp trigger and notifyOwner inApp effect; a stored '
        'reminder-time field or an Inbox record view alone does not deliver reminders.',
      );
      return;
    }
    bool optional(AutomationSpec rule) =>
        !spec.collection(rule.collectionId).field(rule.fieldId).required;
    bool separateDueDate(AutomationSpec rule) {
      final collection = spec.collection(rule.collectionId);
      final separate = collection.fields.any(
        (field) =>
            field.id != rule.fieldId &&
            field.type == FieldType.timestamp &&
            !field.required,
      );
      final calendarFields = spec.views
          .where(
            (view) =>
                view.collectionId == collection.id && view.type == 'calendar',
          )
          .map((view) => view.options['dateFieldId']);
      return separate &&
          calendarFields.every(
            (id) =>
                id != rule.fieldId &&
                id is String &&
                !collection.field(id).required,
          );
    }

    bool openCondition(AutomationSpec rule) {
      final condition = rule.condition;
      if (condition == null || condition.value.toLowerCase() != 'open') {
        return false;
      }
      final field = spec.collection(rule.collectionId).field(condition.fieldId);
      final choices = field.choices.map((value) => value.toLowerCase()).toSet();
      return field.type == FieldType.choice &&
          choices.containsAll({'open', 'completed'});
    }

    if (!rules.any(
      (rule) =>
          (!optionalTimestamp || optional(rule)) &&
          (!distinctOptionalDueDate || separateDueDate(rule)) &&
          (!openCompletedCondition || openCondition(rule)),
    )) {
      issues.add(
        'The owner inbox reminder rule must use '
        '${optionalTimestamp ? 'an optional' : 'a'} timestamp field'
        '${distinctOptionalDueDate ? ', distinct from a second optional due-date timestamp and any due-date calendar binding' : ''}'
        '${openCompletedCondition ? ', with a condition on the declared Open/Completed choice field equal to its Open value so completed items do not notify' : ''}. '
        'Use the authored collection/field IDs and actual declared choice casing.',
      );
    }
  }
}

OwnerInboxReminderRequirement? _ownerInboxReminder(String request) {
  // This gate addresses one explicit personal scheduling scope. Multiple apps,
  // collections, recipients or shared workflows need provider interpretation.
  final scopes =
      RegExp(
            r'\b(?:apps?|collections?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .where(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          );
  if (scopes
              .where((match) => match.group(0)!.toLowerCase().startsWith('app'))
              .length >
          1 ||
      scopes
              .where(
                (match) =>
                    match.group(0)!.toLowerCase().startsWith('collection'),
              )
              .length >
          1 ||
      RegExp(
            r'\b(?:another|second|multiple|two)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:apps?|collections?|trackers?)\b|\b(?:shared|team|household|everyone|members|colleagues)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )) {
    return null;
  }
  final inboxes =
      RegExp(
            r"\b(?:my\s+(?:AppNest\s+)?|personal\s+(?:AppNest\s+)?|owner(?:'s)?\s+|AppNest\s+)inbox\b",
            caseSensitive: false,
          )
          .allMatches(request)
          .where(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )
          .toList();
  if (inboxes.length != 1) return null;
  final inbox = inboxes.single;
  final clause = _clauseAt(request, inbox.start, inbox.end);
  if (!RegExp(
        r'\b(?:reminders?|remind\s+me)\b',
        caseSensitive: false,
      ).hasMatch(clause) ||
      (!RegExp(
        r'\b(?:my|personal|owner)\b',
        caseSensitive: false,
      ).hasMatch(clause))) {
    return null;
  }
  bool explicit(String pattern) => RegExp(pattern, caseSensitive: false)
      .allMatches(request)
      .any((match) => _literalAffirmativeSpan(request, match.start, match.end));
  final optionalReminder = explicit(
    r'\boptional\s+(?:[A-Za-z][A-Za-z-]*\s+){0,2}reminder\s+(?:time|date|timestamp)s?\b|\breminder\s+(?:time|date|timestamp)s?\s+(?:is\s+)?optional\b',
  );
  final optionalDue = explicit(r'\boptional\s+due\s+dates?\b');
  final separate = explicit(
    r'\b(?:separate|distinct|different)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}reminder\s+(?:time|date|timestamp)s?\b|\breminder\s+(?:time|date|timestamp)s?\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:separate|distinct|different)\b',
  );
  return OwnerInboxReminderRequirement(
    optionalTimestamp: optionalReminder,
    distinctOptionalDueDate: optionalDue && separate,
    openCompletedCondition: explicit(
      r'\b(?:open\s*(?:and|or|/|,)\s*completed|completed\s*(?:and|or|/|,)\s*open)\b',
    ),
  );
}

String _clauseAt(String request, int start, int end) {
  final before = request.substring(0, start);
  final from = before.lastIndexOf(RegExp(r'[.;\n]')) + 1;
  final following = RegExp(r'[.;\n]').firstMatch(request.substring(end));
  return request.substring(
    from,
    following == null ? request.length : end + following.start,
  );
}

bool _literalAffirmativeSpan(String request, int start, int end) {
  final before = request.substring(0, start);
  final from = before.lastIndexOf(RegExp(r'[.;\n]')) + 1;
  final clause = _clauseAt(request, start, end);
  final prefix = request.substring(from, start);
  final suffix = clause.substring(end - from);
  return !RegExp(
        r'\b(?:example|examples|sample|hypothetical|maybe|perhaps|consider|later|eventually)\b',
        caseSensitive: false,
      ).hasMatch(clause) &&
      !RegExp(
        r"\b(?:do not|don't|never|without|no|not|avoid)\b",
        caseSensitive: false,
      ).hasMatch(prefix) &&
      !RegExp(
        r'^\s*(?:is|are|would be)?\s*(?:not\s+(?:needed|required|wanted)|unnecessary|only\s+an?\s+example)\b',
        caseSensitive: false,
      ).hasMatch(suffix);
}

bool _affirmativeClause(String request, int at) {
  final before = request.substring(0, at);
  final start = before.lastIndexOf(RegExp(r'[.;]')) + 1;
  return !RegExp(
    r"\b(?:do not|don't|never|without|no)\b",
    caseSensitive: false,
  ).hasMatch(before.substring(start));
}
