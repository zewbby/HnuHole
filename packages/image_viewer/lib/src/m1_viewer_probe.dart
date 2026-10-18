import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Only the M1 spike uses this data model. No business API is implied.
class ProbeImage {
  const ProbeImage(this.id, this.provider, this.pixelSize);
  final String id;
  final ImageProvider provider;
  final Size pixelSize;
}

class ProbeMetrics {
  final Map<String, int> frames = {};
  final Map<String, ImageStreamCompleter> streams = {};
  final Map<String, Object> lastFrames = {};
  int slideUpdates = 0;
  int closed = 0;
  double maxSlideDistance = 0;
}

/// Tests the real upstream layout/gesture/stream behavior via public APIs.
class M1ViewerProbe extends StatefulWidget {
  const M1ViewerProbe({
    required this.images,
    required this.metrics,
    this.initialIndex = 0,
    this.active = true,
    this.onClosed,
    super.key,
  });
  final List<ProbeImage> images;
  final ProbeMetrics metrics;
  final int initialIndex;
  final bool active;
  final VoidCallback? onClosed;
  @override
  State<M1ViewerProbe> createState() => M1ViewerProbeState();
}

class M1ViewerProbeState extends State<M1ViewerProbe>
    with WidgetsBindingObserver {
  late final PageController _pages;
  Drag? _pageDrag;
  bool _pageEligible = false;
  VelocityTracker? _velocity;
  late final ValueNotifier<int> _visibleIndex;
  final _slide = GlobalKey<ExtendedImageSlidePageState>();
  late final List<GlobalKey<ExtendedImageGestureState>> _gestures;
  final Set<int> _pointers = {};
  late int index;
  bool _foreground = true;
  bool _eligible = false;
  bool _slideEnabled = false;
  bool _rejected = false;
  Offset? _start;
  double baseline = 1;
  double get scale =>
      _gestures[index].currentState?.gestureDetails?.totalScale ?? baseline;
  bool get atTop {
    final d = _gestures[index].currentState?.gestureDetails;
    if (d?.destinationRect == null || d?.layoutRect == null) return false;
    return d!.destinationRect!.top >= d.layoutRect!.top - 0.5;
  }

  Rect? get imageRect =>
      _gestures[index].currentState?.gestureDetails?.destinationRect;
  Offset get slideOffset => _slide.currentState?.offset ?? Offset.zero;
  bool get eligible => _eligible;
  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    _visibleIndex = ValueNotifier(index);
    _pages = PageController(initialPage: index);
    _gestures = List.generate(
      widget.images.length,
      (_) => GlobalKey<ExtendedImageGestureState>(),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {
        _foreground = state == AppLifecycleState.resumed;
        if (!_foreground) {
          _cancelSlide();
          _cancelPage();
        }
      });
    }
  }

  @override
  void didUpdateWidget(M1ViewerProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _cancelSlide();
      _cancelPage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageDrag?.cancel();
    _visibleIndex.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length == 1) {
      _start = e.position;
      _pageEligible =
          (scale - baseline).abs() < 0.001 && widget.active && _foreground;
      _velocity = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.position);
      _rejected = false;
      _eligible =
          atTop &&
          (scale - baseline).abs() < 0.001 &&
          widget.active &&
          _foreground;
    } else {
      _rejected = true;
      _pageEligible = false;
      _pageDrag?.cancel();
      _pageDrag = null;
      _eligible = false;
      _cancelSlide();
    }
  }

  void _move(PointerMoveEvent e) {
    if (_pointers.length != 1 || _start == null) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    final delta = e.position - _start!;
    if (_pageEligible &&
        delta.dx.abs() > delta.dy.abs() &&
        delta.distance >= kTouchSlop) {
      _eligible = false;
      _rejected = true;
      _pageDrag ??= _pages.position.drag(
        DragStartDetails(globalPosition: e.position),
        () => _pageDrag = null,
      );
      _pageDrag?.update(
        DragUpdateDetails(
          globalPosition: e.position,
          delta: Offset(e.delta.dx, 0),
          primaryDelta: e.delta.dx,
        ),
      );
      return;
    }
    if (_pageDrag != null) return;
    // Lock a vertical reading gesture even when it started below the top.
    if (delta.distance >= kTouchSlop && delta.dy.abs() >= delta.dx.abs()) {
      _pageEligible = false;
    }
    if (!_eligible || _rejected) return;
    if (!_slideEnabled) {
      if (delta.distance < kTouchSlop) return;
      if (delta.dy <= 0 || delta.dy.abs() <= delta.dx.abs()) {
        _rejected = true;
        _eligible = false;
        _pageEligible = false;
        return;
      }
      _pageEligible = false;
      setState(() => _slideEnabled = true);
    }
    // Product eligibility, upstream slide rendering and Flutter drag physics.
    // No recognizer fork, image decoding or scroll physics are reimplemented.
    _slide.currentState?.slide(Offset(0, e.delta.dy));
  }

  void _up(PointerEvent e) {
    final drag = _pageDrag;
    if (drag != null) {
      final vx = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
      drag.end(
        DragEndDetails(
          primaryVelocity: vx,
          velocity: Velocity(pixelsPerSecond: Offset(vx, 0)),
        ),
      );
      _pageDrag = null;
    }
    final s = _slide.currentState;
    if (s?.isSliding ?? false) s!.endSlide(ScaleEndDetails());
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      _eligible = false;
      _start = null;
      if (mounted) setState(() => _slideEnabled = false);
    }
  }

  void _cancelSlide() {
    _eligible = false;
    final s = _slide.currentState;
    if (s?.isSliding ?? false) s!.endSlide(ScaleEndDetails());
    _slideEnabled = false;
  }

  void _cancelPage() {
    _pageEligible = false;
    _pageDrag?.cancel();
    _pageDrag = null;
  }

  void resetImage() => _gestures[index].currentState?.reset();
  void zoomForProbe(double factor) {
    final g = _gestures[index].currentState;
    g?.handleDoubleTap(
      scale: baseline * factor,
      doubleTapPosition: const Offset(200, 200),
    );
  }

  void nextForProbe() {
    if (index + 1 < widget.images.length) {
      _pages.jumpToPage(index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const Center(child: Text('访问已失效'));
    return TickerMode(
      enabled: _foreground && widget.active,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          final current = widget.images[index].pixelSize;
          baseline = math.max(
            1,
            (size.width / current.width) /
                math.min(
                  size.width / current.width,
                  size.height / current.height,
                ),
          );
          return ExtendedImageSlidePage(
            key: _slide,
            slideAxis: SlideAxis.vertical,
            slideType: SlideType.wholePage,
            resetPageDuration: const Duration(milliseconds: 120),
            slideOffsetHandler: (
              offset, {
              ExtendedImageSlidePageState? state,
            }) => _eligible ? Offset(0, math.max(0, offset.dy)) : Offset.zero,
            slideScaleHandler: (offset, {ExtendedImageSlidePageState? state}) =>
                _eligible
                ? (1 - offset.dy.abs() / size.height * 0.3).clamp(0.7, 1)
                : 1,
            slidePageBackgroundHandler: (offset, pageSize) => Colors.black,
            slideEndHandler:
                (
                  offset, {
                  ExtendedImageSlidePageState? state,
                  ScaleEndDetails? details,
                }) {
                  final close = _eligible && !_rejected && offset.dy >= 100;
                  if (close) {
                    widget.metrics.closed++;
                    widget.onClosed?.call();
                  }
                  return close;
                },
            onSlidingPage: (state) {
              widget.metrics.slideUpdates++;
              widget.metrics.maxSlideDistance = math.max(
                widget.metrics.maxSlideDistance,
                state.offset.distance,
              );
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: (e) {
                _cancelSlide();
                _cancelPage();
                _up(e);
              },
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.images.length,
                // Position.drag() remains Flutter's implementation; built-in
                // recognition is disabled so there is one product eligibility gate.
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) => setState(() {
                  index = value;
                  _visibleIndex.value = value;
                  _eligible = false;
                  _slideEnabled = false;
                }),
                itemBuilder: (context, i) {
                  final item = widget.images[i];
                  final contain = math.min(
                    size.width / item.pixelSize.width,
                    size.height / item.pixelSize.height,
                  );
                  final base = math.max(
                    1.0,
                    size.width / item.pixelSize.width / contain,
                  );
                  return ValueListenableBuilder<int>(
                    valueListenable: _visibleIndex,
                    builder: (context, visibleIndex, child) =>
                        TickerMode(enabled: i == visibleIndex, child: child!),
                    child: ExtendedImage(
                      key: ValueKey('probe-surface-$i'),
                      image: item.provider,
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.gesture,
                      extendedImageGestureKey: _gestures[i],
                      enableSlideOutPage: false,
                      onDoubleTap: (gesture) {
                        final base = gesture.imageGestureConfig!.initialScale;
                        gesture.handleDoubleTap(
                          scale:
                              gesture.gestureDetails!.totalScale! > base + 0.001
                              ? base
                              : base * 2,
                        );
                      },
                      clearMemoryCacheWhenDispose: true,
                      initGestureConfigHandler: (_) => GestureConfig(
                        initialScale: base,
                        minScale: base,
                        maxScale: base * 4,
                        animationMinScale: base,
                        animationMaxScale: base * 4,
                        initialAlignment: InitialAlignment.topCenter,
                        inPageView: false,
                        inertialSpeed: 100,
                      ),
                      loadStateChanged: (s) {
                        final frame = s.extendedImageInfo?.image;
                        if (frame != null &&
                            !identical(
                              widget.metrics.lastFrames[item.id],
                              frame,
                            )) {
                          widget.metrics.lastFrames[item.id] = frame;
                          widget.metrics.frames.update(
                            item.id,
                            (n) => n + 1,
                            ifAbsent: () => 1,
                          );
                          final stream = item.provider
                              .resolve(createLocalImageConfiguration(context))
                              .completer;
                          if (stream != null) {
                            widget.metrics.streams[item.id] = stream;
                          }
                        }
                        return null;
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
