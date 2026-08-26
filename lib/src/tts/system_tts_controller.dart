import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TtsEngine {
  void setCompletionHandler(VoidCallback handler);
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
  Future<void> setVolume(double value);
  Future<List<Map<String, String>>> voices();
  Future<void> setVoice(Map<String, String> voice);
}

abstract interface class TtsMediaControls {
  void bind({
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
    required Future<void> Function() previous,
    required Future<void> Function() next,
  });
  void update({required String? sentence, required bool playing});
  void unbind();
}

class FlutterSystemTtsEngine implements TtsEngine {
  FlutterSystemTtsEngine([FlutterTts? engine])
    : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;

  @override
  void setCompletionHandler(VoidCallback handler) =>
      _engine.setCompletionHandler(handler);

  @override
  Future<void> speak(String text) async => _engine.speak(text);

  @override
  Future<void> stop() async => _engine.stop();

  @override
  Future<void> pause() async => _engine.pause();

  @override
  Future<void> setRate(double value) async => _engine.setSpeechRate(value);

  @override
  Future<void> setPitch(double value) async => _engine.setPitch(value);

  @override
  Future<void> setVolume(double value) async => _engine.setVolume(value);

  @override
  Future<List<Map<String, String>>> voices() async {
    final value = await _engine.getVoices;
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((voice) {
          return voice.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> setVoice(Map<String, String> voice) async =>
      _engine.setVoice(voice);
}

class SystemTtsController extends ChangeNotifier {
  SystemTtsController({TtsEngine? engine, TtsMediaControls? mediaControls})
    : _engine = engine ?? FlutterSystemTtsEngine(),
      _mediaControls = mediaControls {
    _engine.setCompletionHandler(_onCompleted);
    _mediaControls?.bind(
      play: play,
      pause: pause,
      stop: stop,
      previous: previous,
      next: next,
    );
  }

  final TtsEngine _engine;
  final TtsMediaControls? _mediaControls;
  List<String> _sentences = const [];
  String _source = '';
  int _index = 0;
  bool _playing = false;
  bool _paused = false;
  double _rate = 0.5;
  double _pitch = 1;
  double _volume = 1;
  List<Map<String, String>> _voices = const [];
  Map<String, String>? _voice;
  Timer? _sleepTimer;

  List<String> get sentences => _sentences;
  int get index => _index;
  bool get isPlaying => _playing;
  bool get isPaused => _paused;
  double get rate => _rate;
  double get pitch => _pitch;
  double get volume => _volume;
  List<Map<String, String>> get voices => _voices;
  Map<String, String>? get voice => _voice;
  String? get currentSentence => _sentences.isEmpty
      ? null
      : _sentences[_index.clamp(0, _sentences.length - 1)];

  void _changed() {
    _mediaControls?.update(sentence: currentSentence, playing: _playing);
    notifyListeners();
  }

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _rate = preferences.getDouble('leeef.tts.rate') ?? 0.5;
    _pitch = preferences.getDouble('leeef.tts.pitch') ?? 1;
    _volume = preferences.getDouble('leeef.tts.volume') ?? 1;
    await Future.wait([
      _engine.setRate(_rate),
      _engine.setPitch(_pitch),
      _engine.setVolume(_volume),
    ]);
    try {
      _voices = await _engine.voices();
      final savedName = preferences.getString('leeef.tts.voice.name');
      final savedLocale = preferences.getString('leeef.tts.voice.locale');
      if (savedName != null) {
        _voice = _voices.cast<Map<String, String>?>().firstWhere(
          (voice) =>
              voice?['name'] == savedName && voice?['locale'] == savedLocale,
          orElse: () => null,
        );
        if (_voice != null) await _engine.setVoice(_voice!);
      }
    } on Object {
      _voices = const [];
    }
    _changed();
  }

  void prepare(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized == _source) return;
    _source = normalized;
    _sentences = splitSentences(normalized);
    _index = 0;
    _playing = false;
    _paused = false;
    _changed();
  }

  Future<void> play() async {
    if (_sentences.isEmpty) return;
    _playing = true;
    _paused = false;
    _changed();
    await _engine.speak(_sentences[_index]);
  }

  Future<void> pause() async {
    if (!_playing) return;
    await _engine.pause();
    _playing = false;
    _paused = true;
    _changed();
  }

  Future<void> stop() async {
    await _engine.stop();
    _playing = false;
    _paused = false;
    _sleepTimer?.cancel();
    _changed();
  }

  Future<void> previous() async {
    if (_sentences.isEmpty) return;
    _index = (_index - 1).clamp(0, _sentences.length - 1);
    await _engine.stop();
    await play();
  }

  Future<void> next() async {
    if (_sentences.isEmpty) return;
    if (_index + 1 >= _sentences.length) {
      await stop();
      return;
    }
    _index++;
    await _engine.stop();
    await play();
  }

  void _onCompleted() {
    if (!_playing) return;
    if (_index + 1 >= _sentences.length) {
      _playing = false;
      _paused = false;
      _changed();
      return;
    }
    _index++;
    _changed();
    unawaited(_engine.speak(_sentences[_index]));
  }

  Future<void> setRate(double value) async {
    _rate = value;
    await _engine.setRate(value);
    await _saveDouble('leeef.tts.rate', value);
    _changed();
  }

  Future<void> setPitch(double value) async {
    _pitch = value;
    await _engine.setPitch(value);
    await _saveDouble('leeef.tts.pitch', value);
    _changed();
  }

  Future<void> setVolume(double value) async {
    _volume = value;
    await _engine.setVolume(value);
    await _saveDouble('leeef.tts.volume', value);
    _changed();
  }

  Future<void> selectVoice(Map<String, String>? value) async {
    if (value == null) return;
    _voice = value;
    await _engine.setVoice(value);
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString('leeef.tts.voice.name', value['name'] ?? ''),
      preferences.setString('leeef.tts.voice.locale', value['locale'] ?? ''),
    ]);
    _changed();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration != null) {
      _sleepTimer = Timer(duration, () => unawaited(stop()));
    }
    _changed();
  }

  static List<String> splitSentences(String text) {
    if (text.trim().isEmpty) return const [];
    final matches = RegExp(r'[^。！？.!?]+[。！？.!?]*').allMatches(text);
    final result = <String>[];
    for (final match in matches) {
      var sentence = match.group(0)!.trim();
      while (sentence.length > 400) {
        var split = sentence.lastIndexOf('，', 400);
        if (split < 120) split = 400;
        result.add(sentence.substring(0, split + 1).trim());
        sentence = sentence.substring(split + 1).trim();
      }
      if (sentence.isNotEmpty) result.add(sentence);
    }
    return result;
  }

  static Future<void> _saveDouble(String key, double value) async {
    await (await SharedPreferences.getInstance()).setDouble(key, value);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _mediaControls?.unbind();
    unawaited(_engine.stop());
    super.dispose();
  }
}
