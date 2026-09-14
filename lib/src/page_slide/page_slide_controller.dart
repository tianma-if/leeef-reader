import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:leeef_reader/src/page_slide/page_slide_gesture.dart';

typedef PageSlideReleaseHandler = void Function(PageSlideRelease release);

class PageSlideRelease {
  const PageSlideRelease({
    required this.normalizedVelocity,
    this.forceComplete = false,
    this.alongPixels = 0,
  });

  final double normalizedVelocity;
  final bool forceComplete;
  final double alongPixels;
}

/// Carries one pointer sequence across the asynchronous page-snapshot gap.
///
/// Hit testing for a pointer is fixed when the finger goes down. The reader
/// therefore keeps receiving moves while [PageSlideSurface] is being inserted,
/// and this controller lets the newly mounted surface catch up immediately.
class PageSlideController extends ChangeNotifier {
  Offset? _origin;
  Offset? _latest;
  Size _size = Size.zero;
  double _direction = 1;
  double _progress = 0;
  PageSlideReleaseHandler? _releaseHandler;
  PageSlideRelease? _pendingRelease;

  double get progress => _progress;

  void begin({
    required Offset position,
    required Size size,
    required double direction,
  }) {
    _origin = position;
    _latest = position;
    _size = size;
    _direction = direction.sign == 0 ? 1 : direction.sign;
    _progress = 0;
    _pendingRelease = null;
    notifyListeners();
  }

  void update(Offset position) {
    final origin = _origin;
    if (origin == null || _size.width <= 0) return;
    _latest = position;
    _progress = pageSlideProgressFromPointer(
      origin: origin,
      current: position,
      width: _size.width,
      direction: _direction,
    );
    notifyListeners();
  }

  void release({
    required double horizontalVelocity,
    bool forceComplete = false,
  }) {
    final origin = _origin;
    final latest = _latest ?? origin;
    final along = origin == null || latest == null
        ? 0.0
        : pageSlideAlongPixels(
            origin: origin,
            current: latest,
            direction: _direction,
          );
    final release = PageSlideRelease(
      normalizedVelocity: horizontalVelocity * _direction,
      forceComplete: forceComplete,
      alongPixels: along,
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

  void attach(PageSlideReleaseHandler handler) {
    _releaseHandler = handler;
    final pending = _pendingRelease;
    if (pending != null) {
      _pendingRelease = null;
      scheduleMicrotask(() {
        if (_releaseHandler == handler) handler(pending);
      });
    }
  }

  void detach(PageSlideReleaseHandler handler) {
    if (_releaseHandler == handler) _releaseHandler = null;
  }
}
