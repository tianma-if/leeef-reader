import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUrl,
  });
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final Uri releaseUrl;
  bool get updateAvailable =>
      _compareVersions(latestVersion, currentVersion) > 0;

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) => value
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();
    final a = parts(left);
    final b = parts(right);
    for (
      var index = 0;
      index < (a.length > b.length ? a.length : b.length);
      index++
    ) {
      final result = (index < a.length ? a[index] : 0).compareTo(
        index < b.length ? b[index] : 0,
      );
      if (result != 0) return result;
    }
    return 0;
  }
}

class AppUpdateService {
  const AppUpdateService();

  Future<AppUpdateInfo> check() async {
    final package = await PackageInfo.fromPlatform();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(
        Uri.https(
          'api.github.com',
          '/repos/tianma-if/leeef-reader/releases/latest',
        ),
      );
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Leeef-Reader/${package.version}');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub Releases 返回 ${response.statusCode}');
      }
      final json =
          jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;
      return AppUpdateInfo(
        currentVersion: package.version,
        latestVersion: json['tag_name'] as String? ?? package.version,
        releaseNotes: json['body'] as String? ?? '此版本没有变更说明。',
        releaseUrl: Uri.parse(
          json['html_url'] as String? ??
              'https://github.com/tianma-if/leeef-reader/releases',
        ),
      );
    } finally {
      client.close(force: true);
    }
  }
}
