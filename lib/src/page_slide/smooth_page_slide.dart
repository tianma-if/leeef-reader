import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/page_slide/page_slide_gesture.dart';

/// 1:1 finger-following page slide, matching Readest's mobile slide turn.
class SmoothPageSlideController {
  _SmoothPageSlideState? _state;

  Future<void> goTo(int index, {bool animate = true}) async {
    await _state?._goTo(index, animate: animate);
  }
}

class SmoothPageSlide extends StatefulWidget {
  const SmoothPageSlide({
    required this.pageIndex,
    required this.pageCount,
    required this.pageBuilder,
    required this.onPageChanged,
    super.key,
    this.controller,
    this.onCenterTap,
    this.tapZoneRatio = 0.28,
    this.swapTapZones = false,
    this.leftZoneKey,
    this.rightZoneKey,
    this.pageCacheKey,
  });

  final int pageIndex;
  final int pageCount;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final ValueChanged<int> onPageChanged;
  final SmoothPageSlideController? controller;
  final VoidCallback? onCenterTap;
  final double tapZoneRatio;
  final bool swapTapZones;
  final Key? leftZoneKey;
  final Key? rightZoneKey;

  /// When this identity changes, frozen page widgets are rebuilt.
  ///
  /// Unrelated parent rebuilds (insets, clocks, pagination) must keep the
  /// same key so already-rasterized pages are not laid out again mid-swipe.
  final Object? pageCacheKey;

  @override
  State<SmoothPageSlide> createState() => _SmoothPageSlideState();
}

class _SmoothPageSlideState extends State<SmoothPageSlide>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _offset = ValueNotifier(0);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: pageSlideSnapDuration,
  );
  double _velocityPxPerMs = 0;
  double _dragAccumulated = 0;
  bool _settling = false;
  int _activeIndex = 0;
  Object? _cachedKey;
  final Map<int, Widget> _pages = {};
  Widget? _cachedPrev;
  Widget? _cachedCurrent;
  Widget? _cachedNext;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.pageIndex;
    widget.controller?._state = this;
    _settle.addListener(_tickSettle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachePages();
  }

  @override
  void didUpdateWidget(SmoothPageSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
    if (widget.pageIndex != _activeIndex && !_settling) {
      _activeIndex = widget.pageIndex;
      _offset.value = 0;
    }
    _cachePages(force: oldWidget.pageCacheKey != widget.pageCacheKey);
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) {
      widget.controller?._state = null;
    }
    _settle
      ..removeListener(_tickSettle)
      ..dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final zone = width * widget.tapZoneRatio;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (!_settling) _handleTap(details.localPosition, width);
          },
          onHorizontalDragStart: (_) {
            if (_settling) return;
            _dragAccumulated = 0;
          },
          onHorizontalDragUpdate: (details) {
            if (_settling || width <= 0) return;
            _dragAccumulated += details.delta.dx;
            var offset = _dragAccumulated;
            final atStart = _activeIndex <= 0 && offset > 0;
            final atEnd = _activeIndex >= widget.pageCount - 1 && offset < 0;
            if (atStart || atEnd) offset *= pageSlideOverscrollFactor;
            _offset.value = offset;
          },
          onHorizontalDragEnd: (details) {
            _velocityPxPerMs = (details.primaryVelocity ?? 0) / 1000;
            unawaited(_settleFromRelease(width));
          },
          onHorizontalDragCancel: () {
            if (!_settling) unawaited(_animateOffset(0, width));
          },
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (context, offset, _) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cachedPrev case final prev?)
                          Transform.translate(
                            offset: Offset(offset - width, 0),
                            child: prev,
                          ),
                        if (_cachedCurrent case final current?)
                          Transform.translate(
                            offset: Offset(offset, 0),
                            child: current,
                          ),
                        if (_cachedNext case final next?)
                          Transform.translate(
                            offset: Offset(offset + width, 0),
                            child: next,
                          ),
                      ],
                    );
                  },
                ),
                Positioned(
                  key: widget.leftZoneKey,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: zone,
                  child: const SizedBox.expand(),
                ),
                Positioned(
                  key: widget.rightZoneKey,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: zone,
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _page(int index) => KeyedSubtree(
    key: ValueKey('smooth-page-$index'),
    child: RepaintBoundary(child: widget.pageBuilder(context, index)),
  );

  void _cachePages({bool force = false}) {
    if (force || _cachedKey != widget.pageCacheKey) {
      _pages.clear();
      _cachedKey = widget.pageCacheKey;
    }
    final needed = <int>{};
    if (_activeIndex > 0) needed.add(_activeIndex - 1);
    if (widget.pageCount > 0 &&
        _activeIndex >= 0 &&
        _activeIndex < widget.pageCount) {
      needed.add(_activeIndex);
    }
    if (_activeIndex + 1 < widget.pageCount) needed.add(_activeIndex + 1);
    _pages.removeWhere((index, _) => !needed.contains(index));
    for (final index in needed) {
      _pages.putIfAbsent(index, () => _page(index));
    }
    _cachedPrev = _pages[_activeIndex - 1];
    _cachedCurrent = _pages[_activeIndex];
    _cachedNext = _pages[_activeIndex + 1];
  }

  void _handleTap(Offset origin, double width) {
    final x = origin.dx;
    final zone = width * widget.tapZoneRatio;
    final onLeft = x <= zone;
    final onRight = x >= width - zone;
    if (!onLeft && !onRight) {
      widget.onCenterTap?.call();
      return;
    }
    var forward = onRight;
    if (widget.swapTapZones) forward = !forward;
    unawaited(_goTo(_activeIndex + (forward ? 1 : -1)));
  }

  Future<void> _settleFromRelease(double width) async {
    final offset = _offset.value;
    final along = -offset;
    final progress = (along.abs() / width).clamp(0.0, 1.0);
    final velocity = -_velocityPxPerMs;
    final signedVelocity = along < 0 ? -velocity : velocity;
    final commit =
        along.abs() > 0.5 &&
        pageSlideCommitProjected(
          progress: progress,
          velocityPxPerMs: signedVelocity,
          width: width,
        );
    final targetIndex = commit
        ? (along > 0 ? _activeIndex + 1 : _activeIndex - 1)
        : _activeIndex;
    final targetOffset = commit ? (along > 0 ? -width : width) : 0.0;
    await _animateOffset(targetOffset, width);
    if (commit) {
      _commitIndex(targetIndex.clamp(0, widget.pageCount - 1));
    }
  }

  Future<void> _goTo(int index, {bool animate = true}) async {
    final target = index.clamp(0, widget.pageCount - 1);
    if (target == _activeIndex) return;
    final width =
        (context.findRenderObject() as RenderBox?)?.size.width ??
        MediaQuery.sizeOf(context).width;
    if (!animate || (target - _activeIndex).abs() != 1 || width <= 0) {
      _commitIndex(target);
      return;
    }
    final targetOffset = target > _activeIndex ? -width : width;
    await _animateOffset(targetOffset, width);
    _commitIndex(target);
  }

  void _commitIndex(int index) {
    _activeIndex = index;
    _offset.value = 0;
    _cachePages();
    widget.onPageChanged(index);
  }

  Future<void> _animateOffset(double target, double width) async {
    final start = _offset.value;
    if ((start - target).abs() < 0.5) {
      _offset.value = target;
      return;
    }
    _settling = true;
    _settle.duration = pageSlideSnapDuration;
    _settle.value = 0;
    _settleStart = start;
    _settleTarget = target;
    await _settle.forward(from: 0);
    _offset.value = target;
    _settling = false;
  }

  double _settleStart = 0;
  double _settleTarget = 0;

  void _tickSettle() {
    if (!_settling) return;
    final t = pageSlideEaseOutQuad(_settle.value);
    _offset.value = _settleStart + (_settleTarget - _settleStart) * t;
  }
}
