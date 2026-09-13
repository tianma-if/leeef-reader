import 'dart:math' as math;
import 'dart:ui';

/// Shared cylinder parameters for the fragment shader and tessellated fallback.
class PageCurlGeometry {
  const PageCurlGeometry({
    required this.grab,
    required this.touch,
    required this.foldCenter,
    required this.normal,
    required this.tangent,
    required this.radius,
  });

  final Offset grab;
  final Offset touch;
  final Offset foldCenter;
  final Offset normal;
  final Offset tangent;
  final double radius;

  /// Builds the curl from a right-edge grab.
  ///
  /// Touches near the top or bottom still peel from that page corner. Touches
  /// along the middle of the edge roll around a near-vertical cylinder so the
  /// sheet does not collapse into a blank triangular flap.
  static PageCurlGeometry compute({
    required Size size,
    required double travel,
    required double touchY,
  }) {
    final width = size.width;
    final height = size.height;
    final clampedTravel = travel.clamp(0.0, 2.0);
    final clampedY = touchY.clamp(0.08, 0.96);
    final fromCorner = clampedY < 0.28 || clampedY > 0.72;
    final grabY = fromCorner ? (clampedY < 0.28 ? 0.0 : height) : height * clampedY;
    final grab = Offset(width, grabY);
    final touchX = width * (1 - clampedTravel);
    final horizontalPull = math.max(width - touchX, 1.0);
    final requestedVerticalPull = fromCorner
        ? (height * clampedY - grabY) * 0.84
        : (height * clampedY - grabY) * 0.18;
    final verticalLimit = fromCorner ? 0.72 : 0.22;
    final verticalPull = requestedVerticalPull.clamp(
      -horizontalPull * verticalLimit,
      horizontalPull * verticalLimit,
    );
    final touch = Offset(touchX, grabY + verticalPull);
    final pull = grab - touch;
    final pullLength = math.max(pull.distance, 0.001);
    final normal = pull / pullLength;
    final tangent = Offset(-normal.dy, normal.dx);
    final radius = (pullLength * 0.22).clamp(18.0, width * 0.22);
    final sourceGrabDistance = (pullLength + math.pi * radius) / 2;
    final foldCenter = grab - normal * sourceGrabDistance;
    return PageCurlGeometry(
      grab: grab,
      touch: touch,
      foldCenter: foldCenter,
      normal: normal,
      tangent: tangent,
      radius: radius,
    );
  }
}
