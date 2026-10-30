import 'dart:convert';

import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

class _PlatformPod implements Serverpod {
  @override
  final config = ServerpodConfig.defaultConfig();

  @override
  String get runMode => config.runMode;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _PlatformSession implements Session {
  @override
  final Map<String, String> passwords;
  final logs = <String>[];

  _PlatformSession(this.passwords);

  @override
  final Serverpod serverpod = _PlatformPod();

  @override
  final authenticated = AuthenticationInfo(
    'diagnostic-test-actor',
    {},
    authId: 'diagnostic-test-auth',
  );

  @override
  void log(
    String message, {
    LogLevel? level,
    dynamic exception,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) => logs.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> _diagnostic(_PlatformSession session) {
  const prefix = 'ai_configuration ';
  expect(session.logs, hasLength(1));
  expect(session.logs.single, startsWith(prefix));
  final result = jsonDecode(
    session.logs.single.substring(prefix.length),
  ) as Map<String, dynamic>;
  expect(result.values, everyElement(isA<bool>()));
  return result;
}

void main() {
  test('missing provider fields log only presence booleans', () {
    final session = _PlatformSession({});
    final platform = Builder.platform(session);

    expect(platform.aiAvailable, isFalse);
    expect(platform.aiMode, 'Template mode — AI provider not configured');
    expect(_diagnostic(session), {
      'basePresent': false,
      'modelPresent': false,
      'baseValid': false,
      'nvidiaHost': false,
      'nvidiaBase': false,
      'modelSupported': false,
      'selectedKeyPresent': false,
      'providerConfigured': false,
    });
  });

  test(
    'NVIDIA diagnosis identifies missing dedicated key without disclosure',
    () {
      const foreignKey = 'synthetic-foreign-provider-secret';
      final session = _PlatformSession({
        'AI_BASE_URL': 'https://integrate.api.nvidia.com/v1',
        'AI_MODEL': 'z-ai/glm-5.3-flash',
        'AI_API_KEY': foreignKey,
      });
      Builder.platform(session);

      expect(_diagnostic(session), {
        'basePresent': true,
        'modelPresent': true,
        'baseValid': true,
        'nvidiaHost': true,
        'nvidiaBase': true,
        'modelSupported': true,
        'selectedKeyPresent': false,
        'providerConfigured': false,
      });
      for (final suppliedValue in session.passwords.values) {
        expect(session.logs.single, isNot(contains(suppliedValue)));
      }
    },
  );

  test(
    'unsupported configuration never logs supplied values or credentials',
    () {
      final session = _PlatformSession({
        'AI_BASE_URL':
            'https://integrate.api.nvidia.com/private-synthetic-path',
        'AI_MODEL': 'private-synthetic-model',
        'NVIDIA_API_KEY': 'synthetic-dedicated-secret',
      });
      Builder.platform(session);

      final diagnostic = _diagnostic(session);
      expect(diagnostic['baseValid'], isTrue);
      expect(diagnostic['nvidiaBase'], isFalse);
      expect(diagnostic['modelSupported'], isFalse);
      expect(diagnostic['selectedKeyPresent'], isTrue);
      for (final suppliedValue in session.passwords.values) {
        expect(session.logs.single, isNot(contains(suppliedValue)));
      }
    },
  );

  test('valid NVIDIA configuration remains live and emits no diagnostic', () {
    final session = _PlatformSession({
      'AI_BASE_URL': 'https://integrate.api.nvidia.com/v1',
      'AI_MODEL': 'z-ai/glm-5.3-flash',
      'NVIDIA_API_KEY': 'synthetic-dedicated-secret',
    });

    final platform = Builder.platform(session);

    expect(platform.aiAvailable, isTrue);
    expect(platform.aiMode, 'Live AI');
    expect(session.logs, isEmpty);
  });
}
