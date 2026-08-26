import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class AppProxy {
  const AppProxy._();

  static const hostKey = 'leeef.network.proxy_host';
  static const portKey = 'leeef.network.proxy_port';

  static Future<void> initialize() async {
    final values = await SharedPreferences.getInstance();
    apply(values.getString(hostKey), values.getInt(portKey));
  }

  static void apply(String? host, int? port) {
    final normalized = host?.trim();
    HttpOverrides.global =
        normalized == null || normalized.isEmpty || port == null
        ? null
        : _ProxyOverrides(normalized, port);
  }
}

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.host, this.port);
  final String host;
  final int port;

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      'PROXY $host:$port; DIRECT';
}
