import 'dart:convert';
import 'dart:io';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';

class S3SyncBackend implements SyncBackend, SyncDocumentBackend {
  S3SyncBackend({
    required Uri endpoint,
    required this.bucket,
    required this.region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    this.prefix = 'leeef',
    this.pathStyle = true,
  }) : endpoint = _normalizeEndpoint(endpoint),
       _signer = AWSSigV4Signer(
         credentialsProvider: AWSCredentialsProvider(
           AWSCredentials(accessKeyId, secretAccessKey, sessionToken),
         ),
       ) {
    _validateSegment(bucket, 'bucket', allowDots: true);
    _validateSegment(region, 'region');
    for (final segment in _prefixSegments) {
      _validateSegment(segment, 'prefix');
    }
    if (accessKeyId.isEmpty || secretAccessKey.isEmpty) {
      throw ArgumentError('S3 access key and secret key are required.');
    }
  }

  final Uri endpoint;
  final String bucket;
  final String region;
  final String prefix;
  final bool pathStyle;
  final AWSSigV4Signer _signer;
  final S3ServiceConfiguration _serviceConfiguration = S3ServiceConfiguration(
    signPayload: false,
  );

  List<String> get _prefixSegments => prefix
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);

  String _key(String relativePath) => [
    ..._prefixSegments,
    ...relativePath.split('/').where((part) => part.isNotEmpty),
  ].join('/');

  @override
  Future<void> uploadBlob(String sha256, File source) async {
    _validateHash(sha256);
    await _verifyDigest(source, sha256);
    final key = _key('blobs/$sha256/original');
    if (await hasBlob(sha256)) {
      await _verifyRemoteBlob(key, sha256);
      return;
    }
    final response = await _request(
      AWSHttpMethod.put,
      key: key,
      headers: {HttpHeaders.ifNoneMatchHeader: '*'},
      body: source.openRead(),
      contentLength: await source.length(),
    );
    if (response.statusCode == HttpStatus.preconditionFailed) {
      await _verifyRemoteBlob(key, sha256);
      return;
    }
    if (response.statusCode == HttpStatus.conflict) {
      if (await hasBlob(sha256)) {
        await _verifyRemoteBlob(key, sha256);
        return;
      }
    }
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.created,
      HttpStatus.noContent,
    }, 'upload blob');
  }

  @override
  Future<bool> hasBlob(String sha256) async {
    _validateHash(sha256);
    final response = await _request(
      AWSHttpMethod.head,
      key: _key('blobs/$sha256/original'),
    );
    if (response.statusCode == HttpStatus.notFound) return false;
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.noContent,
    }, 'probe blob');
    return true;
  }

  @override
  Future<void> downloadBlob(String sha256, File destination) async {
    _validateHash(sha256);
    final response = await _request(
      AWSHttpMethod.get,
      key: _key('blobs/$sha256/original'),
    );
    _expect(response, const {HttpStatus.ok}, 'download blob');
    if (crypto.sha256.convert(response.body).toString() !=
        sha256.toLowerCase()) {
      throw SyncIntegrityException('Downloaded S3 blob $sha256 is corrupt.');
    }
    await destination.parent.create(recursive: true);
    final staging = File(
      '${destination.path}.s3-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await staging.writeAsBytes(response.body, flush: true);
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
    final key = _key('ops/${operation.deviceId}/${operation.operationId}.json');
    final bytes = utf8.encode(jsonEncode(operation.toJson()));
    final response = await _request(
      AWSHttpMethod.put,
      key: key,
      headers: {
        HttpHeaders.ifNoneMatchHeader: '*',
        AWSHeaders.contentType: 'application/json; charset=utf-8',
      },
      body: Stream.value(bytes),
      contentLength: bytes.length,
    );
    if (response.statusCode == HttpStatus.preconditionFailed) {
      final existing = await _getOperation(key);
      if (existing.operationId != operation.operationId) {
        throw SyncIntegrityException(
          'S3 operation ${operation.operationId} contains different data.',
        );
      }
      return;
    }
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.created,
      HttpStatus.noContent,
    }, 'append operation');
  }

  @override
  Future<List<SyncOperation>> listOperations() async {
    final keys = await _listKeys('${_key('ops')}/');
    final operations = <SyncOperation>[];
    for (final key in keys.where((key) => key.endsWith('.json'))) {
      operations.add(await _getOperation(key));
    }
    operations.sort((left, right) {
      final time = left.occurredAt.compareTo(right.occurredAt);
      return time != 0 ? time : left.operationId.compareTo(right.operationId);
    });
    return operations;
  }

  @override
  Future<void> writeDocument(String path, List<int> bytes) async {
    _validateDocumentPath(path);
    final response = await _request(
      AWSHttpMethod.put,
      key: _key(path),
      headers: {AWSHeaders.contentType: 'application/json; charset=utf-8'},
      body: Stream.value(bytes),
      contentLength: bytes.length,
    );
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.created,
      HttpStatus.noContent,
    }, 'write document');
  }

  @override
  Future<bool> writeDocumentIfAbsent(String path, List<int> bytes) async {
    _validateDocumentPath(path);
    final response = await _request(
      AWSHttpMethod.put,
      key: _key(path),
      headers: {
        HttpHeaders.ifNoneMatchHeader: '*',
        AWSHeaders.contentType: 'application/json; charset=utf-8',
      },
      body: Stream.value(bytes),
      contentLength: bytes.length,
    );
    if (response.statusCode == HttpStatus.preconditionFailed ||
        response.statusCode == HttpStatus.conflict) {
      return false;
    }
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.created,
      HttpStatus.noContent,
    }, 'write document if absent');
    return true;
  }

  @override
  Future<List<int>?> readDocument(String path) async {
    _validateDocumentPath(path);
    final response = await _request(AWSHttpMethod.get, key: _key(path));
    if (response.statusCode == HttpStatus.notFound) return null;
    _expect(response, const {HttpStatus.ok}, 'read document');
    return response.body;
  }

  @override
  Future<List<String>> listDocuments(String prefixPath) async {
    _validateDocumentPath(prefixPath);
    final storagePrefix = _key(prefixPath);
    final rootPrefix = _key('');
    final offset = rootPrefix.isEmpty ? 0 : rootPrefix.length + 1;
    final keys = await _listKeys(
      storagePrefix.endsWith('/') ? storagePrefix : '$storagePrefix/',
    );
    return keys.map((key) => key.substring(offset)).toList(growable: false)
      ..sort();
  }

  @override
  Future<void> deleteDocument(String path) async {
    _validateDocumentPath(path);
    final response = await _request(AWSHttpMethod.delete, key: _key(path));
    _expect(response, const {
      HttpStatus.ok,
      HttpStatus.noContent,
      HttpStatus.notFound,
    }, 'delete document');
  }

  Future<void> verifyCapabilities() async {
    final probe = _key(
      '.leeef-probe/${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    final payload = utf8.encode('leeef-s3-probe');
    try {
      final upload = await _request(
        AWSHttpMethod.put,
        key: probe,
        headers: {HttpHeaders.ifNoneMatchHeader: '*'},
        body: Stream.value(payload),
        contentLength: payload.length,
      );
      _expect(upload, const {
        HttpStatus.ok,
        HttpStatus.created,
        HttpStatus.noContent,
      }, 'conditional upload');
      final head = await _request(AWSHttpMethod.head, key: probe);
      _expect(head, const {HttpStatus.ok, HttpStatus.noContent}, 'head object');
      final download = await _request(AWSHttpMethod.get, key: probe);
      _expect(download, const {HttpStatus.ok}, 'download object');
      if (utf8.decode(download.body) != 'leeef-s3-probe') {
        throw const SyncIntegrityException('S3 probe content changed.');
      }
      final listed = await _listKeys('${_key('.leeef-probe')}/');
      if (!listed.contains(probe)) {
        throw const SyncUnavailable('S3 list did not return the probe object.');
      }
    } finally {
      final deletion = await _request(AWSHttpMethod.delete, key: probe);
      if (deletion.statusCode != HttpStatus.noContent &&
          deletion.statusCode != HttpStatus.ok &&
          deletion.statusCode != HttpStatus.notFound) {
        throw SyncUnavailable(
          'delete S3 probe returned HTTP ${deletion.statusCode}',
        );
      }
    }
  }

  Future<SyncOperation> _getOperation(String key) async {
    final response = await _request(AWSHttpMethod.get, key: key);
    _expect(response, const {HttpStatus.ok}, 'download operation');
    final decoded = jsonDecode(utf8.decode(response.body));
    if (decoded is! Map) {
      throw const SyncIntegrityException('Invalid S3 operation JSON.');
    }
    return SyncOperation.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> _verifyRemoteBlob(String key, String expected) async {
    final response = await _request(AWSHttpMethod.get, key: key);
    _expect(response, const {HttpStatus.ok}, 'verify remote blob');
    if (crypto.sha256.convert(response.body).toString() !=
        expected.toLowerCase()) {
      throw SyncIntegrityException('Remote S3 blob $expected is corrupt.');
    }
  }

  Future<List<String>> _listKeys(String keyPrefix) async {
    final keys = <String>[];
    String? continuationToken;
    do {
      final query = <String, String>{
        'list-type': '2',
        'encoding-type': 'url',
        'prefix': keyPrefix,
      };
      if (continuationToken case final token?) {
        query['continuation-token'] = token;
      }
      final response = await _request(AWSHttpMethod.get, query: query);
      _expect(response, const {HttpStatus.ok}, 'list objects');
      final xml = utf8.decode(response.body, allowMalformed: true);
      for (final match in RegExp(
        r'<Key>([\s\S]*?)</Key>',
        caseSensitive: false,
      ).allMatches(xml)) {
        keys.add(Uri.decodeComponent(_decodeXml(match.group(1)!.trim())));
      }
      final truncated = RegExp(
        r'<IsTruncated>\s*true\s*</IsTruncated>',
        caseSensitive: false,
      ).hasMatch(xml);
      if (!truncated) {
        continuationToken = null;
      } else {
        final tokenMatch = RegExp(
          r'<NextContinuationToken>([\s\S]*?)</NextContinuationToken>',
          caseSensitive: false,
        ).firstMatch(xml);
        if (tokenMatch == null) {
          throw const SyncIntegrityException(
            'Truncated S3 listing has no continuation token.',
          );
        }
        continuationToken = _decodeXml(tokenMatch.group(1)!.trim());
      }
    } while (continuationToken != null);
    return keys;
  }

  Future<_S3Response> _request(
    AWSHttpMethod method, {
    String? key,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    Stream<List<int>>? body,
    int contentLength = 0,
  }) async {
    final uri = _uri(key: key, query: query);
    final request = AWSStreamedHttpRequest(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      contentLength: contentLength,
      followRedirects: false,
    );
    try {
      final signed = await _signer.sign(
        request,
        credentialScope: AWSCredentialScope(
          region: region,
          service: AWSService.s3,
        ),
        serviceConfiguration: _serviceConfiguration,
      );
      final response = await signed.send().response;
      final bytes = await response.bodyBytes;
      final result = _S3Response(
        statusCode: response.statusCode,
        headers: response.headers,
        body: bytes,
      );
      await response.close();
      return result;
    } on SyncUnavailable {
      rethrow;
    } on Object catch (error) {
      throw SyncUnavailable('${method.value} $uri failed: $error');
    }
  }

  Uri _uri({String? key, Map<String, String> query = const {}}) {
    final endpointSegments = endpoint.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final objectSegments = key == null
        ? const <String>[]
        : key.split('/').where((segment) => segment.isNotEmpty).toList();
    if (pathStyle) {
      return endpoint.replace(
        pathSegments: [...endpointSegments, bucket, ...objectSegments],
        queryParameters: query.isEmpty ? null : query,
      );
    }
    return endpoint.replace(
      host: '$bucket.${endpoint.host}',
      pathSegments: [...endpointSegments, ...objectSegments],
      queryParameters: query.isEmpty ? null : query,
    );
  }

  static void _expect(_S3Response response, Set<int> expected, String action) {
    if (expected.contains(response.statusCode)) return;
    final body = utf8.decode(response.body, allowMalformed: true).trim();
    final detail = body.length > 240 ? body.substring(0, 240) : body;
    throw SyncUnavailable(
      '$action returned HTTP ${response.statusCode}'
      '${detail.isEmpty ? '' : ': $detail'}',
    );
  }

  static Uri _normalizeEndpoint(Uri endpoint) {
    if ((endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Expected an HTTP(S) S3 endpoint.',
      );
    }
    return endpoint.replace(query: null, fragment: null);
  }

  static void _validateHash(String value) {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'sha256', 'Expected 64 hex digits.');
    }
  }

  static void _validateSegment(
    String value,
    String name, {
    bool allowDots = false,
  }) {
    final pattern = allowDots
        ? RegExp(r'^[A-Za-z0-9._-]+$')
        : RegExp(r'^[A-Za-z0-9_-]+$');
    if (value.isEmpty || !pattern.hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Unsafe S3 value.');
    }
  }

  static void _validateDocumentPath(String path) {
    final segments = path.split('/');
    if (segments.isEmpty || segments.any((segment) => segment.isEmpty)) {
      throw ArgumentError.value(path, 'path', 'Invalid storage path.');
    }
    for (final segment in segments) {
      if (segment == '.' || segment == '..') {
        throw ArgumentError.value(path, 'path', 'Unsafe storage path.');
      }
      _validateSegment(segment, 'path', allowDots: true);
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

class _S3Response {
  const _S3Response({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}
