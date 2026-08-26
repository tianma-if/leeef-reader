import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';
import 'package:leeef_reader/src/sync/webdav_sync_backend.dart';

void main() {
  late Directory temporaryDirectory;
  late _WebDavTestServer server;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('leeef-webdav-');
    server = await _WebDavTestServer.start();
  });

  tearDown(() async {
    await server.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('verifies required WebDAV capabilities and cleans its probe', () async {
    final backend = WebDavSyncBackend(root: server.root);

    await backend.verifyCapabilities();

    expect(
      server.paths.where((path) => path.contains('.leeef-probe-')),
      isEmpty,
    );
  });

  test('uploads immutable blobs and lists idempotent operations', () async {
    final backend = WebDavSyncBackend(root: server.root);
    final source = File('${temporaryDirectory.path}/book.epub');
    await source.writeAsString('webdav-book');
    final digest = (await sha256.bind(source.openRead()).first).toString();
    final operation = SyncOperation(
      operationId: 'op-1',
      deviceId: 'device-a',
      entityType: EntityType.book,
      entityId: 'book-1',
      kind: OperationKind.upsert,
      occurredAt: DateTime.utc(2026, 8, 26),
      payload: {
        'id': 'book-1',
        'sha256': digest,
        'title': 'WebDAV Book',
        'mediaType': 'application/epub+zip',
      },
    );

    await backend.uploadBlob(digest, source);
    await backend.uploadBlob(digest, source);
    await backend.appendOperation(operation);
    await backend.appendOperation(operation);

    expect(await backend.hasBlob(digest), isTrue);
    expect((await backend.listOperations()).single.operationId, 'op-1');
    final destination = File('${temporaryDirectory.path}/restored.epub');
    await backend.downloadBlob(digest, destination);
    expect(await destination.readAsString(), 'webdav-book');
  });

  test(
    'uses Basic authentication and surfaces authorization failure',
    () async {
      await server.close();
      server = await _WebDavTestServer.start(
        authorization: 'Basic ${base64Encode(utf8.encode('leeef:secret'))}',
      );
      final authorized = WebDavSyncBackend(
        root: server.root,
        username: 'leeef',
        password: 'secret',
      );
      final rejected = WebDavSyncBackend(
        root: server.root,
        username: 'leeef',
        password: 'wrong',
      );

      await authorized.verifyCapabilities();
      await expectLater(
        rejected.verifyCapabilities(),
        throwsA(isA<SyncUnavailable>()),
      );
    },
  );
}

class _WebDavTestServer {
  _WebDavTestServer._(this._server, this._authorization) {
    _directories.add('/dav');
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final String? _authorization;
  final Set<String> _directories = {};
  final Map<String, List<int>> _files = {};
  late final StreamSubscription<HttpRequest> _subscription;

  static Future<_WebDavTestServer> start({String? authorization}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _WebDavTestServer._(server, authorization);
  }

  Uri get root => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    path: '/dav',
  );

  Iterable<String> get paths => {..._directories, ..._files.keys};

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (_authorization != null &&
        request.headers.value(HttpHeaders.authorizationHeader) !=
            _authorization) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    final path = _normalize(request.uri.path);
    switch (request.method) {
      case 'PROPFIND':
        await _propfind(request, path);
      case 'MKCOL':
        if (_directories.contains(path)) {
          request.response.statusCode = HttpStatus.methodNotAllowed;
        } else if (!_directories.contains(_parent(path))) {
          request.response.statusCode = HttpStatus.conflict;
        } else {
          _directories.add(path);
          request.response.statusCode = HttpStatus.created;
        }
        await request.response.close();
      case 'PUT':
        if (!_directories.contains(_parent(path))) {
          request.response.statusCode = HttpStatus.conflict;
        } else if (_files.containsKey(path) &&
            request.headers.value(HttpHeaders.ifNoneMatchHeader) == '*') {
          request.response.statusCode = HttpStatus.preconditionFailed;
        } else {
          _files[path] = await request.fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          );
          request.response.statusCode = HttpStatus.created;
        }
        await request.response.close();
      case 'HEAD':
        request.response.statusCode = _files.containsKey(path)
            ? HttpStatus.ok
            : HttpStatus.notFound;
        await request.response.close();
      case 'GET':
        final bytes = _files[path];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(bytes);
        }
        await request.response.close();
      case 'DELETE':
        final exists = _directories.contains(path) || _files.containsKey(path);
        _directories.removeWhere(
          (candidate) => candidate == path || candidate.startsWith('$path/'),
        );
        _files.removeWhere(
          (candidate, _) => candidate == path || candidate.startsWith('$path/'),
        );
        request.response.statusCode = exists
            ? HttpStatus.noContent
            : HttpStatus.notFound;
        await request.response.close();
      default:
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
    }
  }

  Future<void> _propfind(HttpRequest request, String path) async {
    if (!_directories.contains(path) && !_files.containsKey(path)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final depth = request.headers.value('Depth') ?? '0';
    final entries = <String>[path];
    if (depth == '1' && _directories.contains(path)) {
      entries.addAll(
        _directories.where(
          (candidate) => candidate != path && _parent(candidate) == path,
        ),
      );
      entries.addAll(
        _files.keys.where((candidate) => _parent(candidate) == path),
      );
    }
    final xml = StringBuffer(
      '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">',
    );
    for (final entry in entries) {
      final collection = _directories.contains(entry);
      xml
        ..write('<d:response><d:href>${Uri(path: entry).toString()}')
        ..write(collection ? '/</d:href>' : '</d:href>')
        ..write('<d:propstat><d:prop><d:resourcetype>')
        ..write(collection ? '<d:collection/>' : '')
        ..write('</d:resourcetype></d:prop></d:propstat></d:response>');
    }
    xml.write('</d:multistatus>');
    final bytes = utf8.encode(xml.toString());
    request.response
      ..statusCode = 207
      ..headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      )
      ..add(bytes);
    await request.response.close();
  }

  static String _normalize(String path) => path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;

  static String _parent(String path) {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }
}
