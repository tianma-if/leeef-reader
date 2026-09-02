import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/app_startup.dart';

void main() {
  testWidgets('renders the app before startup services complete', (
    tester,
  ) async {
    final initialization = Completer<void>();
    var started = false;

    await tester.pumpWidget(
      AppStartupHost(
        initialize: () {
          started = true;
          return initialization.future;
        },
        child: const MaterialApp(home: Text('Leeef Reader ready')),
      ),
    );

    expect(find.text('Leeef Reader ready'), findsOneWidget);
    expect(started, isTrue);

    initialization.complete();
    await tester.pump();
  });

  test('starts services independently and contains failures', () async {
    final slow = Completer<void>();
    final started = <String>[];
    final errors = <String>[];

    final initialization = runStartupInitializers([
      StartupInitializer('slow', () {
        started.add('slow');
        return slow.future;
      }),
      StartupInitializer('failed', () async {
        started.add('failed');
        throw StateError('unavailable');
      }),
      StartupInitializer('ready', () async {
        started.add('ready');
      }),
    ], onError: (service, _, _) => errors.add(service));

    await Future<void>.delayed(Duration.zero);
    expect(started, ['slow', 'failed', 'ready']);
    expect(errors, ['failed']);

    slow.complete();
    await initialization;
  });
}
