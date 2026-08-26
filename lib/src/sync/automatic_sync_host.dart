import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/sync/configured_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutomaticSyncHost extends ConsumerStatefulWidget {
  const AutomaticSyncHost({
    required this.child,
    required this.onCompleted,
    super.key,
  });

  final Widget child;
  final ValueChanged<SyncReport> onCompleted;

  @override
  ConsumerState<AutomaticSyncHost> createState() => _AutomaticSyncHostState();
}

class _AutomaticSyncHostState extends ConsumerState<AutomaticSyncHost>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  bool _synchronizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (_) => _scheduleSync(),
    );
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _scheduleSync(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleSync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleSync();
  }

  void _scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_synchronizeIfAllowed()),
    );
  }

  Future<void> _synchronizeIfAllowed() async {
    if (_synchronizing || !mounted) return;
    final preferences = await SharedPreferences.getInstance();
    if (!(preferences.getBool('leeef.sync.auto') ?? true)) return;
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;
    final wifiOnly = preferences.getBool('leeef.sync.wifi_only') ?? false;
    if (wifiOnly &&
        !connectivity.contains(ConnectivityResult.wifi) &&
        !connectivity.contains(ConnectivityResult.ethernet)) {
      return;
    }
    _synchronizing = true;
    try {
      final engine = SyncEngine(
        repository: await ref.read(libraryRepositoryProvider.future),
        backend: await loadConfiguredSyncBackend(),
        libraryDirectory: await ref.read(libraryDirectoryProvider.future),
      );
      final report = await engine.synchronize();
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(allExcerptsProvider);
      ref.invalidate(allBookmarksProvider);
      if (mounted &&
          (report.uploadedOperations > 0 ||
              report.downloadedOperations > 0 ||
              report.downloadedBooks > 0 ||
              report.downloadedCovers > 0)) {
        widget.onCompleted(report);
      }
    } on Object {
      // Offline and incomplete configuration are expected. Pending operations
      // remain durable and the next connectivity/lifecycle event retries them.
    } finally {
      _synchronizing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
