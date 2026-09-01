import 'package:flutter/material.dart';

/// Slides adjacent pages across one shared seam using a single animation.
///
/// Both pages use the same eased progress, so the outgoing trailing edge and
/// incoming leading edge remain attached throughout the transition.
class PageSlideSwitcher extends StatefulWidget {
  const PageSlideSwitcher({
    required this.child,
    required this.direction,
    this.duration = const Duration(milliseconds: 240),
    super.key,
  });

  final Widget child;
  final int direction;
  final Duration duration;

  @override
  State<PageSlideSwitcher> createState() => _PageSlideSwitcherState();
}

class _PageSlideSwitcherState extends State<PageSlideSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addStatusListener(_handleAnimationStatus);
  late Widget _currentChild = widget.child;
  Widget? _outgoingChild;
  int _direction = 1;

  @override
  void didUpdateWidget(PageSlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.child.key == widget.child.key) {
      _currentChild = widget.child;
      return;
    }
    _outgoingChild = _currentChild;
    _currentChild = widget.child;
    _direction = widget.direction < 0 ? -1 : 1;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _outgoingChild == null) return;
    setState(() => _outgoingChild = null);
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = Curves.easeOutCubic.transform(_controller.value);
          final width = constraints.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_outgoingChild case final outgoing?)
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(-_direction * width * progress, 0),
                      child: outgoing,
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(_direction * width * (1 - progress), 0),
                child: _currentChild,
              ),
            ],
          );
        },
      ),
    ),
  );
}
