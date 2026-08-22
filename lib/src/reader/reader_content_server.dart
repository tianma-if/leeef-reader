import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

class ReaderContentServer {
  ReaderContentServer({AssetBundle? assetBundle, String? sessionToken})
    : _assetBundle = assetBundle ?? rootBundle,
      _sessionToken = sessionToken ?? _newSessionToken();

  final AssetBundle _assetBundle;
  final String _sessionToken;
  final Map<String, File> _books = {};
  HttpServer? _server;

  bool get isRunning => _server != null;

  Uri get readerUri {
    final server = _requireServer();
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [_sessionToken, 'reader', 'index.html'],
    );
  }

  void registerBook(String bookId, File file) {
    _validateBookId(bookId);
    _books[bookId] = file;
  }

  void unregisterBook(String bookId) => _books.remove(bookId);

  Uri bookUri(String bookId) {
    _validateBookId(bookId);
    if (!_books.containsKey(bookId)) {
      throw StateError('Book $bookId is not registered.');
    }
    final server = _requireServer();
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [_sessionToken, 'books', bookId, 'original'],
    );
  }

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    _books.clear();
    await server?.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request);
      } on Object {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          // The client may have disconnected while a file was streaming.
        }
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _setSecurityHeaders(request.response);
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length < 3 || segments.first != _sessionToken) {
      await _notFound(request.response);
      return;
    }

    if (segments[1] == 'reader') {
      await _serveAsset(request, segments.sublist(2));
      return;
    }
    if (segments[1] == 'foliate-js') {
      await _serveAsset(request, segments.sublist(1));
      return;
    }
    if (segments.length == 4 &&
        segments[1] == 'books' &&
        segments[3] == 'original') {
      await _serveBook(request, segments[2]);
      return;
    }
    await _notFound(request.response);
  }

  Future<void> _serveAsset(HttpRequest request, List<String> segments) async {
    if (segments.isEmpty || segments.any((part) => part == '..')) {
      await _notFound(request.response);
      return;
    }
    final relativePath = segments.join('/');
    final assetKey = relativePath.startsWith('foliate-js/')
        ? 'assets/$relativePath'
        : 'assets/reader/$relativePath';
    try {
      final data = await _assetBundle.load(assetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      request.response.headers.contentType = _contentType(relativePath);
      request.response.contentLength = bytes.length;
      if (request.method == 'GET') request.response.add(bytes);
      await request.response.close();
    } on FlutterError {
      await _notFound(request.response);
    }
  }

  Future<void> _serveBook(HttpRequest request, String bookId) async {
    final file = _books[bookId];
    if (file == null || !await file.exists()) {
      await _notFound(request.response);
      return;
    }

    final fileLength = await file.length();
    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      fileLength,
    );
    if (range == _invalidRange) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$fileLength',
      );
      await request.response.close();
      return;
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? fileLength - 1;
    request.response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    if (range != null) {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$fileLength',
      );
    }
    if (request.method == 'GET') {
      await file.openRead(start, end + 1).pipe(request.response);
    } else {
      await request.response.close();
    }
  }

  static _ByteRange? _parseRange(String? value, int length) {
    if (value == null) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value);
    if (match == null || length == 0) return _invalidRange;
    final startText = match.group(1)!;
    final endText = match.group(2)!;
    if (startText.isEmpty && endText.isEmpty) return _invalidRange;

    late int start;
    late int end;
    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return _invalidRange;
      start = max(0, length - suffixLength);
      end = length - 1;
    } else {
      start = int.tryParse(startText) ?? length;
      end = endText.isEmpty ? length - 1 : int.tryParse(endText) ?? -1;
    }
    if (start < 0 || start >= length || end < start) return _invalidRange;
    return _ByteRange(start, min(end, length - 1));
  }

  static void _setSecurityHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'self'; style-src 'self'; "
            "img-src 'self' blob: data:; font-src 'self' blob: data:; "
            "connect-src 'self' blob:; frame-src blob:; worker-src 'self' blob:",
      );
  }

  static ContentType _contentType(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js')) {
      return ContentType('text', 'javascript', charset: 'utf-8');
    }
    if (path.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    return ContentType.binary;
  }

  static Future<void> _notFound(HttpResponse response) async {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  HttpServer _requireServer() =>
      _server ?? (throw StateError('Reader content server is not running.'));

  static void _validateBookId(String bookId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(bookId)) {
      throw ArgumentError.value(bookId, 'bookId', 'Invalid book ID.');
    }
  }

  static String _newSessionToken() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}

const _invalidRange = _ByteRange(-1, -1);
