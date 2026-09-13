import 'dart:ui' show Offset, clampDouble;

/// Interactive drag maps this fraction of the page width to a full curl, so a
/// short flick can finish the turn without crossing the whole viewport.
const pageCurlInteractiveSpan = 0.4;

/// Minimum finger travel, as curl progress, that commits the page turn.
const pageCurlCompletionThreshold = 0.05;

/// Fling speed in logical pixels per second that commits even a short drag.
const pageCurlFlingVelocityThreshold = 120.0;

/// Any movement past tap slop in the turn direction commits the page.
const pageCurlMinCommitTravel = 12.0;

/// Curl swipe lanes stay at least this wide so a start slightly inside the
/// page still counts; tap-to-turn keeps the user's tap-zone setting.
double pageCurlSwipeZoneRatio(double tapZoneRatio) =>
    tapZoneRatio < 0.4 ? 0.4 : tapZoneRatio;

/// -1 previous, 1 next, 0 outside the swipe lanes.
double pageCurlDirectionForX({
  required double x,
  required double width,
  required double tapZoneRatio,
  bool swapTapZones = false,
}) {
  final zone = pageCurlSwipeZoneRatio(tapZoneRatio);
  var direction = x >= width * (1 - zone)
      ? 1.0
      : x <= width * zone
      ? -1.0
      : 0.0;
  if (swapTapZones) direction = -direction;
  return direction;
}

/// Converts a pointer path into curl progress. Diagonal flicks within about
/// 60° of horizontal use the full path length, so an imperfect angle still
/// turns the page.
double pageCurlProgressFromPointer({
  required Offset origin,
  required Offset current,
  required double width,
  required double direction,
}) {
  if (width <= 0) return 0;
  final signed = direction.sign == 0 ? 1.0 : direction.sign;
  final dx = (origin.dx - current.dx) * signed;
  if (dx <= 0) return 0;
  final along = pageCurlAlongPixels(
    origin: origin,
    current: current,
    direction: signed,
  );
  return clampDouble(along / (width * pageCurlInteractiveSpan), 0, 1);
}

double pageCurlAlongPixels({
  required Offset origin,
  required Offset current,
  required double direction,
}) {
  final signed = direction.sign == 0 ? 1.0 : direction.sign;
  final dx = (origin.dx - current.dx) * signed;
  if (dx <= 0) return 0;
  final distance = (current - origin).distance;
  return dx >= distance * 0.5 ? distance : dx;
}

bool pageCurlShouldComplete({
  required double progress,
  required double velocity,
  double alongPixels = 0,
}) {
  return alongPixels >= pageCurlMinCommitTravel ||
      progress >= pageCurlCompletionThreshold ||
      velocity <= -pageCurlFlingVelocityThreshold;
}

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
    this.completionThreshold = pageCurlCompletionThreshold,
    this.flingVelocityThreshold = pageCurlFlingVelocityThreshold,
  });

  final double completionThreshold;
  final double flingVelocityThreshold;
  double _progress = 0;

  double get progress => _progress;

  double update({required double horizontalDelta, required double width}) {
    if (width <= 0) return _progress;
    _progress = clampDouble(
      _progress - horizontalDelta / (width * pageCurlInteractiveSpan),
      0,
      1,
    );
    return _progress;
  }

  bool shouldComplete(double horizontalVelocity, {double alongPixels = 0}) =>
      pageCurlShouldComplete(
        progress: _progress,
        velocity: horizontalVelocity,
        alongPixels: alongPixels,
      );

  void setProgress(double value) {
    _progress = clampDouble(value, 0, 1);
  }

  void reset() => _progress = 0;
}
