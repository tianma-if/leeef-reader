import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';

class WebDavSyncBackend implements SyncBackend {
  WebDavSyncBackend({
    required Uri root,
    String? username,
    String? password,
    HttpClient Function()? clientFactory,
  }) : root = _normalizeRoot(root),
       _authorization = username == null || username.isEmpty
           ? null
           : 'Basic ${base64Encode(utf8.encode('$username:${password ?? ''}'))}',
       _clientFactory = clientFactory ?? HttpClient.new;

  final Uri root;
  final String? _authorization;
  final HttpClient Function() _clientFactory;

  @override
  Future<void> uploadBlob(String sha256, File source) async {
    _validateSegment(sha256, 'sha256');
    await _verifyDigest(source, sha256);
    final relativePath = 'blobs/$sha256/original';
    if (await hasBlob(sha256)) {
      final bytes = await _get(relativePath);
      if (crypto.sha256.convert(bytes).toString() != sha256.toLowerCase()) {
        throw SyncIntegrityException('Remote blob $sha256 is corrupt.');
      }
      return;
    }
    await _ensureCollection('blobs/$sha256');
    final response = await _request(
      'PUT',
      relativePath,
      headers: {HttpHeaders.ifNoneMatchHeader: '*'},
      body: source.openRead(),
      contentLength: await source.length(),
    );
    if (response.statusCode == HttpStatus.preconditionFailed) {
      final bytes = await _get(relativePath);
      if (crypto.sha256.convert(bytes).toString() != sha256.toLowerCase()) {
        throw SyncIntegrityException('Remote blob $sha256 is corrupt.');
      }
      return;
    }
    _expect(response, const {
      HttpStatus.created,
      HttpStatus.noContent,
    }, 'upload blob');
  }

  @override
  Future<bool> hasBlob(String sha256) async {
    _validateSegment(sha256, 'sha256');
    final response = await _request('HEAD', 'blobs/$sha256/original');
    if (response.statusCode == HttpStatus.notFound) return false;
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.noContent,
    }, 'probe blob');
    return true;
  }

  @override
  Future<void> downloadBlob(String sha256, File destination) async {
    _validateSegment(sha256, 'sha256');
    final bytes = await _get('blobs/$sha256/original');
    if (crypto.sha256.convert(bytes).toString() != sha256.toLowerCase()) {
      throw SyncIntegrityException('Downloaded blob $sha256 is corrupt.');
    }
    await destination.parent.create(recursive: true);
    final staging = File(
      '${destination.path}.webdav-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await staging.writeAsBytes(bytes, flush: true);
      if (await destination.exists()) await destination.delete();
      await staging.rename(destination.path);
    } on Object {
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
  }

  @override
  Future<void> appendOperation(SyncOperation operation) async {
    _validateSegment(operation.deviceId, 'deviceId');
    _validateSegment(operation.operationId, 'operationId');
    await _ensureCollection('ops/${operation.deviceId}');
    final relativePath =
        'ops/${operation.deviceId}/${operation.operationId}.json';
    final bytes = utf8.encode(jsonEncode(operation.toJson()));
    final response = await _request(
      'PUT',
      relativePath,
      headers: {
        HttpHeaders.ifNoneMatchHeader: '*',
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
      body: Stream.value(bytes),
      contentLength: bytes.length,
    );
    if (response.statusCode == HttpStatus.preconditionFailed) {
      final existing = SyncOperation.fromJson(
        Map<String, Object?>.from(
          jsonDecode(utf8.decode(await _get(relativePath))) as Map,
        ),
      );
      if (existing.operationId != operation.operationId) {
        throw SyncIntegrityException(
          'Operation path ${operation.operationId} contains different data.',
        );
      }
      return;
    }
    _expect(response, const {
      HttpStatus.created,
      HttpStatus.noContent,
    }, 'append operation');
  }

  @override
  Future<List<SyncOperation>> listOperations() async {
    final rootResponse = await _request(
      'PROPFIND',
      'ops',
      headers: {'Depth': '1'},
    );
    if (rootResponse.statusCode == HttpStatus.notFound) return const [];
    _expect(rootResponse, const {207}, 'list operation devices');
    final deviceCollections = _davEntries(rootResponse)
        .where((entry) => entry.isCollection && entry.relativePath != 'ops')
        .map((entry) => entry.relativePath)
        .toList();
    final operations = <SyncOperation>[];
    for (final collection in deviceCollections) {
      final response = await _request(
        'PROPFIND',
        collection,
        headers: {'Depth': '1'},
      );
      _expect(response, const {207}, 'list operations');
      final paths = _davEntries(response)
          .where(
            (entry) =>
                !entry.isCollection && entry.relativePath.endsWith('.json'),
          )
          .map((entry) => entry.relativePath);
      for (final path in paths) {
        final decoded = jsonDecode(utf8.decode(await _get(path)));
        if (decoded is! Map) {
          throw const SyncIntegrityException('Invalid WebDAV operation JSON.');
        }
        operations.add(
          SyncOperation.fromJson(Map<String, Object?>.from(decoded)),
        );
      }
    }
    operations.sort((left, right) {
      final time = left.occurredAt.compareTo(right.occurredAt);
      return time != 0 ? time : left.operationId.compareTo(right.operationId);
    });
    return operations;
  }

  Future<void> verifyCapabilities() async {
    final rootResponse = await _request(
      'PROPFIND',
      '',
      headers: {'Depth': '0'},
    );
    _expect(rootResponse, const {207}, 'read sync root');
    final probe = '.leeef-probe-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final collection = await _request('MKCOL', probe);
      _expect(collection, const {HttpStatus.created}, 'create collection');
      final payload = utf8.encode('leeef-webdav-probe');
      final upload = await _request(
        'PUT',
        '$probe/value',
        headers: {HttpHeaders.ifNoneMatchHeader: '*'},
        body: Stream.value(payload),
        contentLength: payload.length,
      );
      _expect(upload, const {
        HttpStatus.created,
        HttpStatus.noContent,
      }, 'conditional upload');
      final downloaded = await _get('$probe/value');
      if (utf8.decode(downloaded) != 'leeef-webdav-probe') {
        throw const SyncIntegrityException('WebDAV probe content changed.');
      }
      final listing = await _request(
        'PROPFIND',
        probe,
        headers: {'Depth': '1'},
      );
      _expect(listing, const {207}, 'list collection');
    } finally {
      final deletion = await _request('DELETE', probe);
      if (deletion.statusCode != HttpStatus.noContent &&
          deletion.statusCode != HttpStatus.notFound &&
          deletion.statusCode != HttpStatus.ok) {
        throw SyncUnavailable(
          'delete capability probe returned HTTP ${deletion.statusCode}',
        );
      }
    }
  }

  Future<void> _ensureCollection(String relativePath) async {
    var current = '';
    for (final segment in relativePath.split('/')) {
      _validateSegment(segment, 'collection');
      current = current.isEmpty ? segment : '$current/$segment';
      final response = await _request('MKCOL', current);
      if (response.statusCode == HttpStatus.methodNotAllowed ||
          response.statusCode == HttpStatus.conflict) {
        if (response.statusCode == HttpStatus.conflict) {
          throw SyncUnavailable('parent collection for $current is missing');
        }
        continue;
      }
      _expect(response, const {HttpStatus.created}, 'create collection');
    }
  }

  Future<List<int>> _get(String relativePath) async {
    final response = await _request('GET', relativePath);
    _expect(response, const {HttpStatus.ok}, 'download object');
    return response.body;
  }

  Future<_DavResponse> _request(
    String method,
    String relativePath, {
    Map<String, String> headers = const {},
    Stream<List<int>>? body,
    int? contentLength,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client.openUrl(method, _uri(relativePath));
      request.followRedirects = false;
      if (_authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, _authorization);
      }
      headers.forEach(request.headers.set);
      if (contentLength != null) request.contentLength = contentLength;
      if (body != null) await request.addStream(body);
      final response = await request.close();
      final responseBody = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      return _DavResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: responseBody,
      );
    } on SyncUnavailable {
      rethrow;
    } on Object catch (error) {
      throw SyncUnavailable('$method ${_uri(relativePath)} failed: $error');
    } finally {
      client.close(force: true);
    }
  }

  Uri _uri(String relativePath) {
    final segments = relativePath.isEmpty
        ? const <String>[]
        : relativePath.split('/');
    return root.replace(
      pathSegments: [
        ...root.pathSegments.where((part) => part.isNotEmpty),
        ...segments,
      ],
      query: null,
      fragment: null,
    );
  }

  List<_DavEntry> _davEntries(_DavResponse response) {
    final xml = utf8.decode(response.body, allowMalformed: true);
    final blocks = RegExp(
      r'<(?:[A-Za-z_][\w.-]*:)?response\b[^>]*>([\s\S]*?)</(?:[A-Za-z_][\w.-]*:)?response>',
      caseSensitive: false,
    ).allMatches(xml);
    final entries = <_DavEntry>[];
    for (final block in blocks) {
      final content = block.group(1)!;
      final hrefMatch = RegExp(
        r'<(?:[A-Za-z_][\w.-]*:)?href\b[^>]*>([\s\S]*?)</(?:[A-Za-z_][\w.-]*:)?href>',
        caseSensitive: false,
      ).firstMatch(content);
      if (hrefMatch == null) continue;
      final href = _decodeXml(hrefMatch.group(1)!.trim());
      final relative = _relativeDavPath(Uri.parse(href).path);
      if (relative == null) continue;
      entries.add(
        _DavEntry(
          relativePath: relative,
          isCollection: RegExp(
            r'<(?:[A-Za-z_][\w.-]*:)?collection\b',
            caseSensitive: false,
          ).hasMatch(content),
        ),
      );
    }
    return entries;
  }

  String? _relativeDavPath(String path) {
    final rootParts = root.pathSegments
        .where((part) => part.isNotEmpty)
        .toList();
    final parts = Uri(
      path: path,
    ).pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length < rootParts.length) return null;
    for (var index = 0; index < rootParts.length; index++) {
      if (parts[index] != rootParts[index]) return null;
    }
    return parts.skip(rootParts.length).join('/');
  }

  static void _expect(_DavResponse response, Set<int> expected, String action) {
    if (expected.contains(response.statusCode)) return;
    final detail = utf8.decode(response.body, allowMalformed: true).trim();
    final abbreviated = detail.length > 200 ? detail.substring(0, 200) : detail;
    throw SyncUnavailable(
      '$action returned HTTP ${response.statusCode}'
      '${detail.isEmpty ? '' : ': $abbreviated'}',
    );
  }

  static Uri _normalizeRoot(Uri root) {
    if (root.scheme != 'http' && root.scheme != 'https') {
      throw ArgumentError.value(
        root,
        'root',
        'Expected an HTTP(S) WebDAV URL.',
      );
    }
    if (!root.hasAuthority || root.host.isEmpty) {
      throw ArgumentError.value(root, 'root', 'WebDAV URL has no host.');
    }
    return root.replace(query: null, fragment: null);
  }

  static void _validateSegment(String value, String name) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Unsafe WebDAV path segment.');
    }
  }

  static String _decodeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  static Future<void> _verifyDigest(File file, String expected) async {
    if (!await file.exists()) {
      throw SyncIntegrityException('Missing file ${file.path}.');
    }
    final actual = (await crypto.sha256.bind(file.openRead()).first).toString();
    if (actual != expected.toLowerCase()) {
      throw SyncIntegrityException(
        'SHA-256 mismatch for ${file.path}: expected $expected, got $actual.',
      );
    }
  }
}

class _DavResponse {
  const _DavResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final List<int> body;
}

class _DavEntry {
  const _DavEntry({required this.relativePath, required this.isCollection});

  final String relativePath;
  final bool isCollection;
}
