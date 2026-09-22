import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';

import '../runtime/access.dart';

class AiResult {
  final String text, provider, model;
  final Map<String, dynamic> usage;
  AiResult(this.text, this.provider, this.model, this.usage);
}

abstract interface class AiProvider {
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
  });
}

class ChatCompletionProvider implements AiProvider {
  final Uri base;
  final String model, key;
  ChatCompletionProvider(this.base, this.model, this.key);
  static ChatCompletionProvider? configured(Session s) {
    final base = s.passwords['AI_BASE_URL'],
        model = s.passwords['AI_MODEL'],
        key = s.passwords['AI_API_KEY'];
    if (base == null ||
        model == null ||
        key == null ||
        [base, model, key].any((x) => x.trim().isEmpty)) {
      return null;
    }
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return ChatCompletionProvider(uri, model, key);
  }

  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
  }) async {
    final client = http.Client();
    final elapsed = Stopwatch()..start();
    try {
      final endpoint = Uri.parse(
        '${base.toString().replaceFirst(RegExp(r'/$'), '')}/chat/completions',
      );
      final message = http.Request('POST', endpoint)
        ..headers.addAll({
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'model': model,
          'max_tokens': 8000,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You propose AppNest declarative definitions. Return only JSON. Never code, SQL, credentials, tenant IDs, URLs or live grants. Supported capabilities: ${capabilities.join(', ')}. If unsupported return {"unsupported":"plain explanation"}. ${editing ? 'For edits return {"patches":[...]}; allowed semantic patches: RenameLabel(type,targetId,label), AddField(type,collectionId,field:{label,type,required:false,choices?}), AddChoice(type,collectionId,fieldId,choice), AddView(type,view:{type,collectionId,label,titleFieldId?,groupByFieldId?,actionIds}), ReorderView(type,viewIds), ProposeReminder(type,rule:{trigger,effect}). Never supply new stable IDs; server allocates them.' : 'Return a complete AppSpec matching this schema: ${jsonEncode(appSpecSchema())}'}',
            },
            {
              'role': 'user',
              'content': jsonEncode({
                'request': request,
                'currentDefinition': current.toJson(),
                'templates': starterTemplates().values
                    .map((t) => t.toJson())
                    .toList(),
                'diagnostics': diagnostics,
              }),
            },
          ],
        });
      // Bound both total duration and bytes while receiving, not after buffering.
      final response = await client
          .send(message)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        fail(
          'providerUnavailable',
          'AI provider could not complete the request (HTTP ${response.statusCode}).',
        );
      }
      final bytes = <int>[];
      await (() async {
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > Limits.definitionBytes * 3) {
            fail('invalidInput', 'AI response exceeded the size limit.');
          }
          bytes.addAll(chunk);
        }
      })().timeout(
        Duration(
          milliseconds: 45000 - elapsed.elapsedMilliseconds.clamp(0, 44999),
        ),
      );
      final json = payload(jsonDecode(utf8.decode(bytes)));
      final text = json['choices'][0]['message']['content'];
      if (text is! String) {
        fail('invalidInput', 'AI returned an unsupported response format.');
      }
      return AiResult(
        text,
        base.host,
        model,
        json['usage'] is Map ? payload(json['usage']) : {},
      );
    } finally {
      client.close();
    }
  }
}

class FakeAiProvider implements AiProvider {
  final String output;
  FakeAiProvider(this.output);
  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
  }) async => AiResult(output, 'fake-test-only', 'deterministic', {});
}
