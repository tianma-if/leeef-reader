import 'dart:async';

import 'package:flutter/widgets.dart';

typedef StartupErrorHandler =
    FutureOr<void> Function(
      String service,
      Object error,
      StackTrace stackTrace,
    );

class StartupInitializer {
  const StartupInitializer(this.name, this.initialize);

  final String name;
  final Future<void> Function() initialize;
}

/// Starts optional platform services without holding the Android/iOS splash
/// screen open. The app's first frame is rendered before any plugin setup is
/// attempted, and one failing service cannot prevent the others from starting.
class AppStartupHost extends StatefulWidget {
  const AppStartupHost({
    required this.initialize,
    required this.child,
    super.key,
  });

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<AppStartupHost> createState() => _AppStartupHostState();
}

class _AppStartupHostState extends State<AppStartupHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.initialize());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> runStartupInitializers(
  Iterable<StartupInitializer> initializers, {
  required StartupErrorHandler onError,
}) => Future.wait(
  initializers.map((initializer) async {
    try {
      await initializer.initialize();
    } on Object catch (error, stackTrace) {
      await onError(initializer.name, error, stackTrace);
    }
  }),
);
