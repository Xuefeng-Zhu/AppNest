import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/mini_app/mini_app_screen.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_app_navigation_test.dart' show NavigationClient;

void main() {
  final client = NavigationClient();
  setUpAll(() => transport.client = client);
  setUp(() {
    client.preview = PreviewRuntimeAdapter(dailyPlannerTemplate());
    client.calls.clear();
  });
  tearDown(() => client.preview.dispose());
  tearDownAll(() async {
    client.close();
    await client.events.close();
  });

  testWidgets('invitation explains roles without creating a link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: MiniAppScreen(appId: 1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mini-app menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite to app'));
    await tester.pumpAndSettle();
    expect(find.text('Access level'), findsOneWidget);
    expect(
      find.textContaining('Cannot change app structure or sharing.'),
      findsOneWidget,
    );
    expect(find.text('Recipient account ID'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewer').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Can view shared records.'), findsOneWidget);
    await tester.tap(find.text('Invite a specific account (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Recipient account ID'), findsOneWidget);
    expect(find.text('They can copy this from Your account.'), findsOneWidget);
    expect(client.calls, isNot(contains('apps.invite')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
