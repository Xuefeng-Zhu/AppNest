import 'dart:async';
import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';

class AiResult {
  final String text, provider, model;
  final Map<String, dynamic> usage;
  AiResult(this.text, this.provider, this.model, this.usage);
}

/// Safe, actionable diagnostics: never includes provider response bodies.
class AiResponseException implements Exception {
  final String kind, message;
  const AiResponseException(this.kind, this.message);
}

/// Only an optional single outer JSON fence is tolerated; prose and arbitrary
/// embedded JSON are not extracted or interpreted.
Map<String, dynamic> parseAiOutput(String text) {
  if (utf8.encode(text).length > Limits.definitionBytes) {
    throw const AiResponseException(
      'output_size',
      'Generated definition is too large. Return a smaller complete definition.',
    );
  }
  var source = text.trim();
  final fence = RegExp(
    r'^```json\s*\r?\n([\s\S]*?)\r?\n```$',
    caseSensitive: false,
  );
  final match = fence.firstMatch(source);
  if (match != null && !match.group(1)!.contains('```')) {
    source = match.group(1)!;
  }
  try {
    final value = jsonDecode(source);
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    throw const AiResponseException(
      'output_json',
      'The AI response was not valid JSON. Return exactly one complete JSON object without commentary or markdown.',
    );
  }
  throw const AiResponseException(
    'output_shape',
    'The AI response must be a JSON object, not a list or scalar.',
  );
}

Map<String, dynamic> buildAiRequest(
  String model,
  String request,
  AppSpec current, {
  required bool editing,
  List<String> diagnostics = const [],
}) => {
  'model': model,
  'max_tokens': 8000,
  'messages': [
    {
      'role': 'system',
      'content':
          'You propose AppNest declarative definitions. Return exactly one complete JSON object, without markdown or commentary. Never code, SQL, credentials, tenant IDs, URLs or live grants. '
          'Supported capabilities for requires: ${capabilities.join(', ')}. Use only these exact strings in requires. Policy preset names such as personalTracker.v1 belong only in policyPresetRequest; they are not capabilities. '
          'Action ids are app-defined stable identifiers; each action has a supported capability. view.actionIds and page.primaryActionId reference action ids, not capability names. '
          'Build personal mini-app experiences with bounded pages and tabs when requested. Page sections are root views referenced by navigation.pages[].viewIds; do not invent sections or widget trees. Tabs reference existing page ids. Each details or form view must be the sole view of a dedicated non-tab page. '
          'For each editable collection, define both a records.create.v1 action and a records.patch.v1 action. EVERY form view must include the create action id in actionIds, even an editing form; editable forms must include BOTH create and patch action ids. Use one shared form page for adding and editing. Its fieldIds must include all required fields except workflow-managed status. Lists reference the details page through detailPageId and the form page through formPageId. A details view with a patch action must also set formPageId to the shared form page. Source views and destination forms must support the same create/patch capabilities for that collection. page.primaryActionId may only reference a create action exposed by a view on that page which has a formPageId (or is the form itself). '
          'Make adding records reachable from the entry page or a tab: set that page.primaryActionId to the create action id and include that id in its list view.actionIds, with formPageId pointing to the form. Do not place the only create control on a hidden form page. To allow editing, include the patch action id in BOTH the details and form actionIds and set details.formPageId. Define exactly one workflow.transition.v1 action per behavior; the renderer determines valid target options from the current state, so do not create separate target-specific workflow actions. '
          'Workflow actions must bind behaviorId to a workflow.v1 behavior in their collection; that behavior binds fieldId to a choice field and defines transitions using only its choices, for example {"Open":["Done"],"Done":["Open"]}. Record create/patch actions must omit behaviorId. Only use workflow actions for status changes. filterFieldIds must reference choice fields; search titleFieldId must be text. Relative dateFilter binds a timestamp field and uses today or overdue. A grouped summary must groupByFieldId a choice field. '
          'requires must include collections.v1, navigation.v1 when pages are used, views.<type>.v1 for each view type, views.configured.v1 when configuring views, each action capability, and each behavior type. Use only schema enum values for theme, icon and tab icons. '
          'Daily Planner uses independent optional dueAt and reminderAt timestamps, Open/Done workflow, local-day queries and database-wide grouped summaries. notifyOwner is for personalTracker.v1 only; use a condition on status equal to Open. Reminder requests require explicit publication approval and never opt the user in automatically. '
          'If unsupported return {"unsupported":"plain explanation"}. Use diagnostics to correct the entire response on a retry. '
          '${editing ? 'For edits return {"patches":[...]}; allowed semantic patches: RenameLabel(type,targetId,label), AddField(type,collectionId,field:{label,type,required:false,choices?}), AddChoice(type,collectionId,fieldId,choice), AddView(type,view), UpdateView(type,viewId,view), ReorderView(type,viewIds), AddPage(type,page,newViews?,tab?), UpdatePage(type,pageId,page), ReorderPages(type,pageIds), SetNavigation(type,entryPageId,tabs), SetTheme(type,theme,icon?), ProposeReminder(type,rule:{trigger,effect,condition?}). To add a reachable page in one edit, AddPage may supply newViews (view definitions without IDs) and tab:{label,icon}; the server allocates and binds their IDs atomically. page.viewIds may reference existing views; new view IDs are appended automatically. View and page payloads follow the AppSpec schema, omitting id; navigation tabs reference existing page IDs. Never supply new stable IDs; the server allocates them. Preserve existing IDs when referencing records, collections, fields, actions, views, or pages. For a multi-patch edit, use only IDs already present in currentDefinition.' : 'Create the requested app from scratch. Return a complete AppSpec matching the schema with app-defined stable IDs and consistent references.'} '
          '${editing ? 'Exact rename JSON example: {"patches":[{"type":"RenameLabel","targetId":"app","label":"New app name"}]}. To rename a page title, use the same RenameLabel operation with targetId equal to that existing page id. The type value is case-sensitive. A rename patch has exactly type, targetId, and label; never targetType, op, path, or a different type. Page titles and tab labels are separate: change a tab label using {"type":"SetNavigation","entryPageId":"EXISTING_ENTRY_PAGE_ID","tabs":[{"pageId":"EXISTING_PAGE_ID","label":"New tab label","icon":"list"}]} within patches, substituting existing IDs and preserving EVERY current tab and its icon unless asked to change them.' : ''} '
          'AppSpec schema: ${jsonEncode(appSpecSchema())}',
    },
    {
      'role': 'user',
      'content': jsonEncode({
        'request': request,
        if (editing) 'currentDefinition': current.toJson(),
        'diagnostics': diagnostics,
      }),
    },
  ],
};

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
  final http.Client Function() _clientFactory;
  final void Function(String)? log;
  ChatCompletionProvider(
    this.base,
    this.model,
    this.key, {
    http.Client Function()? clientFactory,
    this.log,
  }) : _clientFactory = clientFactory ?? http.Client.new;
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
    return ChatCompletionProvider(
      uri,
      model,
      key,
      log: (message) => s.log(message),
    );
  }

  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
  }) async {
    final client = _clientFactory();
    final elapsed = Stopwatch()..start();
    int? status;
    String finishReason = 'unknown';
    String outcome = 'transport_error';
    int? contentCharacters, completionTokens, reasoningTokens;
    try {
      final endpoint = Uri.parse(
        '${base.toString().replaceFirst(RegExp(r'/$'), '')}/chat/completions',
      );
      final message = http.Request('POST', endpoint)
        ..headers.addAll({
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode(
          buildAiRequest(
            model,
            request,
            current,
            editing: editing,
            diagnostics: diagnostics,
          ),
        );
      // Bound both total duration and bytes while receiving, not after buffering.
      final response = await client
          .send(message)
          .timeout(const Duration(seconds: 45));
      status = response.statusCode;
      if (response.statusCode != 200) {
        throw AiResponseException(
          'http_error',
          'AI provider could not complete the request (HTTP ${response.statusCode}).',
        );
      }
      final bytes = <int>[];
      await (() async {
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > Limits.definitionBytes * 3) {
            throw const AiResponseException(
              'response_size',
              'AI response exceeded the size limit. Return a smaller complete definition.',
            );
          }
          bytes.addAll(chunk);
        }
      })().timeout(
        Duration(
          milliseconds: 45000 - elapsed.elapsedMilliseconds.clamp(0, 44999),
        ),
      );
      final dynamic json;
      try {
        json = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        throw const AiResponseException(
          'envelope_json',
          'The AI provider returned an invalid JSON response envelope.',
        );
      }
      final choices = json is Map ? json['choices'] : null;
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        throw const AiResponseException(
          'envelope_shape',
          'The AI provider response did not contain a completion.',
        );
      }
      final choice = choices.first as Map;
      final reason = choice['finish_reason'];
      if ({
        'stop',
        'length',
        'content_filter',
        'tool_calls',
        'function_call',
      }.contains(reason)) {
        finishReason = reason as String;
      }
      final usage = json['usage'] is Map<String, dynamic>
          ? json['usage'] as Map<String, dynamic>
          : <String, dynamic>{};
      completionTokens = usage['completion_tokens'] is int
          ? usage['completion_tokens'] as int
          : null;
      final details = usage['completion_tokens_details'];
      reasoningTokens = details is Map && details['reasoning_tokens'] is int
          ? details['reasoning_tokens'] as int
          : null;
      final text = choice['message'] is Map
          ? choice['message']['content']
          : null;
      if (text is String) contentCharacters = text.length;
      if (reason == 'length') {
        throw const AiResponseException(
          'truncated',
          'AI output reached the token limit before finishing. Return a smaller complete JSON definition within 8000 tokens.',
        );
      }
      if (reason == 'content_filter' ||
          reason == 'tool_calls' ||
          reason == 'function_call') {
        throw const AiResponseException(
          'completion_stopped',
          'The AI provider did not finish a JSON completion. Return the supported declarative JSON object directly.',
        );
      }
      if (text is! String || text.trim().isEmpty) {
        throw const AiResponseException(
          'content_missing',
          'The AI provider returned no text completion. Return exactly one complete JSON object.',
        );
      }
      outcome = 'received';
      return AiResult(
        text,
        base.host,
        model,
        usage,
      );
    } on TimeoutException {
      outcome = 'timeout';
      throw const AiResponseException(
        'timeout',
        'The AI provider exceeded the 45-second response limit. Return a smaller complete definition.',
      );
    } on AiResponseException catch (e) {
      outcome = e.kind;
      rethrow;
    } on http.ClientException {
      outcome = 'transport_error';
      throw const AiResponseException(
        'transport_error',
        'Could not receive a response from the AI provider.',
      );
    } finally {
      client.close();
      log?.call(
        'generation_provider outcome=$outcome http_status=${status ?? 'none'} finish_reason=$finishReason duration_ms=${elapsed.elapsedMilliseconds} content_chars=${contentCharacters ?? 0} completion_tokens=${completionTokens ?? 0} reasoning_tokens=${reasoningTokens ?? 0}',
      );
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
