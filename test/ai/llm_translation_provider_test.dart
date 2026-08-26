import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/ai/llm_assistant_provider.dart';
import 'package:leeef_reader/src/ai/llm_translation_provider.dart';
import 'package:leeef_reader/src/ai/translation_provider.dart';

void main() {
  test(
    'uses contextual chat completion, retries once, and caches result',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      final bodies = <Map<String, Object?>>[];
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/v1/chat/completions');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer secret',
        );
        final decoded = jsonDecode(await utf8.decoder.bind(request).join());
        bodies.add(Map<String, Object?>.from(decoded as Map));
        request.response.headers.contentType = ContentType.json;
        if (requests == 1) {
          request.response.statusCode = 500;
          request.response.write('{"error":"retry"}');
        } else {
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '你好（结合上下文）'},
                },
              ],
            }),
          );
        }
        await request.response.close();
      });
      final provider = LlmTranslationProvider(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        apiKey: 'secret',
        model: 'test-model',
      );
      addTearDown(provider.close);
      const request = TranslationRequest(
        text: 'Hello',
        context: 'The character greets an old friend.',
      );

      expect(await provider.translate(request), '你好（结合上下文）');
      expect(await provider.translate(request), '你好（结合上下文）');
      expect(requests, 2);
      expect(bodies.last['model'], 'test-model');
      expect(
        jsonEncode(bodies.last),
        contains('The character greets an old friend.'),
      );
    },
  );

  test('translates through native Gemini protocol', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/v1beta/models/gemini-test:generateContent');
      expect(request.uri.queryParameters['key'], 'secret');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(jsonEncode(body), contains('目标语言'));
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '原生 Gemini 译文'},
                  ],
                },
              },
            ],
          }),
        );
      await request.response.close();
    });
    final provider = LlmTranslationProvider(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      apiKey: 'secret',
      model: 'gemini-test',
      providerKind: AiProviderKind.gemini,
    );
    addTearDown(provider.close);

    expect(
      await provider.translate(
        const TranslationRequest(text: 'Hello', context: 'Greeting'),
      ),
      '原生 Gemini 译文',
    );
  });

  test('rotates to the next API key after a provider failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final keys = <String>[];
    server.listen((request) async {
      final key = request.headers.value(HttpHeaders.authorizationHeader)!;
      keys.add(key);
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (key == 'Bearer bad-key') {
        request.response.statusCode = 401;
        request.response.write('{"error":"invalid key"}');
      } else {
        request.response.write('{"choices":[{"message":{"content":"轮换成功"}}]}');
      }
      await request.response.close();
    });
    final provider = LlmTranslationProvider(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      apiKeys: const ['bad-key', 'good-key'],
      model: 'test-model',
    );
    addTearDown(provider.close);

    expect(
      await provider.translate(
        const TranslationRequest(text: 'Rotate', context: 'Key rotation'),
      ),
      '轮换成功',
    );
    expect(keys, ['Bearer bad-key', 'Bearer good-key']);
  });
}
