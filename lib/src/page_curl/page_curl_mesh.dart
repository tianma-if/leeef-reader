import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Builds a textured sheet of paper from a regularly tessellated 3D mesh.
///
/// The sheet bends around a cylinder whose axis is derived from the original
/// page corner and the moving touch point. Vertices past half of the cylinder
/// continue as the back of the sheet. The resulting 3D points are projected
/// back into canvas space and depth-sorted before drawing.
class PageCurlMesh {
  const PageCurlMesh({
    required this.page,
    required this.backside,
    required this.shadow,
    required this.curledEdge,
    required this.foldCrease,
  });

  final ui.Vertices page;
  final ui.Vertices backside;
  final ui.Vertices shadow;
  final Path curledEdge;
  final Path foldCrease;

  static PageCurlMesh build({
    required Size size,
    required ui.Image texture,
    required double progress,
    required double direction,
    required double touchY,
    int columns = 20,
    int rows = 36,
  }) {
    final width = size.width;
    final height = size.height;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final cornerY = touchY < 0.42 ? 0.0 : height;
    final corner = Offset(width, cornerY);
    final travel = math.pow(clampedProgress, 0.84).toDouble();
    final touch = Offset(
      width * (1 - 1.42 * travel),
      _lerpDouble(cornerY, height * touchY, 0.84),
    );
    final pull = corner - touch;
    final pullLength = math.max(pull.distance, 0.001);
    final normal = pull / pullLength;
    final tangent = Offset(-normal.dy, normal.dx);
    final foldCenter = (corner + touch) / 2;
    final baseRadius = (pullLength * 0.092).clamp(10.0, width * 0.105);
    final cameraDistance = width * 2.8;
    final points = <_MeshPoint>[];

    for (var row = 0; row <= rows; row++) {
      final v = row / rows;
      for (var column = 0; column <= columns; column++) {
        final u = column / columns;
        final source = Offset(u * width, v * height);
        final fromFold = source - foldCenter;
        final alongAxis = _dot(fromFold, tangent);
        final distanceFromFold = _dot(fromFold, normal);
        // A real hand-held page is not a perfect cylinder. The bend is tighter
        // near the dragged corner and opens slightly along the crease.
        final axisDistance = (alongAxis.abs() / height).clamp(0.0, 1.0);
        final radius = baseRadius * (0.82 + axisDistance * 0.24);

        var deformed = source;
        var z = 0.0;
        var angle = 0.0;
        if (distanceFromFold > 0) {
          final cylinderLength = math.pi * radius;
          if (distanceFromFold <= cylinderLength) {
            angle = distanceFromFold / radius;
            // Keep the first derivative continuous at the crease. Using a
            // negative sine here reflects the sheet immediately and produces
            // the characteristic "rubber flap" artifact.
            final aroundAxis = radius * math.sin(angle);
            z = radius * (1 - math.cos(angle));
            deformed = foldCenter + tangent * alongAxis + normal * aroundAxis;
          } else {
            angle = math.pi;
            final tail = distanceFromFold - cylinderLength;
            z = radius * 2;
            deformed = foldCenter + tangent * alongAxis - normal * tail;
          }
        }

        final perspective = cameraDistance / (cameraDistance - z * 1.35);
        final projected = Offset(
          (deformed.dx - width / 2) * perspective + width / 2,
          (deformed.dy - height / 2) * perspective + height / 2,
        );
        final screenPosition = direction > 0
            ? projected
            : Offset(width - projected.dx, projected.dy);
        final sourceU = direction > 0 ? u : 1 - u;
        final textureCoordinate = Offset(
          sourceU * (texture.width - 1),
          v * (texture.height - 1),
        );
        final heightRatio = (z / math.max(radius * 2, 0.001)).clamp(0.0, 1.0);
        final shadowPosition = Offset(
          direction > 0
              ? deformed.dx + z * 0.34
              : width - deformed.dx - z * 0.34,
          deformed.dy + (cornerY == height ? -z * 0.12 : z * 0.12),
        );

        points.add(
          _MeshPoint(
            localProjection: projected,
            screenPosition: screenPosition,
            textureCoordinate: textureCoordinate,
            shadowPosition: shadowPosition,
            shadowColor: Color.fromARGB(
              (math.sin(heightRatio * math.pi) * 72).round(),
              18,
              13,
              8,
            ),
            z: z,
            angle: angle,
          ),
        );
      }
    }

    final triangles = <_MeshTriangle>[];
    final stride = columns + 1;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final topLeft = row * stride + column;
        final topRight = topLeft + 1;
        final bottomLeft = topLeft + stride;
        final bottomRight = bottomLeft + 1;
        _addTriangle(triangles, points, topLeft, topRight, bottomLeft);
        _addTriangle(triangles, points, topRight, bottomRight, bottomLeft);
      }
    }
    const depthBucketCount = 48;
    final depthBuckets = List.generate(
      depthBucketCount,
      (_) => <_MeshTriangle>[],
    );
    for (final triangle in triangles) {
      final bucket =
          (triangle.averageZ / (baseRadius * 2) * (depthBucketCount - 1))
              .round()
              .clamp(0, depthBucketCount - 1);
      depthBuckets[bucket].add(triangle);
    }
    final depthSortedTriangles = <_MeshTriangle>[
      for (final bucket in depthBuckets) ...bucket,
    ];

    final pagePositions = Float32List(points.length * 2);
    final pageTextureCoordinates = Float32List(points.length * 2);
    final pageColors = Int32List(points.length);
    final shadowPositions = Float32List(points.length * 2);
    final shadowColors = Int32List(points.length);
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final coordinateIndex = index * 2;
      pagePositions[coordinateIndex] = point.screenPosition.dx;
      pagePositions[coordinateIndex + 1] = point.screenPosition.dy;
      pageTextureCoordinates[coordinateIndex] = point.textureCoordinate.dx;
      pageTextureCoordinates[coordinateIndex + 1] = point.textureCoordinate.dy;
      pageColors[index] = _paperLight(point.angle).toARGB32();
      shadowPositions[coordinateIndex] = point.shadowPosition.dx;
      shadowPositions[coordinateIndex + 1] = point.shadowPosition.dy;
      shadowColors[index] = point.shadowColor.toARGB32();
    }
    final triangleIndices = Uint16List(depthSortedTriangles.length * 3);
    for (var index = 0; index < depthSortedTriangles.length; index++) {
      final triangle = depthSortedTriangles[index];
      final triangleIndex = index * 3;
      triangleIndices[triangleIndex] = triangle.a;
      triangleIndices[triangleIndex + 1] = triangle.b;
      triangleIndices[triangleIndex + 2] = triangle.c;
    }
    final backsideTriangles = depthSortedTriangles
        .where((triangle) => triangle.averageAngle > math.pi / 2)
        .toList(growable: false);
    final backsideIndices = Uint16List(backsideTriangles.length * 3);
    final backsideColors = Int32List(points.length);
    for (var index = 0; index < points.length; index++) {
      final angle = points[index].angle;
      final backAmount = ((angle - math.pi / 2) / (math.pi / 2)).clamp(
        0.0,
        1.0,
      );
      final opacity = (104 + backAmount * 58).round();
      backsideColors[index] = Color.fromARGB(opacity, 255, 247, 224).toARGB32();
    }
    for (var index = 0; index < backsideTriangles.length; index++) {
      final triangle = backsideTriangles[index];
      final triangleIndex = index * 3;
      backsideIndices[triangleIndex] = triangle.a;
      backsideIndices[triangleIndex + 1] = triangle.b;
      backsideIndices[triangleIndex + 2] = triangle.c;
    }

    final boundary = <int>[
      for (var column = 0; column <= columns; column++) column,
      for (var row = 1; row <= rows; row++) row * stride + columns,
      for (var column = columns - 1; column >= 0; column--)
        rows * stride + column,
      for (var row = rows - 1; row > 0; row--) row * stride,
    ];
    final curledEdge = Path();
    var edgeStarted = false;
    for (final index in boundary) {
      final point = points[index];
      if (point.z <= 0.5) {
        edgeStarted = false;
        continue;
      }
      if (edgeStarted) {
        curledEdge.lineTo(point.screenPosition.dx, point.screenPosition.dy);
      } else {
        curledEdge.moveTo(point.screenPosition.dx, point.screenPosition.dy);
        edgeStarted = true;
      }
    }

    final foldCrease = _foldLinePath(
      size: size,
      center: foldCenter,
      tangent: tangent,
      direction: direction,
    );

    return PageCurlMesh(
      page: ui.Vertices.raw(
        ui.VertexMode.triangles,
        pagePositions,
        textureCoordinates: pageTextureCoordinates,
        colors: pageColors,
        indices: triangleIndices,
      ),
      backside: ui.Vertices.raw(
        ui.VertexMode.triangles,
        pagePositions,
        colors: backsideColors,
        indices: backsideIndices,
      ),
      shadow: ui.Vertices.raw(
        ui.VertexMode.triangles,
        shadowPositions,
        colors: shadowColors,
        indices: triangleIndices,
      ),
      curledEdge: curledEdge,
      foldCrease: foldCrease,
    );
  }

  static Path _foldLinePath({
    required Size size,
    required Offset center,
    required Offset tangent,
    required double direction,
  }) {
    final extent = size.longestSide * 2;
    Offset mirror(Offset point) =>
        direction > 0 ? point : Offset(size.width - point.dx, point.dy);
    return Path()
      ..moveTo(
        mirror(center - tangent * extent).dx,
        mirror(center - tangent * extent).dy,
      )
      ..lineTo(
        mirror(center + tangent * extent).dx,
        mirror(center + tangent * extent).dy,
      );
  }

  static void _addTriangle(
    List<_MeshTriangle> triangles,
    List<_MeshPoint> points,
    int a,
    int b,
    int c,
  ) {
    final first = points[a];
    final second = points[b];
    final third = points[c];
    final area = _cross(
      second.localProjection - first.localProjection,
      third.localProjection - first.localProjection,
    );
    if (area.abs() < 0.0001) return;
    triangles.add(
      _MeshTriangle(
        a: a,
        b: b,
        c: c,
        averageZ: (first.z + second.z + third.z) / 3,
        averageAngle: (first.angle + second.angle + third.angle) / 3,
      ),
    );
  }

  static Color _paperLight(double angle) {
    if (angle > math.pi / 2) {
      final grazing = math.sin(angle).abs();
      final light = 0.78 + grazing * 0.12;
      return Color.fromARGB(
        255,
        (255 * light).round(),
        (246 * light).round(),
        (224 * light).round(),
      );
    }
    final diffuse = math.cos(angle).clamp(0.0, 1.0);
    final highlight =
        math.exp(-math.pow((angle - 0.62) * 5.0, 2).toDouble()) * 0.13;
    final light = (0.84 + diffuse * 0.13 + highlight).clamp(0.0, 1.0);
    final channel = (255 * light).round();
    return Color.fromARGB(255, channel, channel, channel);
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class _MeshPoint {
  const _MeshPoint({
    required this.localProjection,
    required this.screenPosition,
    required this.textureCoordinate,
    required this.shadowPosition,
    required this.shadowColor,
    required this.z,
    required this.angle,
  });

  final Offset localProjection;
  final Offset screenPosition;
  final Offset textureCoordinate;
  final Offset shadowPosition;
  final Color shadowColor;
  final double z;
  final double angle;
}

class _MeshTriangle {
  const _MeshTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.averageZ,
    required this.averageAngle,
  });

  final int a;
  final int b;
  final int c;
  final double averageZ;
  final double averageAngle;
}
