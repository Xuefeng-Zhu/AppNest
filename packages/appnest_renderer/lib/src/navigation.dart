part of '../appnest_renderer.dart';

/// A semantic destination, safe to serialize in an authenticated host URL.
@immutable
class MiniAppLocation {
  final String pageId;
  final int? recordId;
  final bool editing;
  const MiniAppLocation(this.pageId, {this.recordId, this.editing = false});
  @override
  bool operator ==(Object other) =>
      other is MiniAppLocation &&
      other.pageId == pageId &&
      other.recordId == recordId &&
      other.editing == editing;
  @override
  int get hashCode => Object.hash(pageId, recordId, editing);
}

enum MiniAppNavigationKind { push, pop, external }

/// The host must use [navigate] for browser URL changes and [canLeave] before
/// closing the app. Both share the editor's discard confirmation.
class MiniAppController extends ChangeNotifier {
  MiniAppLocation? _location;
  MiniAppNavigationKind _navigationKind = MiniAppNavigationKind.external;
  Future<bool> Function(MiniAppLocation)? _navigate;
  Future<bool> Function()? _back, _canLeave;
  MiniAppLocation? get location => _location;
  MiniAppNavigationKind get navigationKind => _navigationKind;
  Future<bool> navigate(MiniAppLocation location) async =>
      await _navigate?.call(location) ?? false;
  Future<bool> back() async => await _back?.call() ?? false;
  Future<bool> canLeave() async => await _canLeave?.call() ?? true;
  void _update(MiniAppLocation location, MiniAppNavigationKind kind) {
    _location = location;
    _navigationKind = kind;
    notifyListeners();
  }

  void _detach() {
    _navigate = null;
    _back = null;
    _canLeave = null;
  }
}

class MiniAppRuntime extends StatelessWidget {
  final RuntimeAdapter adapter;
  final MiniAppController? controller;
  final MiniAppLocation? initialLocation;
  final ValueChanged<MiniAppLocation>? onLocationChanged;
  final DateTime Function()? clock;
  final MiniAppEditConfiguration? editConfiguration;
  const MiniAppRuntime({
    super.key,
    required this.adapter,
    this.controller,
    this.initialLocation,
    this.onLocationChanged,
    this.clock,
    this.editConfiguration,
  });
  @override
  Widget build(BuildContext context) => _VisualEditScope(
    configuration: adapter.preview ? editConfiguration : null,
    child: adapter.spec.navigation == null
        ? Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: _appColor(adapter.spec.theme),
                brightness: Theme.of(context).brightness,
              ),
            ),
            child: _LegacyMiniAppRuntime(adapter: adapter),
          )
        : _RichMiniAppRuntime(
            adapter: adapter,
            controller: controller,
            initialLocation: initialLocation,
            onLocationChanged: onLocationChanged,
            clock: clock ?? DateTime.now,
          ),
  );
}

Color _appColor(String theme) => switch (theme) {
  'amber' => const Color(0xffa86012),
  'blue' => const Color(0xff386ad2),
  'rose' => const Color(0xffaf4b71),
  'sage' => const Color(0xff507963),
  _ => const Color(0xff177d79),
};

IconData _pageIcon(String icon) => switch (icon) {
  'today' || 'calendar' => Icons.today_outlined,
  'check' || 'checklist' || 'tasks' || 'list' => Icons.checklist_rounded,
  'chart' || 'progress' => Icons.donut_small_outlined,
  'home' => Icons.home_outlined,
  'book' => Icons.menu_book_outlined,
  'people' => Icons.people_outline,
  _ => Icons.widgets_outlined,
};
