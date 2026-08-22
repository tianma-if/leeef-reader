import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:leeef_reader/src/mcp/mcp_http_client.dart';

class McpSidecar {
  McpSidecar._({
    required Process process,
    required McpHttpClient client,
    required this.endpoint,
    required StreamSubscription<String> stderrSubscription,
  }) : _process = process,
       _client = client,
       _stderrSubscription = stderrSubscription;

  final Process _process;
  final McpHttpClient _client;
  final StreamSubscription<String> _stderrSubscription;
  final Uri endpoint;

  static Future<McpSidecar> start({
    required String executablePath,
    required String databasePath,
  }) async {
    final token = _newToken();
    final process = await Process.start(
      executablePath,
      ['--listen', '127.0.0.1:0', '--database', databasePath],
      environment: {...Platform.environment, 'LEEEF_MCP_TOKEN': token},
    );
    final errors = <String>[];
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(errors.add);
    try {
      final line = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      final message = jsonDecode(line);
      if (message is! Map || message['type'] != 'ready') {
        throw FormatException('Invalid sidecar handshake: $line');
      }
      final endpoint = Uri.parse(message['endpoint'] as String);
      final address = InternetAddress.tryParse(endpoint.host);
      if (endpoint.scheme != 'http' || address == null || !address.isLoopback) {
        throw StateError('Sidecar returned a non-loopback endpoint.');
      }
      final client = McpHttpClient(endpoint: endpoint, token: token);
      await client.initialize();
      return McpSidecar._(
        process: process,
        client: client,
        endpoint: endpoint,
        stderrSubscription: stderrSubscription,
      );
    } on Object {
      process.kill();
      await stderrSubscription.cancel();
      final detail = errors.isEmpty ? '' : ' ${errors.join(' ')}';
      throw StateError('Unable to start leeef-mcp.$detail');
    }
  }

  Future<Map<String, dynamic>> health() => _client.callTool('health');

  Future<Map<String, dynamic>> libraryStats() =>
      _client.callTool('library_stats');

  Future<void> close() async {
    await _client.close();
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill();
    }
    await _stderrSubscription.cancel();
  }

  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
