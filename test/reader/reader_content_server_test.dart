import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/reader/reader_content_server.dart';

void main() {
  late Directory temporaryDirectory;
  late File book;
  late ReaderContentServer server;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leeef-reader-test-',
    );
    book = File('${temporaryDirectory.path}/fixture.epub');
    await book.writeAsBytes(List<int>.generate(32, (index) => index));
    server = ReaderContentServer(sessionToken: 'test-session-token');
    server.registerBook('book-1', book);
    await server.start();
  });

  tearDown(() async {
    await server.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('serves only registered books behind the session token', () async {
    final response = await _get(server.bookUri('book-1'));

    expect(response.statusCode, HttpStatus.ok);
    expect(response.bytes, List<int>.generate(32, (index) => index));
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');

    final unauthorized = await _get(
      server
          .bookUri('book-1')
          .replace(
            pathSegments: ['wrong-token', 'books', 'book-1', 'original'],
          ),
    );
    expect(unauthorized.statusCode, HttpStatus.notFound);
  });

  test('supports byte ranges required by the EPUB zip loader', () async {
    final response = await _get(
      server.bookUri('book-1'),
      headers: {HttpHeaders.rangeHeader: 'bytes=4-9'},
    );

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.bytes, [4, 5, 6, 7, 8, 9]);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 4-9/32',
    );
  });

  test('rejects invalid and out-of-bounds ranges', () async {
    final response = await _get(
      server.bookUri('book-1'),
      headers: {HttpHeaders.rangeHeader: 'bytes=99-100'},
    );

    expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes */32',
    );
  });

  test('rejects unsafe book identifiers before routing', () {
    expect(() => server.registerBook('../secret', book), throwsArgumentError);
    expect(() => server.bookUri('a/b'), throwsArgumentError);
  });
}

Future<_Response> _get(
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return _Response(response.statusCode, response.headers, bytes);
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response(this.statusCode, this.headers, this.bytes);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}
