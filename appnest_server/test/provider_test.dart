import 'dart:async';
import 'dart:convert';

import 'package:appnest_server/src/generated/guidance_question.dart';
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
    'guidance assesses with only idea and optional declarative definition',
    () {
      for (final definition in <AppSpec?>[null, current]) {
        final body = buildGuidanceRequest(
          'test-model',
          'A small library',
          definition: definition,
        );
        expect(body['max_tokens'], 2048);
        final messages = body['messages'] as List;
        expect(messages.first['content'], contains('needsClarification'));
        expect(messages.first['content'], contains('current definition'));
        expect(messages.first['content'], contains('options'));
        final user = jsonDecode(messages.last['content'] as String) as Map;
        expect(
          user.keys,
          unorderedEquals([
            'idea',
            if (definition != null) 'currentDefinition',
          ]),
        );
        expect(user['idea'], 'A small library');
        if (definition != null) {
          expect(user['currentDefinition'], current.toJson());
        }
        expect(
          messages.last['content'],
          isNot(contains('private record text')),
        );
      }
    },
  );

  test('guidance accepts clear decisions or focused selectable options', () {
    const q1 = {
      'question': 'Who will use this app?',
      'options': ['Club members', 'Organizers', 'Both groups'],
    };
    const q2 = {
      'question': 'What should they track?',
      'options': ['Events', 'Membership', 'Shared tasks'],
    };
    final valid = jsonEncode({
      'needsClarification': true,
      'questions': [q1, q2],
    });
    final parsed = parseGuidanceOutput(valid);
    expect(parsed.map((q) => q.question), [
      'Who will use this app?',
      'What should they track?',
    ]);
    expect(parsed.first.options, ['Club members', 'Organizers', 'Both groups']);
    expect(
      parseGuidanceOutput('```json\n$valid\n```').last.options,
      ['Events', 'Membership', 'Shared tasks'],
    );
    expect(
      parseGuidanceOutput(
        jsonEncode({
          'needsClarification': true,
          'questions': [
            q1,
            q2,
            {
              'question': 'How should members collaborate?',
              'options': [
                'Shared calendar',
                'Task assignments',
                'Discussion posts',
                'No collaboration',
              ],
            },
          ],
        }),
      ).last.options,
      hasLength(4),
    );
    expect(
      parseGuidanceOutput('{"needsClarification":false,"questions":[]}'),
      isEmpty,
    );
    expect(
      parseGuidanceOutput(
        '```json\n{"needsClarification":false,"questions":[]}\n```',
      ),
      isEmpty,
    );
    for (final response in [
      'Not JSON',
      'Here are questions: $valid',
      '```json\n```json\n$valid\n```\n```',
      '["Who will use it?","What should they track?"]',
      '{"questions":[]}',
      '{"needsClarification":true,"questions":[]}',
      jsonEncode({
        'needsClarification': false,
        'questions': [q1],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [q1],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [q1, q1],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [q1, q2, q1, q2],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {...q1, 'question': 'WHO WILL USE THIS APP?'},
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [q1, q2],
        'extra': 1,
      }),
      jsonEncode({
        'needsClarification': 'true',
        'questions': [q1, q2],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {...q2, 'question': 'No question mark'},
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {...q2, 'question': 'What\nshould they track?'},
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {...q2, 'question': 'X' * 121},
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', 'Membership'],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': [
              'Events',
              'Membership',
              'Shared tasks',
              'Another',
              'Extra',
            ],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', 'EVENTS', 'Shared tasks'],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', 'Events ', 'Shared tasks'],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', 4, 'Shared tasks'],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', '', 'Shared tasks'],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', 'Membership', 'Shared\ntasks'],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {
            ...q2,
            'options': ['Events', 'Membership', 'X' * 81],
          },
        ],
      }),
      jsonEncode({
        'needsClarification': true,
        'questions': [
          q1,
          {...q2, 'extra': 'invalid'},
        ],
      }),
      ' ' * 4097,
    ]) {
      expect(
        () => parseGuidanceOutput(response),
        throwsA(isA<AiResponseException>()),
      );
    }
  });

  test('guidance transport logs metadata only and bounds completion', () async {
    final logs = <String>[];
    Future<List<GuidanceQuestion>> ask(
      Object? completion, {
      String finishReason = 'stop',
      Map<String, dynamic> usage = const {},
    }) => ChatCompletionProvider(
      Uri.parse('https://example.test/v1'),
      'test-model',
      'private-key',
      log: logs.add,
      clientFactory: () => MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer private-key');
        expect(request.body, contains('private-idea'));
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': finishReason,
                'message': {'content': completion},
              },
            ],
            'usage': usage,
          }),
          200,
        );
      }),
    ).suggestQuestions('private-idea');

    const valid =
        '{"needsClarification":true,"questions":[{"question":"Who will use it?","options":["Members","Organizers","Both groups"]},{"question":"What should it track?","options":["Events","Membership","Shared tasks"]}]}';
    final result = await ask(valid);
    expect(result.map((q) => q.question), [
      'Who will use it?',
      'What should it track?',
    ]);
    expect(result.first.options, ['Members', 'Organizers', 'Both groups']);
    expect(logs.single, contains('guidance_provider outcome=received'));
    expect(logs.single, contains('content_format=object_candidate'));
    for (final secret in ['private-key', 'private-idea', 'Who will use it?']) {
      expect(logs.single, isNot(contains(secret)));
    }
    expect(
      await ask('{"needsClarification":false,"questions":[]}'),
      isEmpty,
    );
    expect(logs.last, contains('guidance_provider outcome=received'));
    await expectLater(
      ask('{"needsClarification":true,"questions":[]}'),
      throwsA(failure('guidance_shape')),
    );
    expect(logs.last, contains('outcome=guidance_shape'));
    expect(
      (await ask('```json\n$valid\n```')).length,
      2,
    );
    expect(logs.last, contains('content_format=fence_candidate'));
    await expectLater(
      ask(
        null,
        finishReason: 'length',
        usage: {
          'completion_tokens': 2048,
          'completion_tokens_details': {'reasoning_tokens': 2048},
        },
      ),
      throwsA(failure('guidance_truncated')),
    );
    expect(logs.last, contains('outcome=guidance_truncated'));
    expect(logs.last, contains('finish_reason=length'));
    expect(logs.last, contains('content_chars=0'));
    expect(
      logs.last,
      contains('completion_tokens=2048 reasoning_tokens=2048'),
    );
    await expectLater(
      ask(null, finishReason: 'content_filter'),
      throwsA(failure('guidance_completion')),
    );
    expect(logs.last, contains('finish_reason=content_filter'));
    for (final log in logs) {
      for (final secret in [
        'private-key',
        'private-idea',
        'Who will use it?',
      ]) {
        expect(log, isNot(contains(secret)));
      }
    }
  });

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
