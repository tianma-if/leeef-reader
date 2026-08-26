import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/background_sync_scheduler.dart';

void main() {
  test('Windows periodic task safely quotes executable paths', () {
    final arguments = windowsBackgroundTaskArguments(
      enabled: true,
      executable: r'C:\Program Files\Leeef Reader\leeef_reader.exe',
    );

    expect(arguments, containsAllInOrder(['/SC', 'MINUTE', '/MO', '30']));
    expect(
      arguments[arguments.indexOf('/TR') + 1],
      r'"C:\Program Files\Leeef Reader\leeef_reader.exe" --background-sync',
    );
    expect(arguments, contains(windowsBackgroundSyncTaskName));
  });

  test('Windows disabled task requests deletion', () {
    expect(
      windowsBackgroundTaskArguments(enabled: false, executable: 'ignored'),
      const ['/Delete', '/TN', windowsBackgroundSyncTaskName, '/F'],
    );
  });
}
