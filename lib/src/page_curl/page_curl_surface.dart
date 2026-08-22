import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_gesture.dart';
import 'package:leeef_reader/src/page_curl/page_curl_mesh.dart';

class PageCurlSurface extends StatefulWidget {
  const PageCurlSurface({
    required this.currentPage,
    required this.nextPage,
    required this.onTurnCompleted,
    super.key,
    this.onTurnCancelled,
    this.onUnavailable,
    this.controller,
    this.direction = 1,
    this.autoComplete = false,
  });

  final ui.Image currentPage;
  final ui.Image nextPage;
  final VoidCallback onTurnCompleted;
  final VoidCallback? onTurnCancelled;
  final VoidCallback? onUnavailable;
  final PageCurlController? controller;
  final double direction;
  final bool autoComplete;

  @override
  State<PageCurlSurface> createState() => _PageCurlSurfaceState();
}

class _PageCurlSurfaceState extends State<PageCurlSurface>
    with SingleTickerProviderStateMixin {
  static const _paperSpring = SpringDescription(
    mass: 1,
    stiffness: 430,
    damping: 37,
  );
  final PageCurlGesture _gesture = PageCurlGesture();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(_handleAnimationTick);
  late ui.ImageShader _pageTexture;
  double _touchY = 0.88;

  @override
  void initState() {
    super.initState();
    _pageTexture = _createPageTexture(widget.currentPage);
    _attachController(widget.controller);
    if (widget.autoComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_settle(true));
      });
    }
  }

  @override
  void didUpdateWidget(PageCurlSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (oldWidget.currentPage != widget.currentPage) {
      _pageTexture.dispose();
      _pageTexture = _createPageTexture(widget.currentPage);
    }
  }

  ui.ImageShader _createPageTexture(ui.Image image) => ui.ImageShader(
    image,
    ui.TileMode.clamp,
    ui.TileMode.clamp,
    Float64List.fromList(<double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ]),
    filterQuality: FilterQuality.medium,
  );

  @override
  void dispose() {
    _detachController(widget.controller);
    _animation.dispose();
    _pageTexture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return IgnorePointer(
          ignoring: widget.autoComplete || widget.controller != null,
          child: GestureDetector(
            key: const Key('page-curl-gesture'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              _animation.stop();
              _touchY = _normalizedTouchY(
                details.localPosition.dy,
                constraints.maxHeight,
              );
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _touchY = _normalizedTouchY(
                  details.localPosition.dy,
                  constraints.maxHeight,
                );
                _gesture.update(
                  horizontalDelta: details.delta.dx * widget.direction,
                  width: constraints.maxWidth,
                );
              });
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity! * widget.direction;
              _settle(
                _gesture.shouldComplete(velocity),
                normalizedVelocity: velocity,
              );
            },
            child: CustomPaint(
              painter: _PageCurlPainter(
                pageTexture: _pageTexture,
                currentPage: widget.currentPage,
                nextPage: widget.nextPage,
                progress: _progress,
                direction: widget.direction,
                touchY: widget.autoComplete
                    ? _automaticTouchY(_progress)
                    : widget.controller?.touchY ?? _touchY,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  double _normalizedTouchY(double y, double height) =>
      (y / height).clamp(0.12, 0.94);

  double _automaticTouchY(double progress) =>
      0.88 - (math.sin(math.pi * progress) * 0.20);

  Future<void> _settle(bool complete, {double normalizedVelocity = 0}) async {
    _animation.stop();
    _animation.value = _progress;
    final width = context.size?.width ?? 1;
    final rawProgressVelocity = -normalizedVelocity / math.max(width, 1);
    final progressVelocity = complete
        ? math.max(0.0, rawProgressVelocity)
        : math.min(0.0, rawProgressVelocity);
    final target = complete ? 1.0 : 0.0;
    await _animation.animateWith(
      SpringSimulation(
        _paperSpring,
        _animation.value,
        target,
        progressVelocity,
      ),
    );
    if (complete) {
      widget.onTurnCompleted();
    } else {
      widget.onTurnCancelled?.call();
    }
    if (mounted) {
      if (widget.controller case final controller?) {
        controller.setProgress(0);
      } else {
        setState(_gesture.reset);
      }
    }
  }

  double get _progress => widget.controller?.progress ?? _gesture.progress;

  void _handleAnimationTick() {
    if (widget.controller case final controller?) {
      controller.setProgress(_animation.value);
    } else if (mounted) {
      setState(() => _gesture.setProgress(_animation.value));
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleControllerRelease(PageCurlRelease release) {
    final complete =
        release.forceComplete ||
        _progress >= _gesture.completionThreshold ||
        release.normalizedVelocity <= -_gesture.flingVelocityThreshold;
    unawaited(
      _settle(complete, normalizedVelocity: release.normalizedVelocity),
    );
  }

  void _attachController(PageCurlController? controller) {
    controller
      ?..addListener(_handleControllerChanged)
      ..attach(_handleControllerRelease);
  }

  void _detachController(PageCurlController? controller) {
    controller
      ?..detach(_handleControllerRelease)
      ..removeListener(_handleControllerChanged);
  }
}

class _PageCurlPainter extends CustomPainter {
  const _PageCurlPainter({
    required this.pageTexture,
    required this.currentPage,
    required this.nextPage,
    required this.progress,
    required this.direction,
    required this.touchY,
  });

  final ui.ImageShader pageTexture;
  final ui.Image currentPage;
  final ui.Image nextPage;
  final double progress;
  final double direction;
  final double touchY;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    if (progress <= 0.001) {
      canvas.drawImageRect(
        currentPage,
        Rect.fromLTWH(
          0,
          0,
          currentPage.width.toDouble(),
          currentPage.height.toDouble(),
        ),
        bounds,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    canvas.drawImageRect(
      nextPage,
      Rect.fromLTWH(
        0,
        0,
        nextPage.width.toDouble(),
        nextPage.height.toDouble(),
      ),
      bounds,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (progress >= 0.999) return;

    final mesh = PageCurlMesh.build(
      size: size,
      texture: currentPage,
      progress: progress,
      direction: direction,
      touchY: touchY,
    );
    canvas.drawVertices(
      mesh.shadow,
      BlendMode.srcOver,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11)
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      mesh.foldCrease,
      Paint()
        ..color = const Color(0x3D2B2118)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(9, size.shortestSide * 0.027)
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
        ..isAntiAlias = true,
    );
    canvas.drawVertices(
      mesh.page,
      BlendMode.modulate,
      Paint()
        ..shader = pageTexture
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
    canvas
      ..drawPath(
        mesh.curledEdge,
        Paint()
          ..color = const Color(0x7A6E5A43)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25
          ..isAntiAlias = true,
      )
      ..drawPath(
        mesh.curledEdge,
        Paint()
          ..color = const Color(0xB8FFFDF5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.45
          ..isAntiAlias = true,
      );
  }

  @override
  bool shouldRepaint(_PageCurlPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.currentPage != currentPage ||
      oldDelegate.nextPage != nextPage ||
      oldDelegate.direction != direction ||
      oldDelegate.touchY != touchY;
}
