import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class EpubMetadata {
  const EpubMetadata({
    this.title,
    this.author,
    this.description,
    this.coverBytes,
    this.coverExtension,
  });

  final String? title;
  final String? author;
  final String? description;
  final List<int>? coverBytes;
  final String? coverExtension;
}

class EpubMetadataExtractor {
  const EpubMetadataExtractor();

  Future<EpubMetadata> extract(File file) async {
    try {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final container = _file(archive, 'META-INF/container.xml');
      if (container == null) return const EpubMetadata();
      final containerXml = XmlDocument.parse(utf8.decode(container.content));
      final rootfile = _elements(containerXml, 'rootfile').firstOrNull;
      final opfPath = rootfile?.getAttribute('full-path');
      if (opfPath == null || opfPath.isEmpty) return const EpubMetadata();
      final opfFile = _file(archive, opfPath);
      if (opfFile == null) return const EpubMetadata();
      final package = XmlDocument.parse(utf8.decode(opfFile.content));
      final title = _elementText(package, 'title');
      final authors = _elements(package, 'creator')
          .map((element) => element.innerText.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final description = _elementText(package, 'description');
      final coverItem = _findCoverItem(package);
      if (coverItem == null) {
        return EpubMetadata(
          title: title,
          author: authors.isEmpty ? null : authors.join('、'),
          description: description,
        );
      }
      final href = coverItem.getAttribute('href');
      final coverPath = href == null ? null : _resolve(opfPath, href);
      final coverFile = coverPath == null ? null : _file(archive, coverPath);
      return EpubMetadata(
        title: title,
        author: authors.isEmpty ? null : authors.join('、'),
        description: description,
        coverBytes: coverFile?.content,
        coverExtension: href == null ? null : _extension(href),
      );
    } on Object {
      // Invalid metadata must not make an otherwise readable EPUB unimportable.
      return const EpubMetadata();
    }
  }

  static Iterable<XmlElement> _elements(XmlNode node, String localName) => node
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName);

  static String? _elementText(XmlNode node, String localName) {
    final value = _elements(node, localName).firstOrNull?.innerText.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static XmlElement? _findCoverItem(XmlDocument package) {
    final manifestItems = _elements(package, 'item').toList();
    for (final item in manifestItems) {
      final properties =
          item.getAttribute('properties')?.split(' ') ?? const [];
      if (properties.contains('cover-image')) return item;
    }
    String? coverId;
    for (final meta in _elements(package, 'meta')) {
      if (meta.getAttribute('name')?.toLowerCase() == 'cover') {
        coverId = meta.getAttribute('content');
        break;
      }
    }
    if (coverId != null) {
      for (final item in manifestItems) {
        if (item.getAttribute('id') == coverId) return item;
      }
    }
    for (final item in manifestItems) {
      final href = item.getAttribute('href')?.toLowerCase() ?? '';
      if (href.contains('cover') && _isImage(item)) return item;
    }
    return null;
  }

  static bool _isImage(XmlElement item) =>
      item.getAttribute('media-type')?.startsWith('image/') ?? false;

  static ArchiveFile? _file(Archive archive, String path) {
    final normalized = Uri.decodeFull(path).replaceAll('\\', '/');
    for (final file in archive.files) {
      if (file.name.replaceAll('\\', '/') == normalized) return file;
    }
    return null;
  }

  static String _resolve(String opfPath, String href) {
    final base = Uri.parse('file:///$opfPath');
    return base.resolve(href).path.substring(1);
  }

  static String _extension(String href) {
    final path = Uri.parse(href).path;
    final dot = path.lastIndexOf('.');
    return dot < 0 ? 'img' : path.substring(dot + 1).toLowerCase();
  }
}
