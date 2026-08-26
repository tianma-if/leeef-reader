import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';

class TtsMediaControlBridge extends BaseAudioHandler
    implements TtsMediaControls {
  TtsMediaControlBridge._();

  static TtsMediaControlBridge? instance;

  static Future<void> initialize() async {
    final bridge = TtsMediaControlBridge._();
    instance = await AudioService.init<TtsMediaControlBridge>(
      builder: () => bridge,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.leeef.leeefReader.tts',
        androidNotificationChannelName: 'Leeef 朗读',
        androidNotificationOngoing: true,
      ),
    );
  }

  Future<void> Function()? _play;
  Future<void> Function()? _pause;
  Future<void> Function()? _stop;
  Future<void> Function()? _previous;
  Future<void> Function()? _next;

  @override
  void bind({
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {
    _play = play;
    _pause = pause;
    _stop = stop;
    _previous = previous;
    _next = next;
  }

  @override
  void update({required String? sentence, required bool playing}) {
    mediaItem.add(
      MediaItem(
        id: 'leeef-tts',
        title: sentence ?? 'Leeef Reader 朗读',
        album: 'Leeef Reader',
      ),
    );
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: const [0, 1, 4],
        processingState: AudioProcessingState.ready,
        playing: playing,
      ),
    );
  }

  @override
  Future<void> play() async => _play?.call();
  @override
  Future<void> pause() async => _pause?.call();
  @override
  Future<void> stop() async => _stop?.call();
  @override
  Future<void> skipToPrevious() async => _previous?.call();
  @override
  Future<void> skipToNext() async => _next?.call();

  @override
  void unbind() {
    _play = null;
    _pause = null;
    _stop = null;
    _previous = null;
    _next = null;
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }
}
