import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/page_curl/page_curl_gesture.dart';

class PageCurlSurface extends StatefulWidget {
  const PageCurlSurface({
    required this.currentPage,
    required this.nextPage,
    required this.onTurnCompleted,
    super.key,
    this.onTurnCancelled,
    this.onUnavailable,
    this.direction = 1,
    this.autoComplete = false,
  });

  final ui.Image currentPage;
  final ui.Image nextPage;
  final VoidCallback onTurnCompleted;
  final VoidCallback? onTurnCancelled;
  final VoidCallback? onUnavailable;
  final double direction;
  final bool autoComplete;

  @override
  State<PageCurlSurface> createState() => _PageCurlSurfaceState();
}

class _PageCurlSurfaceState extends State<PageCurlSurface>
    with SingleTickerProviderStateMixin {
  final PageCurlGesture _gesture = PageCurlGesture();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(() => setState(() => _gesture.setProgress(_animation.value)));
  ui.FragmentShader? _shader;
  double _touchY = 0.88;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/page_curl.frag',
      );
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      if (widget.autoComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_settle(true));
        });
      }
    } on Object {
      if (mounted) widget.onUnavailable?.call();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return const ColoredBox(color: Colors.transparent);
    return LayoutBuilder(
      builder: (context, constraints) {
        return IgnorePointer(
          ignoring: widget.autoComplete,
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
              _settle(_gesture.shouldComplete(velocity));
            },
            child: CustomPaint(
              painter: _PageCurlPainter(
                shader: shader,
                currentPage: widget.currentPage,
                nextPage: widget.nextPage,
                progress: _gesture.progress,
                direction: widget.direction,
                touchY: widget.autoComplete
                    ? _automaticTouchY(_gesture.progress)
                    : _touchY,
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

  Future<void> _settle(bool complete) async {
    _animation.value = _gesture.progress;
    if (complete) {
      await _animation.animateTo(1, curve: Curves.easeInOutCubic);
      widget.onTurnCompleted();
    } else {
      await _animation.animateBack(0, curve: Curves.easeOutCubic);
      widget.onTurnCancelled?.call();
    }
    if (mounted) setState(_gesture.reset);
  }
}

class _PageCurlPainter extends CustomPainter {
  const _PageCurlPainter({
    required this.shader,
    required this.currentPage,
    required this.nextPage,
    required this.progress,
    required this.direction,
    required this.touchY,
  });

  final ui.FragmentShader shader;
  final ui.Image currentPage;
  final ui.Image nextPage;
  final double progress;
  final double direction;
  final double touchY;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, progress)
      ..setFloat(3, direction)
      ..setFloat(4, touchY)
      ..setImageSampler(0, currentPage)
      ..setImageSampler(1, nextPage);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PageCurlPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.currentPage != currentPage ||
      oldDelegate.nextPage != nextPage ||
      oldDelegate.direction != direction ||
      oldDelegate.touchY != touchY;
}
