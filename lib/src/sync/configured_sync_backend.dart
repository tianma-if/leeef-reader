import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/s3_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/webdav_sync_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reconstructs the backend selected in Settings for background and per-book
/// actions without exposing credentials to the widget tree.
Future<SyncBackend> loadConfiguredSyncBackend() async {
  const secureStorage = FlutterSecureStorage();
  final preferences = await SharedPreferences.getInstance();
  final kind = preferences.getString('leeef.sync.backend') ?? 's3';
  switch (kind) {
    case 'directory':
      final path = preferences.getString('leeef.sync.directory');
      if (path == null) throw StateError('请先在设置中选择同步目录。');
      return DirectorySyncBackend(Directory(path));
    case 'webDav':
      final url = preferences.getString('leeef.sync.webdav.url');
      if (url == null) throw StateError('请先在设置中配置 WebDAV。');
      return WebDavSyncBackend(
        root: Uri.parse(url),
        username: preferences.getString('leeef.sync.webdav.username'),
        password: await secureStorage.read(key: 'leeef.sync.webdav.password'),
      );
    case 's3':
      final endpoint = preferences.getString('leeef.sync.s3.endpoint');
      final bucket = preferences.getString('leeef.sync.s3.bucket');
      if (endpoint == null || bucket == null) {
        throw StateError('请先在设置中配置 S3-compatible。');
      }
      return S3SyncBackend(
        endpoint: Uri.parse(endpoint),
        bucket: bucket,
        region: preferences.getString('leeef.sync.s3.region') ?? 'us-east-1',
        prefix: preferences.getString('leeef.sync.s3.prefix') ?? 'leeef',
        pathStyle: preferences.getBool('leeef.sync.s3.path_style') ?? true,
        accessKeyId:
            await secureStorage.read(key: 'leeef.sync.s3.access_key_id') ?? '',
        secretAccessKey:
            await secureStorage.read(key: 'leeef.sync.s3.secret_access_key') ??
            '',
        sessionToken: await secureStorage.read(
          key: 'leeef.sync.s3.session_token',
        ),
      );
    default:
      throw StateError('未知同步后端：$kind');
  }
}
