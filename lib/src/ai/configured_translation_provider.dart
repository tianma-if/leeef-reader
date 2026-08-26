import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:leeef_reader/src/ai/llm_translation_provider.dart';
import 'package:leeef_reader/src/ai/llm_assistant_provider.dart';
import 'package:leeef_reader/src/ai/persistent_translation_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const aiBaseUrlPreferenceKey = 'leeef.ai.base_url';
const aiModelPreferenceKey = 'leeef.ai.model';
const aiPromptPreferenceKey = 'leeef.ai.translation_prompt';
const aiAssistantPromptPreferenceKey = 'leeef.ai.assistant_prompt';
const aiProviderPreferenceKey = 'leeef.ai.provider';
const aiReasoningEffortPreferenceKey = 'leeef.ai.reasoning_effort';
const aiLibraryToolPreferenceKey = 'leeef.ai.tools.library';
const aiNotesToolPreferenceKey = 'leeef.ai.tools.notes';
const aiHistoryToolPreferenceKey = 'leeef.ai.tools.history';
const aiWriteToolsPreferenceKey = 'leeef.ai.tools.write';
const aiApiKeySecureKey = 'leeef.ai.api_key';

Future<LlmTranslationProvider> loadConfiguredTranslationProvider() async {
  const secureStorage = FlutterSecureStorage();
  final preferences = await SharedPreferences.getInstance();
  final baseUrl = preferences.getString(aiBaseUrlPreferenceKey);
  final model = preferences.getString(aiModelPreferenceKey);
  final rawKeys = await secureStorage.read(key: aiApiKeySecureKey);
  final apiKeys =
      rawKeys
          ?.split(RegExp(r'[\r\n,]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList() ??
      const <String>[];
  if (baseUrl == null || model == null || apiKeys.isEmpty) {
    throw StateError('请先在设置中配置 AI 翻译模型。');
  }
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw StateError('AI API 地址无效。');
  }
  return LlmTranslationProvider(
    baseUri: uri,
    apiKeys: apiKeys,
    model: model,
    providerKind: AiProviderKind.values.firstWhere(
      (item) => item.name == preferences.getString(aiProviderPreferenceKey),
      orElse: () => AiProviderKind.openAiCompatible,
    ),
    reasoningEffort:
        preferences.getString(aiReasoningEffortPreferenceKey) ?? 'medium',
    cache: const PersistentTranslationCache(),
    systemPrompt:
        preferences.getString(aiPromptPreferenceKey) ??
        '你是电子书阅读器中的翻译助手。结合上下文准确翻译选中文本，保持人名、术语、语气与文体一致；先给译文，再用一句话解释有歧义的词语。不要续写原文。',
  );
}

Future<LlmAssistantProvider> loadConfiguredAssistantProvider() async {
  const secureStorage = FlutterSecureStorage();
  final preferences = await SharedPreferences.getInstance();
  final baseUrl = preferences.getString(aiBaseUrlPreferenceKey);
  final model = preferences.getString(aiModelPreferenceKey);
  final rawKeys = await secureStorage.read(key: aiApiKeySecureKey);
  final keys =
      rawKeys
          ?.split(RegExp(r'[\r\n,]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList() ??
      const <String>[];
  final uri = baseUrl == null ? null : Uri.tryParse(baseUrl);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      model == null ||
      keys.isEmpty) {
    throw StateError('请先在设置中配置 AI 模型和 API Key。');
  }
  return LlmAssistantProvider(
    baseUri: uri,
    apiKeys: keys,
    model: model,
    providerKind: AiProviderKind.values.firstWhere(
      (item) => item.name == preferences.getString(aiProviderPreferenceKey),
      orElse: () => AiProviderKind.openAiCompatible,
    ),
    reasoningEffort:
        preferences.getString(aiReasoningEffortPreferenceKey) ?? 'medium',
  );
}
