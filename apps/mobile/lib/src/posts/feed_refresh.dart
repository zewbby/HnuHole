import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../navigation/feed_chrome.dart';

/// The current pull determines whether releasing refreshes. A pull owns its
/// entire pointer sequence, including reversal, independently of reading chrome.
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
  static const _triggerDistance = 128.0;
  int? _pointer;
  double _distance = 0;
  bool _pulling = false;
  bool _refreshing = false;

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

  void _finish(int pointer, {bool canceled = false}) {
    if (_pointer != pointer) return;
    _pointer = null;
    if (!_pulling) return;
    final refresh =
        !canceled && widget.enabled && _distance >= _triggerDistance;
    _pulling = false;
    _rebound();
    if (refresh) unawaited(_refresh());
  }

  void _pullBy(double delta) {
    // Extra travel beyond the visible stretch must not create invisible debt
    // that the user would have to undo before cancellation becomes possible.
    _distance = (_distance + delta).clamp(0, _stretch.upperBound * 2);
    _stretch.value = (_distance * .5).clamp(0, 112);
    widget.chrome.show();
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
    if (notice.depth != 0 ||
        notice.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    if (notice is ScrollStartNotification && notice.dragDetails != null) {
      widget.chrome.beginDrag();
    }
    if (notice is ScrollUpdateNotification && notice.dragDetails != null) {
      final delta = notice.scrollDelta ?? 0;
      if (_pulling) {
        _pullBy(-delta);
      } else {
        widget.chrome.scroll(delta, notice.metrics.pixels);
      }
    }
    if (notice is OverscrollNotification &&
        notice.dragDetails != null &&
        _pointer != null &&
        !_refreshing &&
        widget.enabled) {
      if (!_pulling &&
          notice.metrics.extentBefore == 0 &&
          notice.overscroll < 0) {
        _pulling = true;
        _distance = 0;
        _stretch.stop();
      }
      // Positive overscroll is also reversal on a short or empty list.
      if (_pulling) _pullBy(-notice.overscroll);
    }
    if (notice is ScrollEndNotification) {
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
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => _pointer ??= event.pointer,
    onPointerUp: (event) => _finish(event.pointer),
    onPointerCancel: (event) => _finish(event.pointer, canceled: true),
    child: NotificationListener<ScrollNotification>(
      key: const ValueKey('feed-refresh'),
      onNotification: _scroll,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: (notice) {
          if (notice.depth == 0 && notice.leading && widget.enabled) {
            notice.disallowIndicator();
          }
          return false;
        },
        child: AnimatedBuilder(
          animation: _stretch,
          builder: (context, _) =>
              widget.builder(context, _stretch.value, _refreshing),
        ),
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
  late final _highlight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _reducedMotion = false;

  void _updateAnimation() {
    if (widget.loading && !_reducedMotion) {
      if (!_highlight.isAnimating) _highlight.repeat();
    } else {
      _highlight.stop();
      _highlight.value = 0;
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
    _highlight.dispose();
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
            child: AnimatedBuilder(
              animation: _highlight,
              builder: (context, child) => widget.loading
                  ? ShaderMask(
                      key: const ValueKey('feed-refresh-glyph-highlight'),
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => SweepGradient(
                        colors: [
                          p.secondary.withValues(alpha: .5),
                          p.secondary.withValues(alpha: .5),
                          p.ink,
                          p.ink,
                          p.secondary.withValues(alpha: .5),
                          p.secondary.withValues(alpha: .5),
                        ],
                        stops: const [0, .12, .20, .34, .42, 1],
                        transform: GradientRotation(
                          _highlight.value * math.pi * 2,
                        ),
                      ).createShader(bounds),
                      child: child,
                    )
                  : child!,
              child: Center(
                child: Text(
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
                    // Let the shader supply loading colors without multiplying
                    // its opacity by the faded resting glyph a second time.
                    color: widget.loading
                        ? Colors.white
                        : Color.lerp(
                            p.accent,
                            p.secondary.withValues(alpha: .5),
                            amount,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
