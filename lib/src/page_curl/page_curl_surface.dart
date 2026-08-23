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
  static Future<ui.FragmentProgram>? _programFuture;
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
  ui.FragmentShader? _curlShader;
  double _touchY = 0.88;

  @override
  void initState() {
    super.initState();
    _pageTexture = _createPageTexture(widget.currentPage);
    unawaited(_loadShader());
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
    _curlShader?.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
        'shaders/page_curl.frag',
      ));
      if (!mounted) return;
      setState(() => _curlShader = program.fragmentShader());
    } on Object {
      // The tessellated painter below remains the portable fallback.
    }
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
                curlShader: _curlShader,
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
      // A spring is considered settled while it is still only very close to
      // its target. Do not let the parent remove this surface at that value:
      // the shader can still contain a sizeable piece of the outgoing page,
      // which then disappears in one frame and looks like the new text is
      // rippling into place. Pin the visual state to the fully revealed target
      // page and submit that frame before committing the reader navigation.
      if (!mounted) return;
      if (widget.controller case final controller?) {
        controller.setProgress(1);
      } else {
        setState(() => _gesture.setProgress(1));
      }
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      widget.onTurnCompleted();
    } else {
      widget.onTurnCancelled?.call();
    }
    // A completed turn stays on the target-page texture until its parent has
    // committed the real reader navigation underneath. Resetting to zero here
    // briefly reveals the old or not-yet-painted live page and makes text look
    // as if it ripples back into place. Cancellation still returns to zero.
    if (mounted && !complete) {
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
    required this.curlShader,
    required this.pageTexture,
    required this.currentPage,
    required this.nextPage,
    required this.progress,
    required this.direction,
    required this.touchY,
  });

  final ui.FragmentShader? curlShader;
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

    final shader = curlShader;
    if (shader != null) {
      final cornerY = touchY < 0.42 ? 0.0 : size.height;
      final corner = Offset(size.width, cornerY);
      // The finger only has to travel one viewport width, but the loose page
      // corner has to continue past the opposite edge for the fold crease and
      // the outgoing sheet to leave the viewport. Keeping both distances at
      // one width strands a large piece of the old page on screen at p ~= 1,
      // followed by an abrupt full-page content swap. The cubic term is tiny
      // near the start (so the page remains attached to the finger) and adds
      // the extra off-screen travel during the settling half of the turn.
      final progressValue = progress.clamp(0.0, 1.0);
      final travel =
          progressValue + progressValue * progressValue * progressValue;
      final touchX = size.width * (1 - travel);
      final horizontalPull = math.max(size.width - touchX, 1.0);
      final requestedVerticalPull = (size.height * touchY - cornerY) * 0.84;
      // A page corner cannot follow a steep diagonal finger path literally:
      // the free edge tightens and slides along the finger instead. Limiting
      // the vertical component avoids the oversized flat triangular flap that
      // a cylindrical approximation otherwise produces.
      final verticalPull = requestedVerticalPull.clamp(
        -horizontalPull * 0.72,
        horizontalPull * 0.72,
      );
      final touch = Offset(touchX, cornerY + verticalPull);
      final pull = corner - touch;
      final pullLength = math.max(pull.distance, 0.001);
      final normal = pull / pullLength;
      final tangent = Offset(-normal.dy, normal.dx);
      final radius = (pullLength * 0.145).clamp(12.0, size.width * 0.15);
      // Preserve the sheet length across the half-cylinder. With d being the
      // source corner's distance from the crease, the reflected tail lands on
      // the finger when 2d - pi*r equals the requested pull distance.
      final sourceCornerDistance = (pullLength + math.pi * radius) / 2;
      final foldCenter = corner - normal * sourceCornerDistance;
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, foldCenter.dx)
        ..setFloat(3, foldCenter.dy)
        ..setFloat(4, normal.dx)
        ..setFloat(5, normal.dy)
        ..setFloat(6, tangent.dx)
        ..setFloat(7, tangent.dy)
        ..setFloat(8, radius)
        ..setFloat(9, direction)
        ..setImageSampler(0, currentPage, filterQuality: FilterQuality.low)
        ..setImageSampler(1, nextPage, filterQuality: FilterQuality.low);
      canvas.drawRect(bounds, Paint()..shader = shader);
      return;
    }

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
      Paint()..isAntiAlias = false,
    );
    canvas.drawPath(
      mesh.foldCrease,
      Paint()
        ..color = const Color(0x3D2B2118)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(9, size.shortestSide * 0.027)
        ..strokeCap = StrokeCap.round
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
    canvas.drawVertices(
      mesh.backside,
      BlendMode.srcOver,
      Paint()..isAntiAlias = true,
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
      oldDelegate.curlShader != curlShader ||
      oldDelegate.currentPage != currentPage ||
      oldDelegate.nextPage != nextPage ||
      oldDelegate.direction != direction ||
      oldDelegate.touchY != touchY;
}
