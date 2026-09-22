import 'dart:io';
import 'dart:ui' as ui;

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in artifacts are synthetic renderer evidence, never live server proof.
/// flutter test test/visual_capture_test.dart \
///   --dart-define=APPNEST_CAPTURE_DIR=/tmp/appnest-miniapp-captures
void main() {
  const output = String.fromEnvironment('APPNEST_CAPTURE_DIR');
  setUpAll(() async {
    if (output.isEmpty) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    // Locate the bundled SDK icon font without checking in machine-specific paths.
    var directory = File(Platform.resolvedExecutable).parent;
    for (var level = 0; level < 10; level++) {
      final font = File(
        '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await font.exists()) {
        final textFont = File(
          '${directory.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        await (FontLoader(
          'AppNestCapture',
        )..addFont(textFont.readAsBytes().then(ByteData.sublistView))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
        break;
      }
      directory = directory.parent;
    }
  });
  final moment = DateTime(2026, 9, 22, 12);
  final cases = <(String, Size, MiniAppLocation)>[
    (
      'today-desktop',
      const Size(1440, 1000),
      const MiniAppLocation('todayPage'),
    ),
    ('today-mobile', const Size(390, 844), const MiniAppLocation('todayPage')),
    ('tasks-mobile', const Size(390, 844), const MiniAppLocation('tasksPage')),
    (
      'details-mobile',
      const Size(390, 844),
      const MiniAppLocation('taskDetailPage', recordId: 2),
    ),
    (
      'editor-mobile',
      const Size(390, 844),
      const MiniAppLocation('taskEditorPage', recordId: 2, editing: true),
    ),
    (
      'progress-mobile',
      const Size(390, 844),
      const MiniAppLocation('progressPage'),
    ),
  ];
  for (final (name, size, location) in cases) {
    testWidgets('isolated preview visual layout $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = PreviewRuntimeAdapter(
        dailyPlannerTemplate(),
        now: moment,
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: output.isEmpty ? null : 'AppNestCapture',
            ),
            home: Scaffold(
              body: MiniAppRuntime(
                adapter: adapter,
                initialLocation: location,
                clock: () => moment,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (output.isNotEmpty) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    });
  }
}
