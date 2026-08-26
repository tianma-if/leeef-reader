import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/ai/llm_assistant_provider.dart';

void main() {
  test(
    'Anthropic protocol uses native endpoint, headers, and response',
    () async {
      late HttpRequest captured;
      late Map<String, dynamic> body;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        captured = request;
        body = jsonDecode(await utf8.decoder.bind(request).join());
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Claude answer'},
              ],
            }),
          );
        await request.response.close();
      });
      final provider = LlmAssistantProvider(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        apiKeys: const ['anthropic-key'],
        model: 'claude-sonnet-4-5',
        providerKind: AiProviderKind.anthropic,
      );

      final result = await provider.complete(
        messages: const [AiChatMessage(role: 'user', content: 'hello')],
        context: 'book context',
      );

      expect(result, 'Claude answer');
      expect(captured.uri.path, '/v1/messages');
      expect(captured.headers.value('x-api-key'), 'anthropic-key');
      expect(body['system'], contains('book context'));
      provider.close();
      await server.close(force: true);
    },
  );

  test(
    'Gemini protocol uses generateContent and parses candidate text',
    () async {
      late Uri capturedUri;
      late Map<String, dynamic> body;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        capturedUri = request.uri;
        body = jsonDecode(await utf8.decoder.bind(request).join());
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Gemini answer'},
                    ],
                  },
                },
              ],
            }),
          );
        await request.response.close();
      });
      final provider = LlmAssistantProvider(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        apiKeys: const ['gemini-key'],
        model: 'gemini-2.5-flash',
        providerKind: AiProviderKind.gemini,
      );

      final result = await provider.complete(
        messages: const [AiChatMessage(role: 'user', content: 'hello')],
        context: 'book context',
      );

      expect(result, 'Gemini answer');
      expect(
        capturedUri.path,
        '/v1beta/models/gemini-2.5-flash:generateContent',
      );
      expect(capturedUri.queryParameters['key'], 'gemini-key');
      expect(body['contents'], isA<List>());
      provider.close();
      await server.close(force: true);
    },
  );
}
