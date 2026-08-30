import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/platform/desktop_auto_update_service.dart';

class DesktopUpdateHost extends StatefulWidget {
  const DesktopUpdateHost({required this.child, super.key});

  final Widget child;

  @override
  State<DesktopUpdateHost> createState() => _DesktopUpdateHostState();
}

class _DesktopUpdateHostState extends State<DesktopUpdateHost> {
  final _updater = DesktopAutoUpdateService.instance;
  String? _promptedVersion;
  bool _promptVisible = false;

  @override
  void initState() {
    super.initState();
    _updater.addListener(_updateChanged);
    unawaited(_updater.initialize());
  }

  @override
  void dispose() {
    _updater.removeListener(_updateChanged);
    super.dispose();
  }

  void _updateChanged() {
    if (!mounted) return;
    setState(() {});
    final state = _updater.state;
    final identity = state.version ?? 'latest';
    if (!state.isReady || _promptVisible || _promptedVersion == identity) {
      return;
    }
    _promptVisible = true;
    _promptedVersion = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showReadyPrompt());
      }
    });
  }

  Future<void> _showReadyPrompt() async {
    final strings = AppStrings.of(context);
    final version = _updater.state.version;
    final restart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('Leeef Reader 更新已就绪')),
        content: Text(strings.desktopUpdateReadyDetails(version)),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (state.isReady)
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Semantics(
                liveRegion: true,
                child: FilledButton.icon(
                  onPressed: _install,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(
                    state.version == null
                        ? AppStrings.of(context).text('重启以更新')
                        : '${AppStrings.of(context).text('重启以更新')} v${state.version}',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
