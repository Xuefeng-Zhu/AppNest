import 'dart:convert';

/// Default/application NVIDIA selection remains the previously evaluated set.
const nvidiaNemotronModels = <String>[
  'nvidia/nemotron-3.5-lightning-30b-a3b',
  'nvidia/nemotron-3-super-120b-a12b',
  'nvidia/nemotron-3-ultra-550b-a55b',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
];

/// Additional exact IDs require explicit benchmark selection via --models.
const nvidiaComparisonModels = <String>[
  'moonshotai/kimi-k3',
  'z-ai/glm-5.3',
  'deepseek-ai/deepseek-v4.1-flash',
];

const nvidiaEvaluationModels = <String>[
  ...nvidiaNemotronModels,
  ...nvidiaComparisonModels,
];

/// Fixed, reviewed transport parameters and their primary-source provenance.
/// This registry does not establish free availability or credential access:
/// those are checked separately immediately before completion dispatch.
class NvidiaEvaluationProfile {
  final String model, family, catalogPath, name, reasoning;
  final Map<String, dynamic> requestOverrides;
  final List<String> documentationUrls;
  final Map<String, String> parameterSources;
  final List<String> limitations;

  const NvidiaEvaluationProfile({
    required this.model,
    required this.family,
    required this.catalogPath,
    required this.name,
    required this.reasoning,
    required this.requestOverrides,
    required this.documentationUrls,
    required this.parameterSources,
    this.limitations = const [],
  });

  String get catalogUrl => 'https://build.nvidia.com/$catalogPath';

  Map<String, dynamic> transportOverrides() =>
      jsonDecode(jsonEncode(requestOverrides)) as Map<String, dynamic>;

  Map<String, dynamic> toJson() => {
    'profile': name,
    'family': family,
    'catalogUrl': catalogUrl,
    'reasoning': reasoning,
    'requestOverrides': transportOverrides(),
    'responseContract': 'complete JSON schema supplied as instructions',
    'generationDeadlineSeconds': 90,
    'guidanceDeadlineSeconds': 20,
    'generationMaxTokens': {
      'initial': 8000,
      'recognizedCreationTruncation': 12000,
    },
    'guidanceMaxTokens': 2048,
    'topP': 'model default; omitted',
    'documentationUrls': documentationUrls.toList(),
    'parameterSources': Map<String, String>.from(parameterSources),
    'limitations': limitations.toList(),
  };
}

NvidiaEvaluationProfile nvidiaEvaluationProfile(String model) {
  if (nvidiaNemotronModels.contains(model)) {
    return NvidiaEvaluationProfile(
      model: model,
      family: 'Nemotron',
      catalogPath: model,
      name: 'nvidia-instruction-schema-thinking-off-v1',
      reasoning: 'thinking disabled',
      requestOverrides: const {
        'stream': false,
        'chat_template_kwargs': {'enable_thinking': false},
      },
      documentationUrls: ['https://build.nvidia.com/$model/modelcard'],
      parameterSources: {
        'chat_template_kwargs.enable_thinking':
            'https://build.nvidia.com/$model/modelcard',
        'stream': 'https://build.nvidia.com/$model',
      },
    );
  }
  return switch (model) {
    'moonshotai/kimi-k3' => const NvidiaEvaluationProfile(
      model: 'moonshotai/kimi-k3',
      family: 'Kimi',
      catalogPath: 'moonshotai/kimi-k3',
      name: 'nvidia-kimi-k3-instruction-schema-low-v1',
      reasoning: 'always enabled; low effort requested',
      requestOverrides: {
        'stream': false,
        'temperature': 0,
        'reasoning_effort': 'low',
      },
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3',
        'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
        'reasoning_effort': 'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
      },
      limitations: [
        'Bounded AppNest feasibility profile; thinking cannot be disabled.',
        'Temperature 0 is supported; NVIDIA recommends 1.0. Low effort and '
            'the shared token/deadline limits do not measure maximal capability.',
      ],
    ),
    'z-ai/glm-5.3' => const NvidiaEvaluationProfile(
      model: 'z-ai/glm-5.3',
      family: 'GLM',
      catalogPath: 'z-ai/glm-5-3',
      name: 'nvidia-glm-5.3-instruction-schema-low-v1',
      reasoning: 'enabled; low effort requested; previous thinking cleared',
      requestOverrides: {
        'stream': false,
        'temperature': 0,
        'reasoning_effort': 'low',
        'chat_template_kwargs': {'clear_thinking': true},
      },
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3',
        'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer',
        'https://recipes.vllm.ai/zai-org/GLM-5.3',
      ],
      parameterSources: {
        'stream':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer',
        'temperature':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer',
        'reasoning_effort':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3',
        'reasoning_effort.location': 'https://recipes.vllm.ai/zai-org/GLM-5.3',
        'chat_template_kwargs.clear_thinking':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3',
      },
      limitations: [
        'Bounded AppNest feasibility profile; no unsupported thinking-off '
            'switch is sent.',
        'Temperature 0 is supported; the endpoint default is 0.5. Low effort '
            'and shared token/deadline limits do not measure maximal capability.',
      ],
    ),
    'deepseek-ai/deepseek-v4.1-flash' => const NvidiaEvaluationProfile(
      model: 'deepseek-ai/deepseek-v4.1-flash',
      family: 'DeepSeek',
      catalogPath: 'deepseek-ai/deepseek-v4.1-flash',
      name: 'nvidia-deepseek-v4.1-flash-instruction-schema-default-v1',
      reasoning: 'model default; no documented NVIDIA HTTP override sent',
      requestOverrides: {'stream': false, 'temperature': 0},
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer',
        'https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash/modelcard',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer',
      },
      limitations: [
        'Bounded AppNest feasibility profile; source-model numeric reasoning '
            'controls are not assumed to be NVIDIA HTTP parameters.',
        'Temperature 0 is supported; NVIDIA recommends 1.0. Shared 8000/12000 '
            'generation tokens and 90-second deadline are below publisher '
            'recommendations and do not measure maximal capability.',
      ],
    ),
    _ => throw ArgumentError.value(model, 'model', 'Unknown NVIDIA profile'),
  };
}
