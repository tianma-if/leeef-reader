import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ttsServicePreferenceKey = 'leeef.tts.service';
const ttsBaseUrlPreferenceKey = 'leeef.tts.base_url';
const ttsModelPreferenceKey = 'leeef.tts.model';
const ttsNetworkVoicePreferenceKey = 'leeef.tts.network_voice';
const ttsRegionPreferenceKey = 'leeef.tts.region';
const ttsAppKeyPreferenceKey = 'leeef.tts.app_key';
const ttsApiKeySecureKey = 'leeef.tts.api_key';
const ttsMixingPreferenceKey = 'leeef.tts.mixing';

enum TtsService { system, azure, openAi, alibaba }

class ConfiguredTtsEngine implements TtsEngine {
  ConfiguredTtsEngine({
    HttpClient? client,
    AudioPlayer? player,
    TtsEngine? system,
    bool playbackEnabled = true,
  }) : _client = client ?? HttpClient(),
       _player = player ?? (playbackEnabled ? AudioPlayer() : null),
       _system = system ?? (playbackEnabled ? FlutterSystemTtsEngine() : null) {
    _player?.onPlayerComplete.listen((_) => _completion?.call());
  }
  final HttpClient _client;
  final AudioPlayer? _player;
  final TtsEngine? _system;
  VoidCallback? _completion;
  double _rate = 0.5;
  double _pitch = 1;
  double _volume = 1;
  String? _voice;

  @override
  void setCompletionHandler(VoidCallback handler) {
    _completion = handler;
    _system?.setCompletionHandler(handler);
  }

  @override
  Future<void> speak(String text) async {
    final service = await _serviceFromPreferences();
    await _configureAudioMixing();
    if (service == TtsService.system) {
      final system = _system;
      if (system == null) throw StateError('Playback is disabled.');
      await system.speak(text);
      return;
    }
    final audio = await _synthesize(service, text);
    final player = _player;
    if (player == null) throw StateError('Playback is disabled.');
    await player.setVolume(_volume);
    await player.setPlaybackRate((_rate * 2).clamp(0.5, 2));
    await player.play(BytesSource(audio));
  }

  Future<void> _configureAudioMixing() async {
    final mode =
        (await SharedPreferences.getInstance()).getString(
          ttsMixingPreferenceKey,
        ) ??
        'interrupt';
    final focus = switch (mode) {
      'duck' => AudioContextConfigFocus.duckOthers,
      'mix' => AudioContextConfigFocus.mixWithOthers,
      _ => AudioContextConfigFocus.gain,
    };
    await _player?.setAudioContext(
      AudioContextConfig(focus: focus, stayAwake: true).build(),
    );
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration.speech().copyWith(
        avAudioSessionCategoryOptions: switch (mode) {
          'duck' => AVAudioSessionCategoryOptions.duckOthers,
          'mix' => AVAudioSessionCategoryOptions.mixWithOthers,
          _ => AVAudioSessionCategoryOptions.none,
        },
        androidAudioFocusGainType: mode == 'duck'
            ? AndroidAudioFocusGainType.gainTransientMayDuck
            : AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: mode != 'duck',
      ),
    );
    await session.setActive(true);
  }

  Future<TtsService> _serviceFromPreferences() async {
    final name = (await SharedPreferences.getInstance()).getString(
      ttsServicePreferenceKey,
    );
    return TtsService.values.firstWhere(
      (item) => item.name == name,
      orElse: () => TtsService.system,
    );
  }

  Future<Uint8List> _synthesize(TtsService service, String text) async {
    const storage = FlutterSecureStorage();
    final preferences = await SharedPreferences.getInstance();
    final key = await storage.read(key: ttsApiKeySecureKey) ?? '';
    final voice =
        _voice ??
        preferences.getString(ttsNetworkVoicePreferenceKey) ??
        _defaultVoice(service);
    late HttpClientRequest request;
    switch (service) {
      case TtsService.system:
        throw StateError('System TTS does not synthesize network audio.');
      case TtsService.openAi:
        final base = Uri.parse(
          preferences.getString(ttsBaseUrlPreferenceKey) ??
              'https://api.openai.com/v1',
        );
        final normalized = base.path.endsWith('/')
            ? base
            : base.replace(path: '${base.path}/');
        request = await _client.postUrl(
          normalized.resolve(
            normalized.pathSegments.contains('v1')
                ? 'audio/speech'
                : 'v1/audio/speech',
          ),
        );
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        request.write(
          jsonEncode({
            'model':
                preferences.getString(ttsModelPreferenceKey) ??
                'gpt-4o-mini-tts',
            'voice': voice,
            'input': text,
            'response_format': 'mp3',
            'speed': (_rate * 2).clamp(0.25, 4),
          }),
        );
        break;
      case TtsService.azure:
        final region =
            preferences.getString(ttsRegionPreferenceKey) ?? 'eastasia';
        final base = preferences.getString(ttsBaseUrlPreferenceKey);
        request = await _client.postUrl(
          Uri.parse(
            base?.isNotEmpty == true
                ? base!
                : 'https://$region.tts.speech.microsoft.com/cognitiveservices/v1',
          ),
        );
        request.headers.set('Ocp-Apim-Subscription-Key', key);
        request.headers.set(
          'X-Microsoft-OutputFormat',
          'audio-24khz-48kbitrate-mono-mp3',
        );
        request.headers.contentType = ContentType(
          'application',
          'ssml+xml',
          charset: 'utf-8',
        );
        request.write(
          '<speak version="1.0" xml:lang="zh-CN"><voice name="${_xml(voice)}"><prosody rate="${((_rate - .5) * 150).round()}%" pitch="${((_pitch - 1) * 50).round()}%">${_xml(text)}</prosody></voice></speak>',
        );
        break;
      case TtsService.alibaba:
        final appKey = preferences.getString(ttsAppKeyPreferenceKey) ?? '';
        final base = Uri.parse(
          preferences.getString(ttsBaseUrlPreferenceKey) ??
              'https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/tts',
        );
        request = await _client.getUrl(
          base.replace(
            queryParameters: {
              ...base.queryParameters,
              'appkey': appKey,
              'token': key,
              'text': text,
              'format': 'mp3',
              'sample_rate': '16000',
              'voice': voice,
              'speech_rate': (((_rate - .5) * 1000).round()).toString(),
              'pitch_rate': (((_pitch - 1) * 500).round()).toString(),
            },
          ),
        );
        break;
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'TTS returned HTTP ${response.statusCode}: ${utf8.decode(bytes.take(500).toList(), allowMalformed: true)}',
        uri: request.uri,
      );
    }
    return Uint8List.fromList(bytes);
  }

  @visibleForTesting
  Future<Uint8List> synthesizeForTesting(TtsService service, String text) =>
      _synthesize(service, text);

  static String _defaultVoice(TtsService service) => switch (service) {
    TtsService.openAi => 'alloy',
    TtsService.azure => 'zh-CN-XiaoxiaoNeural',
    TtsService.alibaba => 'xiaoyun',
    TtsService.system => '',
  };
  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  @override
  Future<void> stop() async {
    await _player?.stop();
    await _system?.stop();
  }

  @override
  Future<void> pause() async {
    if (await _serviceFromPreferences() == TtsService.system) {
      await _system?.pause();
    } else {
      await _player?.pause();
    }
  }

  @override
  Future<void> setRate(double value) async {
    _rate = value;
    await _system?.setRate(value);
  }

  @override
  Future<void> setPitch(double value) async {
    _pitch = value;
    await _system?.setPitch(value);
  }

  @override
  Future<void> setVolume(double value) async {
    _volume = value;
    await _player?.setVolume(value);
    await _system?.setVolume(value);
  }

  @override
  Future<List<Map<String, String>>> voices() async {
    final service = await _serviceFromPreferences();
    if (service == TtsService.system) {
      return await _system?.voices() ?? const [];
    }
    final names = switch (service) {
      TtsService.openAi => const [
        'alloy',
        'ash',
        'coral',
        'echo',
        'fable',
        'nova',
        'onyx',
        'sage',
        'shimmer',
      ],
      TtsService.azure => const [
        'zh-CN-XiaoxiaoNeural',
        'zh-CN-YunxiNeural',
        'en-US-AvaNeural',
        'en-US-AndrewNeural',
      ],
      TtsService.alibaba => const ['xiaoyun', 'xiaogang', 'ruoxi', 'siqi'],
      TtsService.system => const <String>[],
    };
    return names.map((name) => {'name': name, 'locale': service.name}).toList();
  }

  @override
  Future<void> setVoice(Map<String, String> voice) async {
    _voice = voice['name'];
    if (await _serviceFromPreferences() == TtsService.system) {
      await _system?.setVoice(voice);
    } else if (_voice != null) {
      await (await SharedPreferences.getInstance()).setString(
        ttsNetworkVoicePreferenceKey,
        _voice!,
      );
    }
  }
}
