import 'dart:ui' show clampDouble;

class PageCurlGesture {
  PageCurlGesture({
    this.completionThreshold = 0.48,
    this.flingVelocityThreshold = 800,
  });

  final double completionThreshold;
  final double flingVelocityThreshold;
  double _progress = 0;

  double get progress => _progress;

  double update({required double horizontalDelta, required double width}) {
    if (width <= 0) return _progress;
    _progress = clampDouble(_progress - horizontalDelta / width, 0, 1);
    return _progress;
  }

  bool shouldComplete(double horizontalVelocity) =>
      _progress >= completionThreshold ||
      horizontalVelocity <= -flingVelocityThreshold;

  void setProgress(double value) {
    _progress = clampDouble(value, 0, 1);
  }

  void reset() => _progress = 0;
}
