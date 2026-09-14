import 'dart:ui' show Offset, clampDouble;

/// Finger travel maps 1:1 onto page width, matching a Readest-style slide.
const pageSlideInteractiveSpan = 1.0;

/// Fraction of the page that commits the turn on release.
const pageSlideCompletionThreshold = 0.22;

/// Fling speed in logical pixels per second that commits even a short drag.
const pageSlideFlingVelocityThreshold = 400.0;

/// Horizontal travel past tap slop that can still commit with a flick.
const pageSlideMinCommitTravel = 28.0;

/// Readest-style snap: ease-out quad over 300ms.
const pageSlideSnapDuration = Duration(milliseconds: 300);

/// Release velocity is projected this far when deciding commit vs cancel.
const pageSlideReleaseProjection = Duration(milliseconds: 240);

/// Horizontal pixels before a drag is claimed as a page turn.
const pageSlideClaimPixels = 8.0;

/// Rubber-band factor at the first/last page.
const pageSlideOverscrollFactor = 0.28;

double pageSlideEaseOutQuad(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * (2 - x);
}

/// Commits when the finger plus a short velocity projection crosses halfway.
bool pageSlideCommitProjected({
  required double progress,
  required double velocityPxPerMs,
  required double width,
}) {
  if (width <= 0) return progress > 0.5;
  final projected =
      progress +
      velocityPxPerMs * pageSlideReleaseProjection.inMilliseconds / width;
  return projected >= 0.5;
}

/// Swipe lanes stay at least this wide so a start slightly inside the page
/// still counts; tap-to-turn keeps the user's tap-zone setting.
double pageSlideSwipeZoneRatio(double tapZoneRatio) =>
    tapZoneRatio < 0.4 ? 0.4 : tapZoneRatio;

/// -1 previous, 1 next, 0 outside the swipe lanes.
double pageSlideDirectionForX({
  required double x,
  required double width,
  required double tapZoneRatio,
  bool swapTapZones = false,
}) {
  final zone = pageSlideSwipeZoneRatio(tapZoneRatio);
  var direction = x >= width * (1 - zone)
      ? 1.0
      : x <= width * zone
      ? -1.0
      : 0.0;
  if (swapTapZones) direction = -direction;
  return direction;
}

/// Converts a pointer path into slide progress. Diagonal flicks within about
/// 60° of horizontal use the full path length, so an imperfect angle still
/// turns the page.
double pageSlideProgressFromPointer({
  required Offset origin,
  required Offset current,
  required double width,
  required double direction,
}) {
  if (width <= 0) return 0;
  final signed = direction.sign == 0 ? 1.0 : direction.sign;
  final dx = (origin.dx - current.dx) * signed;
  if (dx <= 0) return 0;
  final along = pageSlideAlongPixels(
    origin: origin,
    current: current,
    direction: signed,
  );
  return clampDouble(along / (width * pageSlideInteractiveSpan), 0, 1);
}

double pageSlideAlongPixels({
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

bool pageSlideShouldComplete({
  required double progress,
  required double velocity,
  double alongPixels = 0,
}) {
  return progress >= pageSlideCompletionThreshold ||
      (alongPixels >= pageSlideMinCommitTravel &&
          velocity <= -pageSlideFlingVelocityThreshold / 2) ||
      velocity <= -pageSlideFlingVelocityThreshold;
}

class PageSlideGesture {
  PageSlideGesture();

  double _progress = 0;

  double get progress => _progress;

  double update({required double horizontalDelta, required double width}) {
    if (width <= 0) return _progress;
    _progress = clampDouble(
      _progress - horizontalDelta / (width * pageSlideInteractiveSpan),
      0,
      1,
    );
    return _progress;
  }

  bool shouldComplete(double horizontalVelocity, {double alongPixels = 0}) =>
      pageSlideShouldComplete(
        progress: _progress,
        velocity: horizontalVelocity,
        alongPixels: alongPixels,
      );

  void setProgress(double value) {
    _progress = clampDouble(value, 0, 1);
  }

  void reset() => _progress = 0;
}
