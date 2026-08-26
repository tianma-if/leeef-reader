import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:leeef_reader/src/ai/translation_provider.dart';
import 'package:leeef_reader/src/ai/llm_assistant_provider.dart';

class LlmTranslationProvider implements TranslationProvider {
  LlmTranslationProvider({
    required this.baseUri,
    String? apiKey,
    List<String>? apiKeys,
    required this.model,
    this.systemPrompt = _defaultPrompt,
    this.providerKind = AiProviderKind.openAiCompatible,
    this.reasoningEffort = 'medium',
    TranslationCache? cache,
    HttpClient? httpClient,
  }) : assert(apiKey != null || (apiKeys?.isNotEmpty ?? false)),
       apiKeys = List.unmodifiable(apiKeys ?? [?apiKey]),
       _cache = cache ?? MemoryTranslationCache(),
       _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final List<String> apiKeys;
  final String model;
  final String systemPrompt;
  final AiProviderKind providerKind;
  final String reasoningEffort;
  final HttpClient _httpClient;
  final TranslationCache _cache;
  var _keyIndex = 0;

  static const _defaultPrompt =
      '你是电子书阅读器中的翻译助手。结合上下文准确翻译选中文本，保持人名、术语、语气与文体一致；先给译文，再用一句话解释有歧义的词语。不要续写原文。';

  @override
  Future<String> translate(
    TranslationRequest request, {
    TranslationCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final text = request.text.trim();
    if (text.isEmpty) throw ArgumentError('Selected text is empty.');
    final cacheKey =
        '${request.targetLanguage}\u0000${request.context}\u0000$text';
    final cached = await _cache.get(cacheKey);
    if (cached != null) return cached;
    Object? lastError;
    final attempts = apiKeys.length < 2 ? 2 : apiKeys.length;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final key = apiKeys[(_keyIndex + attempt) % apiKeys.length];
      try {
        final result = await _complete(
          request,
          apiKey: key,
          cancellationToken: cancellationToken,
        ).timeout(const Duration(seconds: 45));
        await _cache.put(cacheKey, result);
        _keyIndex = (_keyIndex + attempt + 1) % apiKeys.length;
        return result;
      } on Object catch (error) {
        if (error is TranslationCancelled) rethrow;
        lastError = error;
        if (apiKeys.length == 1 && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
    throw StateError('Translation failed after retry: $lastError');
  }

  Future<void> verifyConnection() async {
    await _complete(
      const TranslationRequest(
        text: 'Hello',
        context: 'Connection test',
        targetLanguage: '简体中文',
      ),
      apiKey: apiKeys[_keyIndex],
    ).timeout(const Duration(seconds: 20));
  }

  Future<String> _complete(
    TranslationRequest request, {
    required String apiKey,
    TranslationCancellationToken? cancellationToken,
  }) async {
    final endpoint = _endpointForProvider(apiKey);
    final httpRequest = await _httpClient.postUrl(endpoint);
    cancellationToken?.whenCancelled.then(
      (_) => httpRequest.abort(const TranslationCancelled()),
    );
    cancellationToken?.throwIfCancelled();
    httpRequest.headers.contentType = ContentType.json;
    final userText =
        '目标语言：${request.targetLanguage}\n\n上下文：\n${_limit(request.context, 6000)}\n\n选中文本：\n${request.text}';
    switch (providerKind) {
      case AiProviderKind.openAiCompatible:
        httpRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $apiKey',
        );
        httpRequest.write(
          jsonEncode({
            'model': model,
            'temperature': 0.2,
            if (reasoningEffort != 'medium')
              'reasoning_effort': reasoningEffort,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userText},
            ],
          }),
        );
      case AiProviderKind.anthropic:
        httpRequest.headers
          ..set('x-api-key', apiKey)
          ..set('anthropic-version', '2023-06-01');
        httpRequest.write(
          jsonEncode({
            'model': model,
            'max_tokens': 4096,
            'system': systemPrompt,
            'messages': [
              {'role': 'user', 'content': userText},
            ],
          }),
        );
      case AiProviderKind.gemini:
        httpRequest.write(
          jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': systemPrompt},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': userText},
                ],
              },
            ],
            'generationConfig': {'temperature': .2},
          }),
        );
    }
    final response = await httpRequest.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'LLM returned HTTP ${response.statusCode}: ${_limit(body, 500)}',
        uri: endpoint,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Invalid LLM response.');
    final content = _responseText(decoded);
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('LLM response content is empty.');
    }
    return content.trim();
  }

  Uri _endpointForProvider(String apiKey) => switch (providerKind) {
    AiProviderKind.openAiCompatible => _chatCompletionsUri(baseUri),
    AiProviderKind.anthropic => _apiPath(baseUri, 'v1/messages'),
    AiProviderKind.gemini => _apiPath(
      baseUri,
      'v1beta/models/${Uri.encodeComponent(model)}:generateContent',
    ).replace(queryParameters: {'key': apiKey}),
  };

  String? _responseText(Map decoded) => switch (providerKind) {
    AiProviderKind.openAiCompatible => switch (decoded['choices']) {
      final List choices when choices.firstOrNull is Map =>
        ((choices.first as Map)['message'] as Map?)?['content'] as String?,
      _ => null,
    },
    AiProviderKind.anthropic => switch (decoded['content']) {
      final List content when content.firstOrNull is Map =>
        (content.first as Map)['text'] as String?,
      _ => null,
    },
    AiProviderKind.gemini => switch (decoded['candidates']) {
      final List candidates when candidates.firstOrNull is Map =>
        ((((candidates.first as Map)['content'] as Map?)?['parts'] as List?)
                    ?.firstOrNull
                as Map?)?['text']
            as String?,
      _ => null,
    },
  };

  static Uri _apiPath(Uri base, String path) {
    final root = base.replace(path: '/', query: null, fragment: null);
    final baseSegments = base.pathSegments.where((item) => item.isNotEmpty);
    final requested = path.split('/');
    if (baseSegments.isNotEmpty && requested.first == baseSegments.first) {
      return root.resolve(path);
    }
    return root.resolve([...baseSegments, ...requested].join('/'));
  }

  static Uri _chatCompletionsUri(Uri base) {
    final normalized = base.path.endsWith('/')
        ? base
        : base.replace(path: '${base.path}/');
    if (normalized.path.endsWith('/chat/completions/')) {
      return normalized.replace(
        path: normalized.path.substring(0, normalized.path.length - 1),
      );
    }
    final includesV1 = normalized.pathSegments.contains('v1');
    return normalized.resolve(
      includesV1 ? 'chat/completions' : 'v1/chat/completions',
    );
  }

  static String _limit(String value, int length) =>
      value.length <= length ? value : value.substring(0, length);

  void close() => _httpClient.close(force: true);
}
