import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/android_auto_update_service.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';

class AndroidUpdateHost extends StatefulWidget {
  const AndroidUpdateHost({required this.child, super.key});

  final Widget child;

  @override
  State<AndroidUpdateHost> createState() => _AndroidUpdateHostState();
}

class _AndroidUpdateHostState extends State<AndroidUpdateHost>
    with WidgetsBindingObserver {
  final _updater = AndroidAutoUpdateService.instance;
  Timer? _checkTimer;
  DateTime? _lastCheck;
  int? _promptedAvailableVersion;
  int? _promptedReadyVersion;
  bool _promptVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updater.addListener(_updateChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    _lastCheck = DateTime.now();
    await _updater.initialize();
    if (!mounted) return;
    _checkTimer = Timer.periodic(
      AndroidAutoUpdateService.checkInterval,
      (_) => unawaited(_checkNow()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastCheck = _lastCheck;
    if (lastCheck == null ||
        DateTime.now().difference(lastCheck) >=
            AndroidAutoUpdateService.checkInterval) {
      unawaited(_checkNow());
    }
  }

  Future<void> _checkNow() async {
    _lastCheck = DateTime.now();
    await _updater.checkNow();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _updater.removeListener(_updateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _updateChanged() {
    if (!mounted) return;
    setState(() {});
    if (_promptVisible) return;

    final state = _updater.state;
    final identity = state.availableVersionCode ?? -1;
    if (state.stage == AndroidUpdateStage.available &&
        _promptedAvailableVersion != identity) {
      _promptVisible = true;
      _promptedAvailableVersion = identity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showAvailablePrompt());
      });
    } else if (state.isReady && _promptedReadyVersion != identity) {
      _promptVisible = true;
      _promptedReadyVersion = identity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showReadyPrompt());
      });
    }
  }

  Future<void> _showAvailablePrompt() async {
    final strings = AppStrings.of(context);
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('发现新版本')),
        content: Text(strings.text('Google Play 确认后会在后台下载更新，下载完成后再提示安装。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('稍后')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download_outlined),
            label: Text(strings.text('开始更新')),
          ),
        ],
      ),
    );
    _promptVisible = false;
    if (start == true && mounted) await _startDownload();
  }

  Future<void> _showReadyPrompt() async {
    final strings = AppStrings.of(context);
    final restart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('Android 更新已就绪')),
        content: Text(strings.text('新版本已通过 Google Play 下载完成。重启应用即可完成安装。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('稍后')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.restart_alt),
            label: Text(strings.text('重启以更新')),
          ),
        ],
      ),
    );
    _promptVisible = false;
    if (restart == true && mounted) await _install();
  }

  Future<void> _startDownload() async {
    final result = await _updater.startBackgroundDownload();
    if (result == AndroidUpdateStartResult.failed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('启动更新下载失败，请稍后重试'))),
      );
    }
  }

  Future<void> _install() async {
    final started = await _updater.installDownloadedUpdate();
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('启动更新安装失败，请稍后重试'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _updater.state;
    final strings = AppStrings.of(context);
    final showAction =
        state.stage == AndroidUpdateStage.available ||
        state.stage == AndroidUpdateStage.downloading ||
        state.stage == AndroidUpdateStage.ready ||
        state.stage == AndroidUpdateStage.installing;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showAction)
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Semantics(
                liveRegion: true,
                child: switch (state.stage) {
                  AndroidUpdateStage.available => FilledButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(strings.text('下载更新')),
                  ),
                  AndroidUpdateStage.ready => FilledButton.icon(
                    onPressed: _install,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(strings.text('重启以更新')),
                  ),
                  _ => FilledButton.tonalIcon(
                    onPressed: null,
                    icon: const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: Text(
                      strings.text(
                        state.stage == AndroidUpdateStage.installing
                            ? '正在安装更新'
                            : '新版本正在后台下载',
                      ),
                    ),
                  ),
                },
              ),
            ),
          ),
      ],
    );
  }
}
