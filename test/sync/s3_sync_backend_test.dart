import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/sync/s3_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';

void main() {
  late Directory temporaryDirectory;
  late _S3TestServer server;
  late S3SyncBackend backend;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('leeef-s3-');
    server = await _S3TestServer.start(pageSize: 2);
    backend = S3SyncBackend(
      endpoint: server.endpoint,
      bucket: 'library',
      region: 'us-east-1',
      accessKeyId: 'test-access',
      secretAccessKey: 'test-secret',
    );
  });

  tearDown(() async {
    await server.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('verifies signed S3 capabilities and removes the probe', () async {
    await backend.verifyCapabilities();

    expect(server.keys.where((key) => key.contains('.leeef-probe')), isEmpty);
    expect(server.sawSignedRequest, isTrue);
    expect(server.sawContentHash, isTrue);
  });

  test('uploads blobs and paginates idempotent operation listing', () async {
    final source = File('${temporaryDirectory.path}/book.epub');
    await source.writeAsString('s3-compatible-book');
    final digest = (await sha256.bind(source.openRead()).first).toString();

    await backend.uploadBlob(digest, source);
    await backend.uploadBlob(digest, source);
    for (var index = 0; index < 3; index++) {
      final operation = _operation(index);
      await backend.appendOperation(operation);
      await backend.appendOperation(operation);
    }

    expect(await backend.hasBlob(digest), isTrue);
    expect(
      (await backend.listOperations()).map(
        (operation) => operation.operationId,
      ),
      ['op-0', 'op-1', 'op-2'],
    );
    expect(server.listRequestCount, greaterThanOrEqualTo(2));
    final destination = File('${temporaryDirectory.path}/restored.epub');
    await backend.downloadBlob(digest, destination);
    expect(await destination.readAsString(), 's3-compatible-book');
  });

  test('rejects a corrupt remote immutable blob', () async {
    final source = File('${temporaryDirectory.path}/book.epub');
    await source.writeAsString('valid-content');
    final digest = (await sha256.bind(source.openRead()).first).toString();
    server.put('library/leeef/blobs/$digest/original', utf8.encode('corrupt'));

    await expectLater(
      backend.uploadBlob(digest, source),
      throwsA(isA<SyncIntegrityException>()),
    );
  });

  test('stores encrypted sync metadata as small documents', () async {
    final path = 'trusted/space/config/device.json';
    final first = utf8.encode('{"ciphertext":"one"}');
    final second = utf8.encode('{"ciphertext":"two"}');

    expect(await backend.writeDocumentIfAbsent(path, first), isTrue);
    expect(await backend.writeDocumentIfAbsent(path, second), isFalse);
    expect(await backend.readDocument(path), first);
    expect(await backend.listDocuments('trusted/space/config'), [path]);

    await backend.writeDocument(path, second);
    expect(await backend.readDocument(path), second);
    await backend.deleteDocument(path);
    expect(await backend.readDocument(path), isNull);
  });
}

SyncOperation _operation(int index) => SyncOperation(
  operationId: 'op-$index',
  deviceId: 'device-a',
  entityType: EntityType.book,
  entityId: 'book-$index',
  kind: OperationKind.upsert,
  occurredAt: DateTime.utc(2026, 8, 26, 0, index),
  payload: {
    'id': 'book-$index',
    'sha256': '${index + 1}' * 64,
    'title': 'Book $index',
    'mediaType': 'application/epub+zip',
  },
);

class _S3TestServer {
  _S3TestServer._(this._server, this.pageSize) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final int pageSize;
  final Map<String, List<int>> _objects = {};
  late final StreamSubscription<HttpRequest> _subscription;
  bool sawSignedRequest = false;
  bool sawContentHash = false;
  int listRequestCount = 0;

  static Future<_S3TestServer> start({required int pageSize}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _S3TestServer._(server, pageSize);
  }

  Uri get endpoint => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
  );

  Iterable<String> get keys => _objects.keys;

  void put(String key, List<int> bytes) => _objects[key] = bytes;

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    sawSignedRequest =
        sawSignedRequest ||
        (authorization?.startsWith(
              'AWS4-HMAC-SHA256 Credential=test-access/',
            ) ??
            false);
    sawContentHash =
        sawContentHash ||
        request.headers.value('x-amz-content-sha256') == 'UNSIGNED-PAYLOAD';
    if (authorization == null) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final key = request.uri.pathSegments.join('/');
    if (request.method == 'GET' &&
        request.uri.queryParameters['list-type'] == '2') {
      await _list(request);
      return;
    }
    switch (request.method) {
      case 'PUT':
        if (_objects.containsKey(key) &&
            request.headers.value(HttpHeaders.ifNoneMatchHeader) == '*') {
          request.response.statusCode = HttpStatus.preconditionFailed;
        } else {
          _objects[key] = await request.fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          );
          request.response.statusCode = HttpStatus.ok;
        }
      case 'HEAD':
        request.response.statusCode = _objects.containsKey(key)
            ? HttpStatus.ok
            : HttpStatus.notFound;
      case 'GET':
        final bytes = _objects[key];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(bytes);
        }
      case 'DELETE':
        request.response.statusCode = _objects.remove(key) == null
            ? HttpStatus.notFound
            : HttpStatus.noContent;
      default:
        request.response.statusCode = HttpStatus.methodNotAllowed;
    }
    await request.response.close();
  }

  Future<void> _list(HttpRequest request) async {
    listRequestCount++;
    final bucket = request.uri.pathSegments.first;
    final prefix = request.uri.queryParameters['prefix'] ?? '';
    final all =
        _objects.keys
            .where((key) => key.startsWith('$bucket/$prefix'))
            .map((key) => key.substring(bucket.length + 1))
            .toList()
          ..sort();
    final offset =
        int.tryParse(request.uri.queryParameters['continuation-token'] ?? '') ??
        0;
    final page = all.skip(offset).take(pageSize).toList();
    final nextOffset = offset + page.length;
    final truncated = nextOffset < all.length;
    final xml = StringBuffer('<?xml version="1.0"?><ListBucketResult>');
    for (final key in page) {
      xml.write('<Contents><Key>${Uri.encodeComponent(key)}</Key></Contents>');
    }
    xml
      ..write('<IsTruncated>$truncated</IsTruncated>')
      ..write(
        truncated
            ? '<NextContinuationToken>$nextOffset</NextContinuationToken>'
            : '',
      )
      ..write('</ListBucketResult>');
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('application', 'xml')
      ..write(xml.toString());
    await request.response.close();
  }
}
