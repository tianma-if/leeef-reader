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

/// Mobile chrome matches Readest: tap shows TOC/color/progress/font.
/// Desktop hover chrome is a progress bar with previous/next, not a pill.
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
    this.onTts,
    this.onHistoryBack,
    this.onHistoryForward,
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
  final VoidCallback? onTts;
  final VoidCallback? onHistoryBack;
  final VoidCallback? onHistoryForward;

  @override
  State<ReaderChromeFooter> createState() => _ReaderChromeFooterState();
}

class _ReaderChromeFooterState extends State<ReaderChromeFooter> {
  ReaderChromeTab _tab = ReaderChromeTab.none;

  @override
  Widget build(BuildContext context) {
    if (isDesktopReaderPlatform()) {
      return _DesktopFooterBar(
        progress: widget.progress,
        label: widget.progressLabel,
        onPrevious: widget.onPrevious,
        onNext: widget.onNext,
        onSeekProgress: widget.onSeekProgress,
        onTts: widget.onTts,
        onHistoryBack: widget.onHistoryBack,
        onHistoryForward: widget.onHistoryForward,
      );
    }
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.97),
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
                  onPrevious: widget.onPrevious,
                  onNext: widget.onNext,
                  onHistoryBack: widget.onHistoryBack,
                  onHistoryForward: widget.onHistoryForward,
                ),
                ReaderChromeTab.font => _FontPanel(
                  preferences: widget.preferences,
                  onChanged: widget.onPreferencesChanged,
                  onOpenFullSettings: widget.onOpenFullSettings,
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    icon: Icons.linear_scale,
                    label: strings.text('阅读进度'),
                    selected: _tab == ReaderChromeTab.progress,
                    onPressed: () => _toggle(ReaderChromeTab.progress),
                  ),
                  _FooterAction(
                    icon: Icons.font_download_outlined,
                    label: strings.text('字体'),
                    selected: _tab == ReaderChromeTab.font,
                    onPressed: () => _toggle(ReaderChromeTab.font),
                  ),
                  if (widget.onTts != null)
                    _FooterAction(
                      icon: Icons.headphones_outlined,
                      label: strings.text('朗读'),
                      selected: false,
                      onPressed: widget.onTts,
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

class _DesktopFooterBar extends StatelessWidget {
  const _DesktopFooterBar({
    required this.progress,
    required this.label,
    this.onPrevious,
    this.onNext,
    this.onSeekProgress,
    this.onTts,
    this.onHistoryBack,
    this.onHistoryForward,
  });

  final double progress;
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<double>? onSeekProgress;
  final VoidCallback? onTts;
  final VoidCallback? onHistoryBack;
  final VoidCallback? onHistoryForward;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: strings.text('上一页'),
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                if (onHistoryBack != null)
                  IconButton(
                    tooltip: strings.text('后退到上次跳转位置'),
                    onPressed: onHistoryBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                  ),
                if (onHistoryForward != null)
                  IconButton(
                    tooltip: strings.text('前进到下个跳转位置'),
                    onPressed: onHistoryForward,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: theme.sliderTheme.copyWith(
                      trackHeight: 2,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: onSeekProgress,
                    ),
                  ),
                ),
                if (onTts != null)
                  IconButton(
                    tooltip: strings.text('朗读'),
                    onPressed: onTts,
                    icon: const Icon(Icons.headphones_outlined, size: 18),
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final theme in _paperThemes) ...[
                  _ThemeSwatch(
                    label: strings.text(theme.$1),
                    foreground: theme.$2,
                    background: theme.$3,
                    selected: preferences.background == theme.$3,
                    onTap: () => onChanged(
                      preferences.copyWith(
                        foreground: theme.$2,
                        background: theme.$3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                ListenableBuilder(
                  listenable: appearance,
                  builder: (context, _) {
                    final dark = appearance.themeMode == ThemeMode.dark;
                    return _ThemeSwatch(
                      label: dark ? strings.text('深色') : strings.text('浅色'),
                      foreground: dark ? '#eeeeee' : '#292b29',
                      background: dark ? '#000000' : '#ffffff',
                      selected: false,
                      icon: dark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      onTap: () => appearance.setThemeMode(
                        dark ? ThemeMode.light : ThemeMode.dark,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.label,
    required this.foreground,
    required this.background,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String foreground;
  final String background;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = Color(
      0xFF000000 | int.parse(background.substring(1), radix: 16),
    );
    final fg = Color(
      0xFF000000 | int.parse(foreground.substring(1), radix: 16),
    );
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: icon != null
              ? Icon(icon, color: fg, size: 20)
              : Text(label, style: TextStyle(color: fg, fontSize: 12)),
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.progress,
    required this.label,
    this.onSeek,
    this.onPrevious,
    this.onNext,
    this.onHistoryBack,
    this.onHistoryForward,
  });

  final double progress;
  final String label;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onHistoryBack;
  final VoidCallback? onHistoryForward;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SliderTheme(
            data: theme.sliderTheme.copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: progress.clamp(0.0, 1.0), onChanged: onSeek),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: strings.text('上一页'),
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: strings.text('后退到上次跳转位置'),
                onPressed: onHistoryBack,
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
              IconButton(
                tooltip: strings.text('前进到下个跳转位置'),
                onPressed: onHistoryForward,
                icon: const Icon(Icons.arrow_forward, size: 20),
              ),
              IconButton(
                tooltip: strings.text('下一页'),
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(strings.text('A'), style: const TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: preferences.fontSize.clamp(12, 32),
                  min: 12,
                  max: 32,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(fontSize: value)),
                ),
              ),
              Text(strings.text('A'), style: const TextStyle(fontSize: 18)),
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
          Row(
            children: [
              Text(strings.text('边距')),
              Expanded(
                child: Slider(
                  value: preferences.margin.clamp(8, 48),
                  min: 8,
                  max: 48,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(margin: value)),
                ),
              ),
            ],
          ),
          if (onOpenFullSettings != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenFullSettings,
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: Text(strings.text('阅读样式')),
              ),
            ),
        ],
      ),
    );
  }
}
