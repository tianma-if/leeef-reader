import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

typedef PageCurlReleaseHandler = void Function(PageCurlRelease release);

class PageCurlRelease {
  const PageCurlRelease({
    required this.normalizedVelocity,
    this.forceComplete = false,
  });

  final double normalizedVelocity;
  final bool forceComplete;
}

/// Carries one pointer sequence across the asynchronous page-snapshot gap.
///
/// Hit testing for a pointer is fixed when the finger goes down. The reader
/// therefore keeps receiving moves while [PageCurlSurface] is being inserted,
/// and this controller lets the newly mounted surface catch up immediately.
class PageCurlController extends ChangeNotifier {
  Offset? _origin;
  Size _size = Size.zero;
  double _direction = 1;
  double _progress = 0;
  double _touchY = 0.88;
  PageCurlReleaseHandler? _releaseHandler;
  PageCurlRelease? _pendingRelease;

  double get progress => _progress;
  double get touchY => _touchY;

  void begin({
    required Offset position,
    required Size size,
    required double direction,
  }) {
    _origin = position;
    _size = size;
    _direction = direction.sign == 0 ? 1 : direction.sign;
    // Reveal a small lifted corner as soon as the snapshot is ready, even if
    // the pointer has not moved yet. Subsequent updates remain fully tied to
    // the finger's horizontal travel.
    _progress = 0.018;
    _touchY = _normalizeY(position.dy);
    _pendingRelease = null;
    notifyListeners();
  }

  void update(Offset position) {
    final origin = _origin;
    if (origin == null || _size.width <= 0) return;
    final travel = (origin.dx - position.dx) * _direction;
    _progress = (travel / (_size.width * 0.86)).clamp(0.0, 1.0);
    _touchY = _normalizeY(position.dy);
    notifyListeners();
  }

  void release({
    required double horizontalVelocity,
    bool forceComplete = false,
  }) {
    final release = PageCurlRelease(
      normalizedVelocity: horizontalVelocity * _direction,
      forceComplete: forceComplete,
    );
    final handler = _releaseHandler;
    if (handler == null) {
      _pendingRelease = release;
    } else {
      handler(release);
    }
  }

  void setProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void attach(PageCurlReleaseHandler handler) {
    _releaseHandler = handler;
    final pending = _pendingRelease;
    if (pending != null) {
      _pendingRelease = null;
      scheduleMicrotask(() {
        if (_releaseHandler == handler) handler(pending);
      });
    }
  }

  void detach(PageCurlReleaseHandler handler) {
    if (_releaseHandler == handler) _releaseHandler = null;
  }

  double _normalizeY(double y) {
    if (_size.height <= 0) return 0.88;
    return (y / _size.height).clamp(0.08, 0.96);
  }
}
