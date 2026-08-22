import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/mcp/mcp_sidecar.dart';

void main() {
  final executableName = Platform.isWindows ? 'leeef-mcp.exe' : 'leeef-mcp';
  final sidecarExecutable = File('sidecars/leeef-mcp/build/$executableName');

  test(
    'Flutter launches sidecar and reads Drift data through MCP',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'leeef-mcp-verification-',
      );
      try {
        final databasePath = '${temporaryDirectory.path}/leeef.sqlite';
        final database = AppDatabase.forTesting(
          NativeDatabase(File(databasePath)),
        );
        final ids = ['book-1', 'operation-1'].iterator;
        final repository = LibraryRepository(
          database: database,
          deviceId: 'verification-device',
          idGenerator: () {
            ids.moveNext();
            return ids.current;
          },
        );
        await repository.createBookMetadata(
          sha256: 'f' * 64,
          title: 'MCP Verification Book',
          mediaType: 'application/epub+zip',
        );
        await database.close();

        final sidecar = await McpSidecar.start(
          executablePath: sidecarExecutable.absolute.path,
          databasePath: databasePath,
        );
        try {
          final health = await sidecar.health();
          final stats = await sidecar.libraryStats();
          expect(health['status'], 'ok');
          expect(health['databaseConnected'], isTrue);
          expect(stats['books'], 1);
          expect(stats['pendingSyncOperations'], 1);
        } finally {
          await sidecar.close();
        }
      } finally {
        await temporaryDirectory.delete(recursive: true);
      }
    },
    skip: sidecarExecutable.existsSync()
        ? false
        : 'Build sidecars/leeef-mcp before running this test.',
  );
}
