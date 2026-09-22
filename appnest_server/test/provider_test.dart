import 'dart:async';
import 'dart:convert';

import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final current = starterTemplates()['planner']!;
  Matcher failure(String kind) => isA<AiResponseException>().having(
    (e) => e.kind,
    'kind',
    kind,
  );

  test(
    'create sends only the request and diagnostics, edit includes definition',
    () {
      for (final editing in [false, true]) {
        final body = buildAiRequest(
          'test-model',
          'My plant app',
          current,
          editing: editing,
          diagnostics: ['Correct requires'],
        );
        final messages = body['messages'] as List;
        final user = jsonDecode(messages.last['content'] as String) as Map;
        expect(
          user.keys,
          unorderedEquals([
            'request',
            'diagnostics',
            if (editing) 'currentDefinition',
          ]),
        );
        expect(user['diagnostics'], ['Correct requires']);
        expect(messages.first['content'], contains('policyPresetRequest'));
        expect(messages.first['content'], contains('not capability names'));
        expect(messages.first['content'], contains('AppSpec schema:'));
        if (editing) {
          expect(user['currentDefinition'], current.toJson());
          expect(
            messages.first['content'],
            contains(
              '{"type":"RenameLabel","targetId":"app","label":"New app name"}',
            ),
          );
          expect(
            messages.first['content'],
            contains('never targetType, op, path'),
          );
        }
      }
    },
  );

  test('strict JSON and one outer json fence validate identically', () {
    for (final text in [
      current.canonical,
      ' \n```json\n${current.canonical}\n```\n ',
    ]) {
      expect(AppSpec.parse(jsonEncode(parseAiOutput(text))).hash, current.hash);
    }
  });

  test(
    'output parser rejects prose, partial JSON, nested fences and wrong shape',
    () {
      for (final text in [
        'Here is your app: {}',
        '{"title":',
        '```json\n{}\n``` trailing',
        '```json\n{}\n```\n```json\n{}\n```',
        '```javascript\n{}\n```',
      ]) {
        expect(() => parseAiOutput(text), throwsA(failure('output_json')));
      }
      expect(() => parseAiOutput('[]'), throwsA(failure('output_shape')));
    },
  );

  Future<AiResult> respond(
    Object body, {
    int status = 200,
    List<String>? logs,
  }) => ChatCompletionProvider(
    Uri.parse('https://example.test/v1'),
    'test-model',
    'secret-key',
    log: logs?.add,
    clientFactory: () => MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer secret-key');
      expect(
        (jsonDecode(request.body)['messages'] as List).last['content'],
        isNot(contains('currentDefinition')),
      );
      return http.Response(jsonEncode(body), status);
    }),
  ).generate('private-request', current, editing: false);

  Map<String, dynamic> completion(String reason, Object? content) => {
    'choices': [
      {
        'finish_reason': reason,
        'message': {'content': content},
      },
    ],
    'usage': {
      'completion_tokens': 322,
      'completion_tokens_details': {'reasoning_tokens': 174},
    },
  };

  test(
    'transport records safe completion metadata, never content or credentials',
    () async {
      final logs = <String>[];
      final result = await respond(
        completion('stop', 'private-response'),
        logs: logs,
      );
      expect(result.text, 'private-response');
      expect(result.usage['completion_tokens'], 322);
      expect(logs.single, contains('finish_reason=stop'));
      expect(
        logs.single,
        contains('completion_tokens=322 reasoning_tokens=174'),
      );
      expect(logs.single, contains('duration_ms='));
      for (final secret in [
        'secret-key',
        'private-request',
        'private-response',
      ]) {
        expect(logs.single, isNot(contains(secret)));
      }
    },
  );

  test(
    'transport distinguishes truncation, HTTP errors and missing completion',
    () async {
      await expectLater(
        respond(completion('length', '{')),
        throwsA(failure('truncated')),
      );
      await expectLater(
        respond({'private': 'body'}, status: 429),
        throwsA(failure('http_error')),
      );
      await expectLater(
        respond({'choices': []}),
        throwsA(failure('envelope_shape')),
      );
      await expectLater(
        respond(completion('stop', null)),
        throwsA(failure('content_missing')),
      );
      await expectLater(
        respond(completion('content_filter', null)),
        throwsA(failure('completion_stopped')),
      );
    },
  );

  test(
    'transport distinguishes malformed envelope JSON from timeout',
    () async {
      for (final timeout in [false, true]) {
        final provider = ChatCompletionProvider(
          Uri.parse('https://example.test/v1'),
          'model',
          'secret',
          clientFactory: () => MockClient((request) async {
            if (timeout) throw TimeoutException('private transport details');
            return http.Response('not-json-private-body', 200);
          }),
        );
        await expectLater(
          provider.generate('request', current, editing: false),
          throwsA(failure(timeout ? 'timeout' : 'envelope_json')),
        );
      }
    },
  );
}
