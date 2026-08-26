import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/tts/configured_tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'OpenAI network TTS sends configured model, voice, key, and text',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      TestWidgetsFlutterBinding.ensureInitialized();
      addTearDown(() => server.close(force: true));
      final received = <String, Object?>{};
      server.listen((request) async {
        received['path'] = request.uri.path;
        received['authorization'] = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        received.addAll(
          Map<String, Object?>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          ),
        );
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      SharedPreferences.setMockInitialValues({
        ttsBaseUrlPreferenceKey:
            'http://${server.address.host}:${server.port}/v1',
        ttsModelPreferenceKey: 'tts-model',
        ttsNetworkVoicePreferenceKey: 'nova',
      });
      FlutterSecureStorage.setMockInitialValues({ttsApiKeySecureKey: 'secret'});
      final engine = ConfiguredTtsEngine(
        client: client,
        playbackEnabled: false,
      );
      final bytes = await engine.synthesizeForTesting(
        TtsService.openAi,
        'Read this',
      );
      expect(bytes, [1, 2, 3]);
      expect(received['path'], '/v1/audio/speech');
      expect(received['authorization'], 'Bearer secret');
      expect(received['model'], 'tts-model');
      expect(received['voice'], 'nova');
      expect(received['input'], 'Read this');
    },
  );
}
