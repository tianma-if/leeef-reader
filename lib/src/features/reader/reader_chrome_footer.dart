import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/reader/reader_page_turn_policy.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';

enum ReaderChromeTab { none, color, progress, font }

const _paperThemes = <(String, String, String)>[
  ('纸张', '#292b29', '#fbf8f1'),
  ('夜间', '#d8d8d8', '#151515'),
  ('护眼', '#26352b', '#dce8d5'),
  ('OLED', '#eeeeee', '#000000'),
];

/// Mobile chrome matches Readest: tap shows four actions, not a live
/// progress pill. Desktop keeps previous/next plus a compact label.
class ReaderChromeFooter extends StatefulWidget {
  const ReaderChromeFooter({
    required this.progress,
    required this.progressLabel,
    required this.preferences,
    required this.onPreferencesChanged,
    super.key,
    this.onPrevious,
    this.onNext,
    this.onToc,
    this.onSeekProgress,
    this.onOpenFullSettings,
  });

  final double progress;
  final String progressLabel;
  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onPreferencesChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToc;
  final ValueChanged<double>? onSeekProgress;
  final VoidCallback? onOpenFullSettings;

  @override
  State<ReaderChromeFooter> createState() => _ReaderChromeFooterState();
}

class _ReaderChromeFooterState extends State<ReaderChromeFooter> {
  ReaderChromeTab _tab = ReaderChromeTab.none;

  @override
  Widget build(BuildContext context) {
    if (isDesktopReaderPlatform()) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: _DesktopProgressPill(
          label: widget.progressLabel,
          onPrevious: widget.onPrevious,
          onNext: widget.onNext,
        ),
      );
    }
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: switch (_tab) {
                ReaderChromeTab.none => const SizedBox(width: double.infinity),
                ReaderChromeTab.color => _ColorPanel(
                  preferences: widget.preferences,
                  onChanged: widget.onPreferencesChanged,
                ),
                ReaderChromeTab.progress => _ProgressPanel(
                  progress: widget.progress,
                  label: widget.progressLabel,
                  onSeek: widget.onSeekProgress,
                ),
                ReaderChromeTab.font => _FontPanel(
                  preferences: widget.preferences,
                  onChanged: widget.onPreferencesChanged,
                  onOpenFullSettings: widget.onOpenFullSettings,
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _FooterAction(
                    icon: Icons.list,
                    label: strings.text('目录'),
                    selected: false,
                    onPressed: widget.onToc,
                  ),
                  _FooterAction(
                    icon: Icons.wb_sunny_outlined,
                    label: strings.text('颜色'),
                    selected: _tab == ReaderChromeTab.color,
                    onPressed: () => _toggle(ReaderChromeTab.color),
                  ),
                  _FooterAction(
                    icon: Icons.tune,
                    label: strings.text('阅读进度'),
                    selected: _tab == ReaderChromeTab.progress,
                    onPressed: () => _toggle(ReaderChromeTab.progress),
                  ),
                  _FooterAction(
                    icon: Icons.text_fields,
                    label: strings.text('字体'),
                    selected: _tab == ReaderChromeTab.font,
                    onPressed: () => _toggle(ReaderChromeTab.font),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(ReaderChromeTab tab) {
    setState(() => _tab = _tab == tab ? ReaderChromeTab.none : tab);
  }
}

/// Mobile header overlays the page so showing chrome does not reflow text.
class ReaderChromeOverlayBar extends StatelessWidget {
  const ReaderChromeOverlayBar({required this.child, super.key});

  final PreferredSizeWidget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1,
      color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(height: child.preferredSize.height, child: child),
      ),
    );
  }
}

class _DesktopProgressPill extends StatelessWidget {
  const _DesktopProgressPill({
    required this.label,
    this.onPrevious,
    this.onNext,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SafeArea(
      minimum: const EdgeInsets.all(12),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(28),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: strings.text('上一页'),
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              SizedBox(
                width: 100,
                child: Text(label, textAlign: TextAlign.center),
              ),
              IconButton(
                tooltip: strings.text('下一页'),
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.label,
    required this.selected,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, color: color),
    );
  }
}

class _ColorPanel extends StatelessWidget {
  const _ColorPanel({required this.preferences, required this.onChanged});

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final appearance = AppAppearanceController.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final theme in _paperThemes)
                ChoiceChip(
                  label: Text(strings.text(theme.$1)),
                  selected: preferences.background == theme.$3,
                  onSelected: (_) => onChanged(
                    preferences.copyWith(
                      foreground: theme.$2,
                      background: theme.$3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: appearance,
            builder: (context, _) => SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(strings.text('跟随系统')),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(strings.text('浅色')),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(strings.text('深色')),
                ),
              ],
              selected: {appearance.themeMode},
              onSelectionChanged: (value) =>
                  appearance.setThemeMode(value.single),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.progress,
    required this.label,
    this.onSeek,
  });

  final double progress;
  final String label;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: theme.sliderTheme.copyWith(
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: progress.clamp(0.0, 1.0), onChanged: onSeek),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontPanel extends StatelessWidget {
  const _FontPanel({
    required this.preferences,
    required this.onChanged,
    this.onOpenFullSettings,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;
  final VoidCallback? onOpenFullSettings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(strings.text('字号')),
              Expanded(
                child: Slider(
                  value: preferences.fontSize.clamp(12, 32),
                  min: 12,
                  max: 32,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(fontSize: value)),
                ),
              ),
              Text(preferences.fontSize.round().toString()),
            ],
          ),
          Row(
            children: [
              Text(strings.text('行距')),
              Expanded(
                child: Slider(
                  value: preferences.lineHeight.clamp(1.1, 2.5),
                  min: 1.1,
                  max: 2.5,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(lineHeight: value)),
                ),
              ),
            ],
          ),
          if (onOpenFullSettings != null)
            TextButton(
              onPressed: onOpenFullSettings,
              child: Text(strings.text('阅读样式')),
            ),
        ],
      ),
    );
  }
}
