import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('splits mixed Chinese and Latin text into bounded sentences', () {
    final sentences = SystemTtsController.splitSentences(
      '第一句。第二句！Third sentence? 最后一句',
    );
    expect(sentences, ['第一句。', '第二句！', 'Third sentence?', '最后一句']);
  });

  test('plays, advances, pauses, and persists system TTS settings', () async {
    SharedPreferences.setMockInitialValues({});
    final engine = _FakeTtsEngine();
    final controller = SystemTtsController(engine: engine);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.prepare('一句。二句。');

    await controller.play();
    expect(engine.spoken, ['一句。']);
    engine.complete();
    expect(controller.index, 1);
    expect(engine.spoken, ['一句。', '二句。']);
    await controller.pause();
    expect(controller.isPaused, isTrue);
    await controller.previous();
    expect(controller.index, 0);

    await controller.setRate(0.7);
    await controller.setPitch(1.2);
    await controller.setVolume(0.8);
    final values = await SharedPreferences.getInstance();
    expect(values.getDouble('leeef.tts.rate'), 0.7);
    expect(values.getDouble('leeef.tts.pitch'), 1.2);
    expect(values.getDouble('leeef.tts.volume'), 0.8);
  });
}

class _FakeTtsEngine implements TtsEngine {
  VoidCallback? completionHandler;
  final spoken = <String>[];

  void complete() => completionHandler?.call();

  @override
  void setCompletionHandler(VoidCallback handler) {
    completionHandler = handler;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> setPitch(double value) async {}

  @override
  Future<void> setRate(double value) async {}

  @override
  Future<void> setVoice(Map<String, String> voice) async {}

  @override
  Future<void> setVolume(double value) async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<List<Map<String, String>>> voices() async => [
    {'name': 'Test Voice', 'locale': 'zh-CN'},
  ];
}
