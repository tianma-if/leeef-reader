import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:leeef_reader/src/page_slide/page_slide_controller.dart';
import 'package:leeef_reader/src/page_slide/page_slide_gesture.dart';

/// Interactive 2D slide of two page snapshots.
///
/// The outgoing trailing edge and incoming leading edge share one seam, and
/// progress tracks the finger 1:1 against the page width.
class PageSlideSurface extends StatefulWidget {
  const PageSlideSurface({
    required this.currentPage,
    required this.nextPage,
    required this.onTurnCompleted,
    super.key,
    this.onTurnCancelled,
    this.controller,
    this.direction = 1,
    this.autoComplete = false,
  });

  final ui.Image currentPage;
  final ui.Image nextPage;
  final VoidCallback onTurnCompleted;
  final VoidCallback? onTurnCancelled;
  final PageSlideController? controller;
  final double direction;
  final bool autoComplete;

  @override
  State<PageSlideSurface> createState() => _PageSlideSurfaceState();
}

class _PageSlideSurfaceState extends State<PageSlideSurface>
    with SingleTickerProviderStateMixin {
  static const _slideSpring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 36,
  );
  final PageSlideGesture _gesture = PageSlideGesture();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addListener(_handleAnimationTick);

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    if (widget.autoComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_settle(true));
      });
    }
  }

  @override
  void didUpdateWidget(PageSlideSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = _progress;
        final signed = widget.direction.sign == 0 ? 1.0 : widget.direction.sign;
        return IgnorePointer(
          ignoring: widget.autoComplete || widget.controller != null,
          child: GestureDetector(
            key: const Key('page-slide-gesture'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _animation.stop();
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _gesture.update(
                  horizontalDelta: details.delta.dx * signed,
                  width: width,
                );
              });
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity! * signed;
              _settle(
                _gesture.shouldComplete(
                  velocity,
                  alongPixels: _gesture.progress * width,
                ),
                normalizedVelocity: velocity,
              );
            },
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: Offset(-signed * width * progress, 0),
                    child: _PageImage(image: widget.currentPage),
                  ),
                  Transform.translate(
                    offset: Offset(signed * width * (1 - progress), 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x3D000000),
                            blurRadius: 18,
                            offset: Offset(-signed * 6, 0),
                          ),
                        ],
                      ),
                      child: _PageImage(image: widget.nextPage),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

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
        _slideSpring,
        _animation.value,
        target,
        progressVelocity,
      ),
    );
    if (complete) {
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

  void _handleControllerRelease(PageSlideRelease release) {
    final complete =
        release.forceComplete ||
        pageSlideShouldComplete(
          progress: _progress,
          velocity: release.normalizedVelocity,
          alongPixels: release.alongPixels,
        );
    unawaited(
      _settle(complete, normalizedVelocity: release.normalizedVelocity),
    );
  }

  void _attachController(PageSlideController? controller) {
    controller
      ?..addListener(_handleControllerChanged)
      ..attach(_handleControllerRelease);
  }

  void _detachController(PageSlideController? controller) {
    controller
      ?..detach(_handleControllerRelease)
      ..removeListener(_handleControllerChanged);
  }
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.image});

  final ui.Image image;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: RawImage(
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    ),
  );
}
