import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';

Future<void> showTtsControlsSheet(
  BuildContext context, {
  required SystemTtsController controller,
  required String text,
}) async {
  controller.prepare(text);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final strings = AppStrings.of(context);
      return SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              children: [
                Text(
                  strings.text('系统朗读'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(minHeight: 72),
                  alignment: Alignment.center,
                  child: Text(
                    controller.currentSentence ?? strings.text('当前页面没有可朗读文字'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: strings.text('上一句'),
                      onPressed: controller.sentences.isEmpty
                          ? null
                          : controller.previous,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton.filled(
                      tooltip: strings.text(controller.isPlaying ? '暂停' : '播放'),
                      onPressed: controller.sentences.isEmpty
                          ? null
                          : controller.isPlaying
                          ? controller.pause
                          : controller.play,
                      icon: Icon(
                        controller.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.text('停止'),
                      onPressed: controller.stop,
                      icon: const Icon(Icons.stop),
                    ),
                    IconButton(
                      tooltip: strings.text('下一句'),
                      onPressed: controller.sentences.isEmpty
                          ? null
                          : controller.next,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
                _SliderRow(
                  label: strings.text('语速'),
                  value: controller.rate,
                  min: 0.2,
                  max: 1,
                  onChanged: controller.setRate,
                ),
                _SliderRow(
                  label: strings.text('音调'),
                  value: controller.pitch,
                  min: 0.5,
                  max: 2,
                  onChanged: controller.setPitch,
                ),
                _SliderRow(
                  label: strings.text('音量'),
                  value: controller.volume,
                  min: 0,
                  max: 1,
                  onChanged: controller.setVolume,
                ),
                if (controller.voices.isNotEmpty)
                  DropdownButtonFormField<Map<String, String>>(
                    initialValue: controller.voice,
                    decoration: InputDecoration(labelText: strings.text('声音')),
                    items: [
                      for (final voice in controller.voices)
                        DropdownMenuItem(
                          value: voice,
                          child: Text(
                            '${voice['name'] ?? strings.text('系统声音')} · ${voice['locale'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: controller.selectVoice,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: Text(strings.text('15 分钟后停止')),
                      onPressed: () =>
                          controller.setSleepTimer(const Duration(minutes: 15)),
                    ),
                    ActionChip(
                      label: Text(strings.text('30 分钟后停止')),
                      onPressed: () =>
                          controller.setSleepTimer(const Duration(minutes: 30)),
                    ),
                    ActionChip(
                      label: Text(strings.text('取消定时')),
                      onPressed: () => controller.setSleepTimer(null),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 44, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 36, child: Text(value.toStringAsFixed(1))),
    ],
  );
}
