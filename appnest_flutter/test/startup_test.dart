import 'dart:async';

import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_flutter/features/mini_app/mini_app_screen.dart';
import 'package:appnest_flutter/main.dart';
import 'package:appnest_flutter/screens/sign_in_screen.dart';
import 'package:appnest_flutter/screens/startup_screen.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import 'draft_navigation_test.dart' show DraftNavigationClient;
import 'mini_app_navigation_test.dart' show TestBrowserHistory;

class _AuthStorage implements ClientAuthSuccessStorage {
  _AuthStorage(this.value);
  AuthSuccess? value;
  int reads = 0;
  int clears = 0;
  Object? readFailure;

  @override
  Future<AuthSuccess?> get() async {
    reads++;
    if (readFailure != null) throw readFailure!;
    return value;
  }

  @override
  Future<void> set(AuthSuccess? data) async {
    if (data == null) clears++;
    value = data;
  }
}

class _StartupClient extends DraftNavigationClient {
  Completer<bool>? pendingValidation;
  Object? validationFailure;
  int validations = 0;
  int refreshes = 0;
  bool sessionAccepted = true;

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    if ('$endpoint.$method' == 'jwtRefresh.refreshAccessToken') {
      refreshes++;
      return _session(jwt: true) as T;
    }
    if ('$endpoint.$method' == 'serverpod_auth_core.status.isSignedIn') {
      validations++;
      if (validationFailure != null) throw validationFailure!;
      return (pendingValidation == null
              ? sessionAccepted
              : await pendingValidation!.future)
          as T;
    }
    if ('$endpoint.$method' == 'serverpod_auth_core.status.signOutDevice') {
      return null as T;
    }
    return super.callServerEndpoint<T>(
      endpoint,
      method,
      args,
      authenticated: authenticated,
    );
  }
}

AuthSuccess _session({bool jwt = false}) => AuthSuccess.fromJson({
  'authStrategy': jwt ? 'jwt' : 'session',
  'token': 'synthetic-test-access',
  if (jwt) 'refreshToken': 'synthetic-test-refresh',
  'authUserId': '11111111-1111-4111-8111-111111111111',
  'scopeNames': <String>[],
});

void main() {
  late _StartupClient client;
  late _AuthStorage storage;
  late transport.ClientInitialization initialization;
  var creations = 0;

  setUpAll(() async {
    // Match the existing auth overlay fixture; Ahem makes compact links wider.
    await (FontLoader(
      'Lora',
    )..addFont(rootBundle.load('assets/fonts/Lora.ttf'))).load();
    client = _StartupClient();
    transport.client = client;
  });

  setUp(() {
    client
      ..preview = PreviewRuntimeAdapter(notesTemplate())
      ..pendingValidation = null
      ..validationFailure = null
      ..validations = 0
      ..refreshes = 0
      ..sessionAccepted = true;
    client.calls.clear();
    client.resumes.clear();
    storage = _AuthStorage(_session());
    client.authSessionManager = FlutterAuthSessionManager(storage: storage);
    creations = 0;
    initialization = transport.ClientInitialization(() async {
      creations++;
      return client.auth;
    });
  });

  tearDown(() => client.preview.dispose());
  tearDownAll(() async {
    client.close();
    await client.events.close();
  });

  Future<void> mount(WidgetTester tester, {Widget? child}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Lora'),
        home: StartupScreen(
          initialize: initialization.initialize,
          child: child ?? const Scaffold(body: Text('Authenticated workspace')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'authenticated validation beyond two seconds keeps a visible app',
    (
      tester,
    ) async {
      client.pendingValidation = Completer<bool>();
      await mount(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Opening AppNest'), findsOneWidget);
      expect(find.text('Checking your session…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Authenticated workspace'), findsNothing);
      expect(find.byType(SignInScreen), findsNothing);
      expect(client.auth.isAuthenticated, isTrue);
      expect(storage.clears, 0);
      expect(tester.takeException(), isNull);

      client.pendingValidation!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Authenticated workspace'), findsOneWidget);
      expect(creations, 1);
      expect(client.validations, 1);
    },
  );

  testWidgets('raw SDK validation timeout is recoverable without losing auth', (
    tester,
  ) async {
    initialization = transport.ClientInitialization(() async {
      creations++;
      return client.auth;
    }, validationTimeout: const Duration(milliseconds: 100));
    client.pendingValidation = Completer<bool>();
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 101));
    expect(find.text('Can’t connect to AppNest'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('saved session has been kept'), findsOneWidget);
    expect(client.auth.isAuthenticated, isTrue);
    expect(storage.value?.authUserId, _session().authUserId);
    expect(storage.clears, 0);
    expect(tester.takeException(), isNull);

    // Future.timeout does not cancel the SDK request. Settle that request before
    // making the explicit retry; its late success must not dismiss recovery.
    client.pendingValidation!.complete(true);
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    client.pendingValidation = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated workspace'), findsOneWidget);
    expect(creations, 1);
    expect(storage.reads, 1);
    expect(client.validations, 2);
    expect(storage.clears, 0);
  });

  testWidgets('JWT network retry reuses transport and restores storage once', (
    tester,
  ) async {
    storage.value = _session(jwt: true);
    client.validationFailure = ServerpodClientNetworkException(
      'private transport diagnostic',
    );
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Can’t connect to AppNest'), findsOneWidget);
    expect(find.textContaining('private transport diagnostic'), findsNothing);
    expect(client.auth.isAuthenticated, isTrue);
    expect(storage.clears, 0);

    client.validationFailure = null;
    client.pendingValidation = Completer<bool>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    // A competing caller observes the same active attempt; no second JWT
    // refresh or validation starts while the retry is still pending.
    final sameAttempt = initialization.initialize();
    expect(client.validations, 2);
    expect(client.refreshes, 2);
    expect(creations, 1);
    expect(find.text('Retry'), findsNothing);
    client.pendingValidation!.complete(true);
    await sameAttempt;
    await tester.pumpAndSettle();
    expect(find.text('Authenticated workspace'), findsOneWidget);
    // One restore plus the SDK's cache refresh for each JWT validation.
    expect(storage.reads, 3);
    expect(storage.clears, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed local restore can retry without recreating transport', (
    tester,
  ) async {
    storage.readFailure = StateError('private setup diagnostic');
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t open AppNest'), findsOneWidget);
    expect(find.textContaining('private setup diagnostic'), findsNothing);
    storage.readFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated workspace'), findsOneWidget);
    expect(creations, 1);
    expect(storage.reads, 2);
    expect(client.validations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first visit renders sign-in without a validation request', (
    tester,
  ) async {
    storage.value = null;
    await mount(
      tester,
      child: const SignInScreen(child: Text('Private app')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignInWidget), findsOneWidget);
    expect(find.text('Opening AppNest'), findsNothing);
    expect(client.validations, 0);
    expect(client.calls, isEmpty);
    expect(creations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a server-rejected session reaches sign-in before private routes',
    (
      tester,
    ) async {
      client.sessionAccepted = false;
      await mount(
        tester,
        child: const SignInScreen(child: Text('Private app')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SignInWidget), findsOneWidget);
      expect(client.auth.isAuthenticated, isFalse);
      expect(storage.clears, 1);
      expect(client.calls, isEmpty);
      expect(find.text('Private app'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final path in ['/apps/1/pages/homePage', '/drafts/1']) {
    testWidgets('startup retry retains the original $path route', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      client.published = path.startsWith('/apps');
      client.pendingValidation = Completer<bool>();
      final history = TestBrowserHistory(Uri.parse(path));
      addTearDown(history.dispose);
      await tester.pumpWidget(
        MyApp(
          initialize: initialization.initialize,
          routeInformationProvider: history,
        ),
      );
      await tester.pump();
      expect(find.text('Opening AppNest'), findsOneWidget);
      expect(history.value.uri.path, path);
      expect(client.calls, isEmpty);
      client.pendingValidation!.completeError(
        TimeoutException('private validation diagnostic'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(history.value.uri.path, path);
      expect(find.byType(SignInScreen), findsNothing);
      expect(storage.clears, 0);

      client.pendingValidation = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(history.value.uri.path, path);
      expect(
        path.startsWith('/apps')
            ? find.byType(MiniAppScreen)
            : find.byType(BuilderScreen),
        findsOneWidget,
      );
      expect(creations, 1);
      expect(client.validations, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
