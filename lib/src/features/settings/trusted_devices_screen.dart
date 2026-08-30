import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/sync/configured_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';
import 'package:leeef_reader/src/sync/trusted/pairing_service.dart';
import 'package:leeef_reader/src/sync/trusted/portable_configuration.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:leeef_reader/src/sync/trusted/sync_space_store.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_device.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrustedDevicesScreen extends ConsumerStatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  ConsumerState<TrustedDevicesScreen> createState() =>
      _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends ConsumerState<TrustedDevicesScreen> {
  bool _busy = true;
  String? _error;
  SyncSpaceState? _space;
  DeviceIdentity? _identity;
  List<TrustedDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload(refreshRemote: true));
  }

  Future<
    ({
      SyncSpaceStore spaceStore,
      PortableConfiguration configuration,
      PairingService pairing,
      TrustedSyncService trustedSync,
    })
  >
  _services() async {
    final preferences = await SharedPreferences.getInstance();
    const secrets = FlutterSecretStore();
    final spaceStore = SyncSpaceStore(
      preferences: preferences,
      secrets: secrets,
    );
    final configuration = PortableConfiguration(
      preferences: preferences,
      secrets: secrets,
    );
    return (
      spaceStore: spaceStore,
      configuration: configuration,
      pairing: PairingService(
        spaceStore: spaceStore,
        configuration: configuration,
      ),
      trustedSync: TrustedSyncService(
        spaceStore: spaceStore,
        configuration: configuration,
      ),
    );
  }

  Future<void> _reload({bool refreshRemote = false}) async {
    if (mounted) setState(() => _busy = true);
    try {
      final services = await _services();
      if (refreshRemote && await services.spaceStore.loadSpace() != null) {
        try {
          final backend = await loadConfiguredSyncBackend();
          if (backend case final SyncDocumentBackend documentBackend) {
            await services.trustedSync.synchronize(documentBackend);
          }
        } on Object {
          // Cached device state remains useful while the backend is offline.
        }
      }
      final identity = await services.spaceStore.loadOrCreateIdentity();
      final devices = await services.spaceStore.loadDevices();
      if (!mounted) return;
      setState(() {
        _space = null;
        _identity = identity;
        _devices = devices;
        _error = null;
      });
      final space = await services.spaceStore.loadSpace();
      if (mounted) setState(() => _space = space);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hostPairing() async {
    setState(() => _busy = true);
    PairingHostSession? session;
    try {
      final services = await _services();
      session = await services.pairing.startHost();
      if (!mounted) return;
      BuildContext? dialogContext;
      unawaited(
        session.completion.then((device) {
          final context = dialogContext;
          if (context != null && context.mounted) {
            Navigator.of(context).pop(device);
          }
        }),
      );
      final device = await showDialog<TrustedDevice>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          final strings = AppStrings.of(context);
          return AlertDialog(
            title: Text(strings.text('让其他设备加入')),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.text('在另一台设备输入下面的配对码。两台设备需要连接同一个局域网。')),
                  const SizedBox(height: 20),
                  SelectionArea(
                    child: Text(
                      session!.code,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(strings.text('配对码 5 分钟内有效且只能使用一次。')),
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: session!.code));
                },
                icon: const Icon(Icons.copy),
                label: Text(strings.text('复制配对码')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(strings.text('取消')),
              ),
            ],
          );
        },
      );
      if (device != null && mounted) {
        Object? syncError;
        try {
          await _syncEverything();
        } on Object catch (error) {
          syncError = error;
        }
        if (mounted) {
          _showMessage(
            '${AppStrings.of(context).text('已添加设备')}：${device.name}'
            '${syncError == null ? '' : '\n${AppStrings.of(context).text('配置已传输，书库将在同步后端可用时继续同步')}'}',
          );
        }
      }
    } on Object catch (error) {
      if (mounted) _showMessage(AppStrings.of(context).failure('设备配对', error));
    } finally {
      await session?.close();
      await _reload();
    }
  }

  Future<void> _joinPairing() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('从已有设备恢复')),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
            ],
            decoration: InputDecoration(
              labelText: AppStrings.of(context).text('配对码'),
              helperText: AppStrings.of(context).text('两台设备需要连接同一个局域网'),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppStrings.of(context).text('开始配对')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final services = await _services();
      final result = await services.pairing.join(code);
      await AppAppearanceController.instance.load();
      try {
        await _syncEverything();
      } on Object {
        // Pairing has already restored credentials. Offline data sync retries
        // through the normal automatic sync host.
      }
      if (!mounted) return;
      _showMessage(
        '${AppStrings.of(context).text('设备配对完成，已恢复配置')} '
        '(${result.importedConfigurationValues})',
      );
    } on Object catch (error) {
      if (mounted) _showMessage(AppStrings.of(context).failure('设备配对', error));
    } finally {
      await _reload();
    }
  }

  Future<void> _syncEverything() async {
    final backend = await loadConfiguredSyncBackend();
    await SyncEngine(
      repository: await ref.read(libraryRepositoryProvider.future),
      backend: backend,
      libraryDirectory: await ref.read(libraryDirectoryProvider.future),
      trustedSyncService: await loadTrustedSyncService(),
    ).synchronize();
    ref.invalidate(libraryBooksProvider);
    ref.invalidate(allExcerptsProvider);
    ref.invalidate(allBookmarksProvider);
  }

  Future<void> _renameCurrentDevice() async {
    final current = _identity?.device;
    if (current == null) return;
    final controller = TextEditingController(text: current.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('设备名称')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppStrings.of(context).text('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final services = await _services();
    await services.spaceStore.setDeviceName(name);
    try {
      await _syncEverything();
    } on Object {
      // The renamed device will be announced on the next successful sync.
    }
    await _reload();
  }

  Future<void> _revoke(TrustedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('移除同步设备')),
        content: Text(
          '${device.name}\n\n${AppStrings.of(context).text('移除后，该设备将不能再获取后续配置。')}\n\n'
          '${AppStrings.of(context).text('如果设备已经丢失，还应在 S3/WebDAV 服务端更换访问凭据。')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('移除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final backend = await loadConfiguredSyncBackend();
      if (backend is! SyncDocumentBackend) {
        throw StateError('当前同步后端不支持设备管理。');
      }
      final documentBackend = backend as SyncDocumentBackend;
      final services = await _services();
      await services.trustedSync.revokeDevice(documentBackend, device.id);
      await services.trustedSync.synchronize(documentBackend);
      if (mounted) {
        _showMessage(AppStrings.of(context).text('设备已移除'));
      }
    } on Object catch (error) {
      if (mounted) _showMessage(AppStrings.of(context).failure('移除设备', error));
    } finally {
      await _reload();
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final currentId = _identity?.device.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('我的同步设备')),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => _reload(refreshRemote: true),
            tooltip: strings.text('刷新'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy && _identity == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _space == null
                              ? strings.text('尚未建立可信设备空间')
                              : strings.text('配置、凭据和书库数据将在可信设备间加密同步'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.text(
                            '设备配对后会自动迁移 S3/WebDAV、AI、TTS、OPDS 和阅读配置。',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _hostPairing,
                              icon: const Icon(Icons.add_link),
                              label: Text(strings.text('让其他设备加入')),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _joinPairing,
                              icon: const Icon(Icons.settings_backup_restore),
                              label: Text(strings.text('从已有设备恢复')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  strings.text('已绑定设备'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final device in _devices)
                  Card(
                    child: ListTile(
                      leading: Icon(_platformIcon(device.platform)),
                      title: Text(
                        '${device.name}${device.id == currentId ? ' · ${strings.text('本机')}' : ''}',
                      ),
                      subtitle: Text(
                        device.isRevoked
                            ? strings.text('已移除')
                            : '${device.platform} · ${strings.text('最近同步')} ${_formatTime(device.lastSeenAt)}',
                      ),
                      trailing: device.id == currentId
                          ? IconButton(
                              onPressed: _busy ? null : _renameCurrentDevice,
                              tooltip: strings.text('重命名'),
                              icon: const Icon(Icons.edit_outlined),
                            )
                          : device.isRevoked
                          ? null
                          : IconButton(
                              onPressed: _busy ? null : () => _revoke(device),
                              tooltip: strings.text('移除'),
                              icon: const Icon(Icons.link_off),
                            ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    if (now.difference(local).abs() < const Duration(minutes: 2)) {
      return AppStrings.of(context).text('刚刚');
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static IconData _platformIcon(String platform) => switch (platform) {
    'ios' => Icons.phone_iphone,
    'android' => Icons.android,
    'macos' => Icons.laptop_mac,
    'windows' => Icons.computer,
    _ => Icons.devices,
  };
}
