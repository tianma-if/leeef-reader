import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

class OpdsEntry {
  const OpdsEntry({
    required this.id,
    required this.title,
    this.author,
    this.summary,
    this.navigationUri,
    this.acquisitionUri,
    this.coverUri,
    this.mediaType,
  });
  final String id;
  final String title;
  final String? author;
  final String? summary;
  final Uri? navigationUri;
  final Uri? acquisitionUri;
  final Uri? coverUri;
  final String? mediaType;
}

class OpdsFeed {
  const OpdsFeed({required this.title, required this.entries, this.nextUri});
  final String title;
  final List<OpdsEntry> entries;
  final Uri? nextUri;
}

class OpdsService {
  OpdsService({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  Future<OpdsFeed> load(Uri uri, {String? username, String? password}) async {
    final request = await _client.getUrl(uri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/atom+xml;profile=opds-catalog, application/xml;q=0.9',
    );
    if (username?.isNotEmpty ?? false) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('$username:${password ?? ''}'))}',
      );
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'OPDS returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    return parse(utf8.decode(bytes, allowMalformed: true), baseUri: uri);
  }

  OpdsFeed parse(String xml, {required Uri baseUri}) {
    final document = XmlDocument.parse(xml);
    final root = document.rootElement;
    if (root.name.local != 'feed') {
      throw const FormatException('OPDS document is not an Atom feed.');
    }
    String? childText(XmlElement element, String name) => element.childElements
        .where((child) => child.name.local == name)
        .map((child) => child.innerText.trim())
        .where((text) => text.isNotEmpty)
        .firstOrNull;
    Uri? link(
      XmlElement element,
      bool Function(String rel, String type) accepts,
    ) {
      for (final child in element.childElements.where(
        (item) => item.name.local == 'link',
      )) {
        final rel = child.getAttribute('rel') ?? '';
        final type = child.getAttribute('type') ?? '';
        final href = child.getAttribute('href');
        if (href != null && accepts(rel, type)) return baseUri.resolve(href);
      }
      return null;
    }

    final entries = <OpdsEntry>[];
    for (final entry in root.childElements.where(
      (item) => item.name.local == 'entry',
    )) {
      final acquisition = link(entry, (rel, _) => rel.contains('acquisition'));
      final navigation = link(
        entry,
        (rel, type) =>
            !rel.contains('acquisition') &&
            (type.contains('atom+xml') || rel == 'subsection'),
      );
      final cover = link(entry, (rel, _) => rel.contains('image'));
      String? mediaType;
      if (acquisition != null) {
        for (final child in entry.childElements.where(
          (item) => item.name.local == 'link',
        )) {
          if (child.getAttribute('href') != null &&
              baseUri.resolve(child.getAttribute('href')!) == acquisition) {
            mediaType = child.getAttribute('type');
            break;
          }
        }
      }
      final authors = entry.childElements
          .where((item) => item.name.local == 'author')
          .map((author) => childText(author, 'name'))
          .whereType<String>();
      entries.add(
        OpdsEntry(
          id:
              childText(entry, 'id') ??
              acquisition?.toString() ??
              navigation?.toString() ??
              childText(entry, 'title') ??
              '',
          title: childText(entry, 'title') ?? '未命名条目',
          author: authors.isEmpty ? null : authors.join(', '),
          summary: childText(entry, 'summary') ?? childText(entry, 'content'),
          navigationUri: navigation,
          acquisitionUri: acquisition,
          coverUri: cover,
          mediaType: mediaType,
        ),
      );
    }
    return OpdsFeed(
      title: childText(root, 'title') ?? baseUri.host,
      entries: entries,
      nextUri: link(root, (rel, _) => rel.split(' ').contains('next')),
    );
  }

  Future<File> download(
    OpdsEntry entry,
    Directory destination, {
    String? username,
    String? password,
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = entry.acquisitionUri;
    if (uri == null) {
      throw StateError('This OPDS entry has no acquisition link.');
    }
    final request = await _client.getUrl(uri);
    if (username?.isNotEmpty ?? false) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('$username:${password ?? ''}'))}',
      );
    }
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException(
        'Download returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    await destination.create(recursive: true);
    final extension = _extensionFor(entry.mediaType, uri.path);
    final safeName = entry.title.replaceAll(
      RegExp(r'[^\w\u4e00-\u9fff.-]+'),
      '_',
    );
    final file = File(
      '${destination.path}/${safeName.isEmpty ? 'opds-book' : safeName}.$extension',
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          received,
          response.contentLength < 0 ? null : response.contentLength,
        );
      }
      await sink.flush();
      await sink.close();
      return file;
    } on Object {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  static String _extensionFor(String? mediaType, String path) {
    const types = {
      'application/epub+zip': 'epub',
      'application/pdf': 'pdf',
      'text/plain': 'txt',
      'application/x-mobipocket-ebook': 'mobi',
      'application/vnd.amazon.ebook': 'azw3',
      'application/x-fictionbook+xml': 'fb2',
    };
    if (types[mediaType] case final extension?) return extension;
    final match = RegExp(r'\.([a-zA-Z0-9]{2,5})$').firstMatch(path);
    return match?.group(1)?.toLowerCase() ?? 'epub';
  }

  void close() => _client.close(force: true);
}
