import 'dart:convert';
import 'dart:io';

class McpHttpClient {
  McpHttpClient({required this.endpoint, required this.token});

  final Uri endpoint;
  final String token;
  final HttpClient _httpClient = HttpClient();
  String? _sessionId;
  int _nextRequestId = 1;

  Future<void> initialize() async {
    final response = await _post({
      'jsonrpc': '2.0',
      'id': _nextRequestId++,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-11-25',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'leeef-reader', 'version': '0.1.0'},
      },
    });
    _throwProtocolError(response.body);
    _sessionId = response.headers.value('Mcp-Session-Id');
    if (_sessionId == null || _sessionId!.isEmpty) {
      throw const FormatException('MCP server did not return a session ID.');
    }
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  Future<Map<String, dynamic>> callTool(
    String name, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (_sessionId == null) throw StateError('MCP client is not initialized.');
    final response = await _post({
      'jsonrpc': '2.0',
      'id': _nextRequestId++,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': arguments},
    });
    _throwProtocolError(response.body);
    final result = response.body['result'];
    if (result is! Map) throw const FormatException('Invalid MCP tool result.');
    final resultMap = Map<String, dynamic>.from(result);
    if (resultMap['isError'] == true) {
      throw StateError('MCP tool $name failed: ${resultMap['content']}');
    }
    final structured = resultMap['structuredContent'];
    if (structured is! Map) {
      throw const FormatException('MCP tool returned no structured content.');
    }
    return Map<String, dynamic>.from(structured);
  }

  Future<void> close() async {
    final sessionId = _sessionId;
    _sessionId = null;
    if (sessionId != null) {
      try {
        final request = await _httpClient.deleteUrl(endpoint);
        _setHeaders(request, sessionId: sessionId);
        final response = await request.close();
        await response.drain<void>();
      } on Object {
        // Sidecar teardown must remain best-effort.
      }
    }
    _httpClient.close(force: true);
  }

  Future<_McpResponse> _post(Map<String, Object?> message) async {
    final request = await _httpClient.postUrl(endpoint);
    _setHeaders(request, sessionId: _sessionId);
    request.add(utf8.encode(jsonEncode(message)));
    final response = await request.close();
    final responseText = await utf8.decodeStream(response);
    if (response.statusCode == HttpStatus.accepted && responseText.isEmpty) {
      return _McpResponse(response.headers, const {});
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'MCP request failed (${response.statusCode}): $responseText',
        uri: endpoint,
      );
    }
    final decoded = jsonDecode(responseText);
    if (decoded is! Map) throw const FormatException('Invalid MCP response.');
    return _McpResponse(response.headers, Map<String, dynamic>.from(decoded));
  }

  void _setHeaders(HttpClientRequest request, {String? sessionId}) {
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
    if (sessionId != null) request.headers.set('Mcp-Session-Id', sessionId);
  }

  static void _throwProtocolError(Map<String, dynamic> response) {
    final error = response['error'];
    if (error != null) throw StateError('MCP protocol error: $error');
  }
}

class _McpResponse {
  const _McpResponse(this.headers, this.body);

  final HttpHeaders headers;
  final Map<String, dynamic> body;
}
