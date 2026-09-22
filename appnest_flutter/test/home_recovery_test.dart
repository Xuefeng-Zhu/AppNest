import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/home/home_load_failure.dart';
import 'package:appnest_flutter/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Test-only transport. Production HomeScreen still uses authenticated endpoints.
class TestClient extends Client {
  TestClient() : super('http://localhost:8180/');
  Object? failure;
  Completer<void>? pending;
  int workspaceRequests = 0;
  bool aiAvailable = false;
  final methods = <String>[];

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    methods.add('$endpoint.$method');
    expectSync(authenticated, isTrue);
    if (method == 'workspaces') {
      workspaceRequests++;
      await pending?.future;
      if (failure != null) throw failure!;
    }
    return switch ('$endpoint.$method') {
      'apps.workspaces' => [
        WorkspaceInfo(id: 1, name: 'Recovered workspace', role: 'owner'),
      ],
      'builder.platform' => PlatformInfo(
        aiAvailable: aiAvailable,
        aiMode: aiAvailable
            ? 'Live AI'
            : 'Template mode — AI provider not configured',
        development: true,
        actorId: 'test-actor',
      ),
      'apps.list' => <AppManifest>[],
      'apps.templates' => <TemplateInfo>[],
      'runtime.inbox' => <InboxItem>[],
      _ => throw StateError('Unexpected endpoint: $endpoint.$method'),
    } as T;
  }
}

void main() {
  final testClient = TestClient();
  setUpAll(() => transport.client = testClient);
  tearDownAll(testClient.close);
  setUp(() {
    testClient.failure = null;
    testClient.pending = null;
    testClient.workspaceRequests = 0;
    testClient.aiAvailable = false;
    testClient.methods.clear();
  });

  Future<void> home(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('configured AI keeps creation controls without a Live AI label', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    expect(find.text('Live AI'), findsNothing);
    expect(find.textContaining('Template mode'), findsNothing);
    expect(find.text('Describe an app…'), findsOneWidget);
    expect(find.text('Create preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured AI still explains template mode', (tester) async {
    await home(tester);
    expect(
      find.text('Template mode — AI provider not configured'),
      findsOneWidget,
    );
    expect(find.text('Live AI'), findsNothing);
    expect(find.text('Create preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'network failure retries reads and replaces error with workspace',
    (
      tester,
    ) async {
      testClient.failure = const ServerpodClientNetworkException(
        'Unknown server response code. private diagnostic',
      );
      await home(tester);
      expect(find.text('Can’t connect to AppNest'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(find.textContaining('Unknown server response'), findsNothing);

      testClient.failure = null;
      testClient.pending = Completer<void>();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('Connecting to AppNest…'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(testClient.workspaceRequests, 2);
      testClient.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Recovered workspace'), findsOneWidget);
      expect(find.text('A little app. A lot together.'), findsOneWidget);
      expect(find.byType(HomeLoadFailure), findsNothing);
      expect(testClient.methods, [
        'apps.workspaces',
        'apps.workspaces',
        'builder.platform',
        'apps.list',
        'apps.templates',
        'runtime.inbox',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed launcher recovers when returning to the app', (
    tester,
  ) async {
    testClient.failure = const ServerpodClientNetworkException('offline');
    await home(tester);
    testClient.failure = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(testClient.workspaceRequests, 2);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(HomeLoadFailure), findsNothing);
    expect(find.text('Recovered workspace'), findsOneWidget);
    expect(testClient.workspaceRequests, 2);
  });

  testWidgets('disposing during a retry ignores its late response', (
    tester,
  ) async {
    testClient.failure = const ServerpodClientNetworkException('offline');
    await home(tester);
    testClient.failure = null;
    testClient.pending = Completer<void>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    testClient.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(testClient.methods, isNot(contains('apps.list')));
  });

  testWidgets('permission errors are not mislabeled as connection failures', (
    tester,
  ) async {
    testClient.failure = NestError(
      category: 'forbidden',
      message: 'Private server detail',
    );
    await home(tester);
    expect(find.text('Workspace access changed'), findsOneWidget);
    expect(find.text('Can’t connect to AppNest'), findsNothing);
    expect(find.textContaining('Private server detail'), findsNothing);
  });

  testWidgets('unauthorized and unknown failures have safe recovery copy', (
    tester,
  ) async {
    testClient.failure = ServerpodClientUnauthorized();
    await home(tester);
    expect(find.text('Please sign in again'), findsOneWidget);
    testClient.failure = StateError('Private implementation detail');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load your workspace'), findsOneWidget);
    expect(find.textContaining('Private implementation'), findsNothing);
  });

  testWidgets('error and keyboard retry fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: HomeLoadFailure(
              error: TimeoutException('private URL'),
              onRetry: () => retries++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Can’t connect to AppNest'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Focus the sole action and activate it through the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(retries, 1);
  });
}
