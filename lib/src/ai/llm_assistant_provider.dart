import 'dart:convert';
import 'dart:io';

enum AiProviderKind { openAiCompatible, anthropic, gemini }

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});
  final String role;
  final String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

class LlmAssistantProvider {
  LlmAssistantProvider({
    required this.baseUri,
    required this.apiKeys,
    required this.model,
    this.providerKind = AiProviderKind.openAiCompatible,
    this.reasoningEffort = 'medium',
    HttpClient? client,
  }) : _client = client ?? HttpClient();
  final Uri baseUri;
  final List<String> apiKeys;
  final String model;
  final AiProviderKind providerKind;
  final String reasoningEffort;
  final HttpClient _client;
  var _keyIndex = 0;

  Future<String> complete({
    required List<AiChatMessage> messages,
    required String context,
    String? systemPrompt,
  }) async {
    if (apiKeys.isEmpty) throw StateError('No AI API key is configured.');
    Object? lastError;
    for (var attempt = 0; attempt < apiKeys.length; attempt++) {
      final key = apiKeys[(_keyIndex + attempt) % apiKeys.length];
      try {
        final endpoint = _endpointFor(key);
        final request = await _client.postUrl(endpoint);
        request.headers.contentType = ContentType.json;
        final effectiveSystem =
            systemPrompt ??
            '你是 Leeef Reader 的阅读助手。基于提供的书籍上下文回答，明确区分原文事实与推断，不编造不存在的引用。';
        switch (providerKind) {
          case AiProviderKind.openAiCompatible:
            request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
            request.write(
              jsonEncode({
                'model': model,
                'temperature': 0.3,
                if (reasoningEffort != 'medium')
                  'reasoning_effort': reasoningEffort,
                'messages': [
                  {'role': 'system', 'content': effectiveSystem},
                  {
                    'role': 'system',
                    'content': '当前上下文：\n${_limit(context, 24000)}',
                  },
                  ...messages.map((item) => item.toJson()),
                ],
              }),
            );
          case AiProviderKind.anthropic:
            request.headers
              ..set('x-api-key', key)
              ..set('anthropic-version', '2023-06-01');
            request.write(
              jsonEncode({
                'model': model,
                'max_tokens': 4096,
                'system':
                    '$effectiveSystem\n\n当前上下文：\n${_limit(context, 24000)}',
                'messages': messages.map((item) => item.toJson()).toList(),
              }),
            );
          case AiProviderKind.gemini:
            request.write(
              jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {
                      'text':
                          '$effectiveSystem\n\n当前上下文：\n${_limit(context, 24000)}',
                    },
                  ],
                },
                'contents': [
                  for (final item in messages)
                    {
                      'role': item.role == 'assistant' ? 'model' : 'user',
                      'parts': [
                        {'text': item.content},
                      ],
                    },
                ],
                'generationConfig': {'temperature': .3},
              }),
            );
        }
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'AI returned HTTP ${response.statusCode}: ${_limit(body, 500)}',
            uri: endpoint,
          );
        }
        final decoded = jsonDecode(body) as Map;
        final text = _responseText(decoded);
        if (text is! String || text.trim().isEmpty) {
          throw const FormatException('AI response is empty.');
        }
        _keyIndex = (_keyIndex + attempt + 1) % apiKeys.length;
        return text.trim();
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw StateError('All configured AI keys failed: $lastError');
  }

  Uri _endpointFor(String key) => switch (providerKind) {
    AiProviderKind.openAiCompatible => _endpoint(baseUri),
    AiProviderKind.anthropic => _resolveApiPath(baseUri, 'v1/messages'),
    AiProviderKind.gemini => _resolveApiPath(
      baseUri,
      'v1beta/models/${Uri.encodeComponent(model)}:generateContent',
    ).replace(queryParameters: {'key': key}),
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

  static Uri _resolveApiPath(Uri base, String path) {
    final root = base.replace(path: '/', query: null, fragment: null);
    final baseSegments = base.pathSegments.where((item) => item.isNotEmpty);
    final requested = path.split('/');
    if (baseSegments.isNotEmpty && requested.first == baseSegments.first) {
      return root.resolve(path);
    }
    return root.resolve([...baseSegments, ...requested].join('/'));
  }

  static Uri _endpoint(Uri base) {
    final normalized = base.path.endsWith('/')
        ? base
        : base.replace(path: '${base.path}/');
    return normalized.resolve(
      normalized.pathSegments.contains('v1')
          ? 'chat/completions'
          : 'v1/chat/completions',
    );
  }

  static String _limit(String value, int maximum) =>
      value.length <= maximum ? value : value.substring(0, maximum);
  void close() => _client.close(force: true);
}
