import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../navigation/feed_chrome.dart';

/// Retains Material's threshold/cancellation/single-flight gesture handling,
/// while moving its visual feedback into the existing header.
class FeedRefresh extends StatefulWidget {
  const FeedRefresh({
    super.key,
    required this.chrome,
    required this.onRefresh,
    required this.builder,
    this.enabled = true,
  });
  final FeedChromeController chrome;
  final Future<void> Function() onRefresh;
  final bool enabled;
  final Widget Function(BuildContext, double pull, bool refreshing) builder;

  @override
  State<FeedRefresh> createState() => _FeedRefreshState();
}

class _FeedRefreshState extends State<FeedRefresh>
    with SingleTickerProviderStateMixin {
  late final _stretch = AnimationController(
    vsync: this,
    upperBound: 112,
    duration: const Duration(milliseconds: 320),
  );
  RefreshIndicatorStatus? _status;
  double _distance = 0;
  bool _refreshing = false;
  bool get _dragging =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;

  void _rebound() {
    _distance = 0;
    _stretch.animateTo(
      0,
      curve: Curves.easeOutCubic,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
    );
  }

  void _statusChanged(RefreshIndicatorStatus? status) {
    _status = status;
    if (status == RefreshIndicatorStatus.snap) {
      widget.chrome.refreshing(true);
      _rebound();
    } else if (status == RefreshIndicatorStatus.canceled ||
        status == RefreshIndicatorStatus.done) {
      widget.chrome.refreshing(false);
      _rebound();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || !widget.enabled) return;
    setState(() => _refreshing = true);
    widget.chrome.refreshing(true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        widget.chrome.refreshing(false);
        setState(() => _refreshing = false);
      }
    }
  }

  bool _scroll(ScrollNotification notice) {
    if (notice.depth != 0 || notice.metrics.axis != Axis.vertical) return false;
    if (notice is ScrollStartNotification && notice.dragDetails != null) {
      widget.chrome.beginDrag();
    }
    if (notice is ScrollUpdateNotification && notice.dragDetails != null) {
      final delta = notice.scrollDelta ?? 0;
      widget.chrome.scroll(delta, notice.metrics.pixels);
      if (_dragging && _distance > 0) {
        _distance = math.max(0, _distance - delta);
        _stretch.value = (_distance * .5).clamp(0, 112);
      }
    }
    if (notice is OverscrollNotification &&
        notice.dragDetails != null &&
        notice.metrics.extentBefore == 0 &&
        notice.overscroll < 0 &&
        _dragging) {
      widget.chrome.show();
      _distance -= notice.overscroll;
      _stretch.value = (_distance * .5).clamp(0, 112);
    }
    if (notice is ScrollEndNotification) {
      if (_stretch.value > 0) _rebound();
      // A fling ending at the top restores chrome, never a bottom bounce.
      if (notice.metrics.pixels <= 0) widget.chrome.show();
    }
    return false;
  }

  @override
  void dispose() {
    _stretch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _scroll,
        child: RefreshIndicator.noSpinner(
          key: const ValueKey('feed-refresh'),
          triggerMode: RefreshIndicatorTriggerMode.anywhere,
          notificationPredicate: (notice) =>
              notice.depth == 0 &&
              notice.metrics.axisDirection == AxisDirection.down &&
              (widget.enabled || _refreshing || _dragging),
          semanticsLabel: '刷新帖子',
          onRefresh: _refresh,
          onStatusChange: _statusChanged,
          child: AnimatedBuilder(
            animation: _stretch,
            builder: (context, _) =>
                widget.builder(context, _stretch.value, _refreshing),
          ),
        ),
      );
}

/// The face keeps the feed wordmark's Roboto bold, accent and compact spacing.
/// A single glyph run uses a tiny positive tracking value, without a space.
class FeedSmileMark extends StatefulWidget {
  const FeedSmileMark({super.key, required this.pull, required this.loading});
  final double pull;
  final bool loading;

  @override
  State<FeedSmileMark> createState() => _FeedSmileMarkState();
}

class _FeedSmileMarkState extends State<FeedSmileMark>
    with SingleTickerProviderStateMixin {
  late final _orbit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _reducedMotion = false;

  void _updateAnimation() {
    if (widget.loading && !_reducedMotion) {
      if (!_orbit.isAnimating) _orbit.repeat();
    } else {
      _orbit.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _updateAnimation();
  }

  @override
  void didUpdateWidget(FeedSmileMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    final amount = (widget.pull / 100).clamp(0.0, 1.0);
    return Semantics(
      label: widget.loading ? '正在刷新帖子' : 'HnuHole',
      liveRegion: widget.loading,
      child: ExcludeSemantics(
        child: Transform.scale(
          scale: 1 + amount * .45,
          child: SizedBox(
            key: const ValueKey('feed-smile-mark'),
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  ':)',
                  key: const ValueKey('feed-smile-text'),
                  textDirection: TextDirection.ltr,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: .6,
                    color: Color.lerp(
                      p.accent,
                      p.secondary.withValues(alpha: .5),
                      widget.loading ? 1 : amount,
                    ),
                  ),
                ),
                if (widget.loading)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _orbit,
                      builder: (context, _) => CustomPaint(
                        key: const ValueKey('feed-refresh-orbit'),
                        painter: _RefreshOrbit(_orbit.value, p.ink),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshOrbit extends CustomPainter {
  const _RefreshOrbit(this.phase, this.color);
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawArc(
    Rect.fromCircle(center: size.center(Offset.zero), radius: 18),
    phase * math.pi * 2 - math.pi / 2,
    math.pi * .75,
    false,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round,
  );

  @override
  bool shouldRepaint(_RefreshOrbit oldDelegate) =>
      phase != oldDelegate.phase || color != oldDelegate.color;
}
