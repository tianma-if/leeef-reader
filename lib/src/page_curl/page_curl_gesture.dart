import 'dart:ui' show clampDouble;

double pageCurlSettlingTravel({
  required double progress,
  required double startProgress,
  required bool complete,
}) {
  final current = clampDouble(progress, 0, 1);
  if (!complete) return current;
  final start = clampDouble(startProgress, 0, 1);
  final remaining = 1 - start;
  if (remaining <= 0.0001) return 2;
  final settleProgress = clampDouble((current - start) / remaining, 0, 1);
  // Add the off-screen distance cubically after release. At t=0 both the
  // position and velocity match the pointer-driven value, so the handoff is
  // continuous; at t=1 the corner has travelled two viewport widths.
  return current + settleProgress * settleProgress * settleProgress;
}

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
