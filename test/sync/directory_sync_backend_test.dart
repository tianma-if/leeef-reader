import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';

void main() {
  test('conditional document write has a single winner', () async {
    final root = await Directory.systemTemp.createTemp('leeef-doc-race-');
    addTearDown(() => root.delete(recursive: true));
    final backend = DirectorySyncBackend(root);
    const path = 'trusted/space/keys/2.json';

    final results = await Future.wait(
      List.generate(8, (index) => backend.writeDocumentIfAbsent(path, [index])),
    );

    expect(results.where((result) => result), hasLength(1));
    expect(await backend.readDocument(path), hasLength(1));
  });

  test('document paths reject traversal segments', () async {
    final root = await Directory.systemTemp.createTemp('leeef-doc-path-');
    addTearDown(() => root.delete(recursive: true));
    final backend = DirectorySyncBackend(root);

    await expectLater(
      backend.writeDocument('../outside.json', const [1]),
      throwsArgumentError,
    );
  });
}
