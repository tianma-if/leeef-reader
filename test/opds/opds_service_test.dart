import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/opds/opds_service.dart';

void main() {
  test('parses navigation, acquisition, cover, author and next links', () {
    final feed = OpdsService().parse('''
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Books</title><link rel="next" href="page2.xml" />
        <entry><id>folder</id><title>Fiction</title><link rel="subsection" type="application/atom+xml" href="fiction.xml" /></entry>
        <entry><id>book</id><title>A Book</title><author><name>Ada</name></author><summary>Summary</summary>
          <link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="book.epub" />
          <link rel="http://opds-spec.org/image" href="cover.jpg" /></entry>
      </feed>''', baseUri: Uri.parse('https://catalog.example/root/feed.xml'));
    expect(feed.title, 'Books');
    expect(feed.nextUri.toString(), 'https://catalog.example/root/page2.xml');
    expect(
      feed.entries.first.navigationUri.toString(),
      'https://catalog.example/root/fiction.xml',
    );
    expect(feed.entries.last.author, 'Ada');
    expect(feed.entries.last.mediaType, 'application/epub+zip');
    expect(
      feed.entries.last.acquisitionUri.toString(),
      'https://catalog.example/root/book.epub',
    );
  });

  test(
    'loads feed and downloads acquisition with basic authentication',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Basic dXNlcjpwYXNz',
        );
        if (request.uri.path == '/feed') {
          request.response.headers.contentType = ContentType(
            'application',
            'atom+xml',
            charset: 'utf-8',
          );
          request.response.write(
            '<feed xmlns="http://www.w3.org/2005/Atom"><title>T</title><entry><id>b</id><title>B</title><link rel="http://opds-spec.org/acquisition" type="text/plain" href="/book"/></entry></feed>',
          );
        } else {
          request.response.write('downloaded');
        }
        await request.response.close();
      });
      final service = OpdsService();
      addTearDown(service.close);
      final root = Uri.parse(
        'http://${server.address.host}:${server.port}/feed',
      );
      final feed = await service.load(root, username: 'user', password: 'pass');
      final directory = await Directory.systemTemp.createTemp(
        'leeef-opds-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await service.download(
        feed.entries.single,
        directory,
        username: 'user',
        password: 'pass',
      );
      expect(file.path, endsWith('.txt'));
      expect(await file.readAsString(), 'downloaded');
    },
  );
}
