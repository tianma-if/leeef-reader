import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppLog {
  const AppLog._();
  static File? _file;

  static Future<void> initialize() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/leeef/logs');
    await directory.create(recursive: true);
    _file = File('${directory.path}/leeef.log');
    await info('application started');
  }

  static Future<void> info(String message) => _write('INFO', message);
  static Future<void> error(Object error, [StackTrace? stackTrace]) =>
      _write('ERROR', '$error${stackTrace == null ? '' : '\n$stackTrace'}');

  static Future<void> _write(String level, String message) async {
    final file = _file;
    if (file == null) return;
    if (await file.exists() && await file.length() > 1024 * 1024) {
      final old = File('${file.path}.1');
      if (await old.exists()) await old.delete();
      await file.rename(old.path);
    }
    await file.writeAsString(
      '${DateTime.now().toUtc().toIso8601String()} [$level] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<String> read() async {
    final file = _file;
    return file != null && await file.exists() ? file.readAsString() : '';
  }

  static Future<void> clear() async {
    final file = _file;
    if (file != null && await file.exists()) await file.writeAsString('');
  }
}
