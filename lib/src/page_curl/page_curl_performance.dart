import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

class PageCurlPerformanceReport {
  const PageCurlPerformanceReport({
    required this.frameCount,
    required this.slowFrames,
    required this.p90FrameTime,
    required this.targetRefreshRate,
  });

  final int frameCount;
  final int slowFrames;
  final Duration p90FrameTime;
  final double targetRefreshRate;

  double get slowFrameRatio => frameCount == 0 ? 0 : slowFrames / frameCount;
  double get estimatedFps => p90FrameTime.inMicroseconds == 0
      ? 0
      : Duration.microsecondsPerSecond / p90FrameTime.inMicroseconds;
}

class PageCurlPerformanceMonitor {
  PageCurlPerformanceMonitor({this.onReport});

  final void Function(PageCurlPerformanceReport report)? onReport;
  final List<Duration> _frames = [];
  double _refreshRate = 60;
  bool _running = false;

  void start({double refreshRate = 60}) {
    if (_running) return;
    _refreshRate = refreshRate.isFinite && refreshRate > 0 ? refreshRate : 60;
    _frames.clear();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _running = true;
  }

  PageCurlPerformanceReport stop() {
    if (_running) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _running = false;
    }
    final report = calculate(_frames, refreshRate: _refreshRate);
    onReport?.call(report);
    return report;
  }

  void _onTimings(List<FrameTiming> timings) {
    _frames.addAll(
      timings.map((timing) => timing.buildDuration + timing.rasterDuration),
    );
  }

  static PageCurlPerformanceReport calculate(
    Iterable<Duration> samples, {
    double refreshRate = 60,
  }) {
    final frames = samples.toList()..sort();
    final safeRate = refreshRate.isFinite && refreshRate > 0
        ? refreshRate
        : 60.0;
    final budget = Duration(
      microseconds: (Duration.microsecondsPerSecond / safeRate).round(),
    );
    final p90Index = frames.isEmpty
        ? 0
        : math.min(frames.length - 1, (frames.length * .9).ceil() - 1);
    return PageCurlPerformanceReport(
      frameCount: frames.length,
      slowFrames: frames.where((frame) => frame > budget).length,
      p90FrameTime: frames.isEmpty ? Duration.zero : frames[p90Index],
      targetRefreshRate: safeRate,
    );
  }
}
