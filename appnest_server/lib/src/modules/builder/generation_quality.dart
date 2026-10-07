import 'package:appnest_spec/appnest_spec.dart';

/// Generation must produce an app that can be used from its visible pages.
/// These checks supplement schema validation without changing old definitions.
void validateGeneratedExperience(AppSpec spec, {AppSpec? baseline}) {
  final existing = baseline == null ? <String, String>{} : _issues(baseline);
  for (final issue in _issues(spec).entries) {
    if (!existing.containsKey(issue.key)) throw SpecException(issue.value);
  }
}

const _recordViewTypes = {
  'list',
  'board',
  'capacity',
  'action',
  'table',
  'calendar',
  'timeline',
  'imageCards',
  'gallery',
  'checklist',
};

Map<String, String> _issues(AppSpec spec) {
  final issues = <String, String>{};
  final navigation = spec.navigation;
  final mainPages = navigation == null
      ? <PageSpec>[]
      : {
          navigation.entryPageId,
          ...navigation.tabs.map((tab) => tab.pageId),
        }.map(spec.page).toList();
  final mainViews = navigation == null
      ? spec.views
      : mainPages.expand((page) => page.viewIds.map(spec.view)).toList();
  if (spec.collections.isEmpty &&
      spec.views.any(
        (view) => {
          'clock',
          'timer',
          'deviceInfo',
          'deviceControl',
        }.contains(view.type),
      ) &&
      !mainViews.any(
        (view) => {
          'clock',
          'timer',
          'deviceInfo',
          'deviceControl',
        }.contains(view.type),
      )) {
    issues['utility:unreachable'] = 'A utility app needs a clock, timer or device component on its entry page or tabs.';
  }
  for (final collection in spec.collections) {
    final actions = spec.actions
        .where((action) => action.collectionId == collection.id)
        .toList();
    if (!actions.any(
      (action) => {
        'records.create.v1',
        'records.patch.v1',
      }.contains(action.capability),
    )) {
      continue;
    }
    for (final capability in ['records.create.v1', 'records.patch.v1']) {
      if (!actions.any((action) => action.capability == capability)) {
        issues['${collection.id}:missing:$capability'] =
            '${collection.label} needs both create and edit actions to be usable.';
      }
    }
    bool exposes(ViewSpec view, String capability) =>
        view.collectionId == collection.id &&
        view.actionIds.any((id) => spec.action(id).capability == capability);
    final canCreate = navigation == null
        ? mainViews.any((view) => exposes(view, 'records.create.v1'))
        : mainPages.any((page) {
            final id = page.primaryActionId;
            if (id == null) {
              // Renderer sections expose their own create buttons when there
              // is no page-level primary action.
              return page.viewIds
                  .map(spec.view)
                  .any(
                    (view) =>
                        view.type != 'details' &&
                        view.type != 'form' &&
                        exposes(view, 'records.create.v1'),
                  );
            }
            final action = spec.action(id);
            return action.collectionId == collection.id &&
                action.capability == 'records.create.v1' &&
                page.viewIds
                    .map(spec.view)
                    .any(
                      (view) => view.type != 'details' && view.type != 'form',
                    );
          });
    final recordViews = [
      ...mainViews.where((view) => _recordViewTypes.contains(view.type)),
      for (final view in mainViews.where(
        (view) => _recordViewTypes.contains(view.type),
      ))
        if (view.detailPageId != null)
          ...spec
              .page(view.detailPageId!)
              .viewIds
              .map(spec.view)
              .where(
                (destination) => destination.type == 'details',
              ),
    ];
    if (!canCreate) {
      issues['${collection.id}:unreachable:create'] =
          '${collection.label} needs a reachable add control on the entry page or a tab.';
    }
    if (!recordViews.any((view) => exposes(view, 'records.patch.v1'))) {
      issues['${collection.id}:unreachable:edit'] =
          '${collection.label} needs a reachable edit control on a record view '
          'or linked details page, with a matching form.';
    }
  }
  return issues;
}
