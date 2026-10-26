part of 'viewer.dart';

/// Product eligibility around extended_image's public gesture/slide APIs.
/// Flutter still supplies image decoding, animation and page drag physics.
class _ViewerSurface extends StatefulWidget {
  const _ViewerSurface({
    required this.controller,
    required this.backgroundColor,
    required this.onDismissProgress,
    super.key,
  });
  final ViewerController controller;
  final Color backgroundColor;
  final ValueChanged<double> onDismissProgress;
  @override
  State<_ViewerSurface> createState() => _ViewerSurfaceState();
}

class _ViewerSurfaceState extends State<_ViewerSurface>
    with SingleTickerProviderStateMixin {
  late final PageController _pages;
  Drag? _pageDrag;
  VelocityTracker? _velocity;
  late final AnimationController _dismissAnimation;
  Offset _dismissOffset = Offset.zero;
  Offset _animationStart = Offset.zero, _animationEnd = Offset.zero;
  bool _dismissing = false;
  bool _canPullDown = false, _canPullUp = false;
  double get _dismissProgress => _lastSize == null
      ? 0
      : (_dismissOffset.dy.abs() / (_lastSize!.height * .7)).clamp(0, 1);
  GlobalKey<ExtendedImageGestureState> _gesture = GlobalKey();
  final Set<int> _pointers = {};
  bool _pageEligible = false;
  bool _eligible = false;
  bool _rejected = false;
  Offset? _start;
  Size? _lastSize;
  ViewerSource? _displaySource;
  String? _displayId;
  double _baseline = 1;
  bool _restorePending = false;
  bool _restoreScheduled = false;
  Object? _reportedFailure;
  Object? _reportedReady;
  int? _pointerRevision;

  ViewerController get _c => widget.controller;
  double get _scale =>
      _gesture.currentState?.gestureDetails?.totalScale ?? _baseline;
  bool get _atTop {
    final details = _gesture.currentState?.gestureDetails;
    if (details?.destinationRect == null || details?.layoutRect == null) {
      return false;
    }
    return details!.destinationRect!.top >= details.layoutRect!.top - 0.5;
  }

  bool get _atBottom {
    final details = _gesture.currentState?.gestureDetails;
    return details?.destinationRect != null &&
        details?.layoutRect != null &&
        details!.destinationRect!.bottom <= details.layoutRect!.bottom + .5;
  }

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: _c.index);
    _dismissAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final t = Curves.easeOutCubic.transform(_dismissAnimation.value);
          _setDismissOffset(Offset.lerp(_animationStart, _animationEnd, t)!);
        });
    _c._surfaceOwner = this;
    _c._captureReading = _captureReading;
  }

  @override
  void didUpdateWidget(_ViewerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_c.foreground || !_c.active) _cancel();
    if (_dismissOffset != Offset.zero &&
        _pointerRevision != _c.selectionRevision) {
      _cancel();
    }
    if (_pages.hasClients &&
        (_pages.page! - _c.index).abs() > 0.001 &&
        _pageDrag == null &&
        !_pages.position.isScrollingNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients && _pageDrag == null) {
          _pages.jumpToPage(_c.index);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageDrag?.cancel();
    if (_c._surfaceOwner == this) {
      _c._captureReading = null;
      _c._surfaceOwner = null;
    }
    _dismissAnimation.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _captureReading() {
    if (!_c.active || _displayId == null) return;
    if (_restorePending && _c._reading.containsKey(_displayId)) return;
    final details = _gesture.currentState?.gestureDetails;
    final rect = details?.destinationRect;
    final layout = details?.layoutRect;
    if (rect == null || layout == null || rect.width <= 0 || rect.height <= 0) {
      return;
    }
    _c._reading[_displayId!] = ViewerReadingPosition(
      zoomFactor: (_scale / _baseline).clamp(1, 4),
      normalizedAnchor: Offset(
        ((layout.center.dx - rect.left) / rect.width).clamp(0, 1),
        ((layout.center.dy - rect.top) / rect.height).clamp(0, 1),
      ),
    );
  }

  void _scheduleRestore((int, int, int) token, String id, ViewerSource source) {
    if (!_restorePending ||
        _restoreScheduled ||
        !_c._current(token.$1, token.$2, token.$3) ||
        !identical(source, _displaySource) ||
        id != _displayId) {
      return;
    }
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted ||
          !_c._current(token.$1, token.$2, token.$3) ||
          id != _displayId ||
          !identical(source, _displaySource)) {
        return;
      }
      final reading = _c._reading[id];
      final gesture = _gesture.currentState;
      final details = gesture?.gestureDetails;
      final raw = details?.rawDestinationRect;
      final layout = details?.layoutRect;
      if (gesture == null || raw == null || layout == null) {
        return;
      }
      if (reading == null) {
        _restorePending = false;
        _captureReading();
        return;
      }
      final scale = _baseline * reading.zoomFactor;
      final width = raw.width * scale;
      final height = raw.height * scale;
      final desiredCenter =
          layout.center +
          Offset(
            width * (0.5 - reading.normalizedAnchor.dx),
            height * (0.5 - reading.normalizedAnchor.dy),
          );
      final offset =
          desiredCenter -
          Offset(
            width >= layout.width ? raw.center.dx * scale : raw.center.dx,
            height >= layout.height ? raw.center.dy * scale : raw.center.dy,
          );
      gesture.gestureDetails = GestureDetails(
        totalScale: scale,
        offset: offset,
        gestureDetails: details,
        rawDestinationRect: raw,
      );
      _restorePending = false;
    });
  }

  void _down(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_dismissAnimation.isAnimating || _dismissing) {
      _rejected = true;
      return;
    }
    if (_pointers.length == 1) {
      _pointerRevision = _c.selectionRevision;
      _start = event.position;
      _pageEligible =
          _c.active &&
          _c.foreground &&
          (_displaySource == null || (_scale - _baseline).abs() < 0.001);
      _velocity = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.position);
      _rejected = false;
      _canPullDown = _atTop;
      _canPullUp = _atBottom;
      _eligible =
          (_canPullDown || _canPullUp) &&
          (_scale - _baseline).abs() < 0.001 &&
          _c.active &&
          _c.foreground &&
          _c.status == ViewerLoadStatus.ready &&
          _displayId == _c.currentItem.id;
    } else {
      _rejected = true;
      _cancel();
    }
  }

  void _move(PointerMoveEvent event) {
    if (_pointers.length != 1 || _start == null) return;
    if (_pointerRevision != _c.selectionRevision && _pageDrag == null) {
      _cancel();
      _rejected = true;
      return;
    }
    _velocity?.addPosition(event.timeStamp, event.position);
    final delta = event.position - _start!;
    if (_pageEligible &&
        delta.dx.abs() > delta.dy.abs() &&
        delta.distance >= kTouchSlop) {
      _eligible = false;
      _rejected = true;
      if (_pageDrag == null) {
        unawaited(_c._exposeNeighbor(_c.index + (delta.dx < 0 ? 1 : -1)));
      }
      _pageDrag ??= _pages.position.drag(
        DragStartDetails(globalPosition: event.position),
        () => _pageDrag = null,
      );
      _pageDrag?.update(
        DragUpdateDetails(
          globalPosition: event.position,
          delta: Offset(event.delta.dx, 0),
          primaryDelta: event.delta.dx,
        ),
      );
      return;
    }
    if (_pageDrag != null) return;
    if (delta.distance >= kTouchSlop && delta.dy.abs() >= delta.dx.abs()) {
      _pageEligible = false;
    }
    if (!_eligible || _rejected) return;
    if (delta.distance < kTouchSlop) return;
    if ((delta.dy > 0 ? !_canPullDown : !_canPullUp) ||
        delta.dy.abs() <= delta.dx.abs()) {
      _rejected = true;
      _eligible = false;
      _pageEligible = false;
      return;
    }
    _pageEligible = false;
    _setDismissOffset(Offset(delta.dx * .35, delta.dy));
  }

  void _up(PointerEvent event) {
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
    if (_dismissOffset != Offset.zero && !_dismissAnimation.isAnimating) {
      final velocity = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
      final threshold = ((_lastSize?.height ?? 600) * .18).clamp(100, 180);
      final commit =
          _eligible &&
          !_rejected &&
          _pointerRevision == _c.selectionRevision &&
          (_dismissOffset.dy.abs() >= threshold ||
              _dismissOffset.dy.abs() >= 36 &&
                  velocity.abs() >= 700 &&
                  velocity.sign == _dismissOffset.dy.sign);
      unawaited(_settleDismiss(commit));
    }
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _eligible = false;
      _start = null;
      _captureReading();
    }
  }

  void _cancel() {
    _eligible = false;
    _pageEligible = false;
    _pageDrag?.cancel();
    _pageDrag = null;
    _dismissAnimation.stop();
    _dismissing = false;
    if (_dismissOffset != Offset.zero) {
      _dismissOffset = Offset.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onDismissProgress(0);
          setState(() {});
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _setDismissOffset(Offset offset) {
    if (!mounted) return;
    setState(() => _dismissOffset = offset);
    widget.onDismissProgress(_dismissProgress);
  }

  Future<void> _settleDismiss(bool close) async {
    _dismissing = close;
    final revision = _c.selectionRevision;
    _animationStart = _dismissOffset;
    _animationEnd = close
        ? Offset(
            _dismissOffset.dx,
            _dismissOffset.dy.sign * (_lastSize!.height * .85),
          )
        : Offset.zero;
    try {
      await _dismissAnimation.forward(from: 0).orCancel;
      if (mounted &&
          close &&
          _c.active &&
          _c.foreground &&
          revision == _c.selectionRevision) {
        _c.close(ViewerCloseReason.gesture);
      }
    } on TickerCanceled {
      // Rotation, backgrounding and revocation must cancel an unfinished exit.
    }
  }

  void _report(ViewerFailure failure, (int, int, int) token) {
    if (_reportedFailure == token) return;
    _reportedFailure = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c._reportFailure(failure, token.$1, token.$2, token.$3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = _c._source;
    final selectedIndex = _c.index;
    final item = _c.currentItem;
    final token = (_c.generation, _c.selectionRevision, _c._attempt);
    if (!identical(_displaySource, source) || _displayId != item.id) {
      _displaySource = source;
      _displayId = item.id;
      _gesture = GlobalKey<ExtendedImageGestureState>();
      _reportedFailure = null;
      _reportedReady = null;
      _restorePending = true;
    }
    final gestureKey = _gesture;
    return TickerMode(
      enabled: _c.foreground && _c.active,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          if (_lastSize != null && _lastSize != size) {
            // Keep the last painted reading state. The upstream gesture can
            // already have reset its scale for an intermediate Android layout.
            if (!_c._reading.containsKey(_displayId)) _captureReading();
            _restorePending = true;
            // A rotation never grants close eligibility to an in-flight gesture.
            _cancel();
            _rejected = true;
          }
          _lastSize = size;
          if (source != null) {
            final contain = math.min(
              size.width / source.pixelSize.width,
              size.height / source.pixelSize.height,
            );
            _baseline = math.max(
              1,
              size.width / source.pixelSize.width / contain,
            );
          }
          final baseline = _baseline;
          return Transform.translate(
            key: const ValueKey('viewer-dismiss-transform'),
            offset: _dismissOffset,
            child: Transform.scale(
              scale: 1 - _dismissProgress * .28,
              child: Opacity(
                opacity: _dismissing ? 1 - _dismissProgress : 1,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: (event) {
                    _cancel();
                    _up(event);
                  },
                  child: PageView.builder(
                    key: const ValueKey('viewer-pages'),
                    controller: _pages,
                    itemCount: _c.items.length,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: _c.select,
                    itemBuilder: (context, index) {
                      final entry = _c._cache[_c.items[index].id];
                      if (!_c.active ||
                          token.$1 != _c.generation ||
                          token.$2 != _c.selectionRevision ||
                          token.$3 != _c._attempt ||
                          !identical(_c._source, source)) {
                        return const SizedBox.expand();
                      }
                      if (index != selectedIndex || source == null) {
                        if (!_c.foreground || entry == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return _ViewerPreview(
                          key: ValueKey(entry),
                          entry: entry,
                          reading: _c._reading[_c.items[index].id],
                        );
                      }
                      // Capture at construction: an old stream callback must never
                      // borrow the controller's newer selection/attempt identity.
                      return ExtendedImage(
                        key: ValueKey((item.id, token.$3, source)),
                        image: _c._limitedProvider ?? source.provider,
                        semanticLabel: item.semanticLabel ?? '第${index + 1}张图片',
                        fit: BoxFit.contain,
                        mode: ExtendedImageMode.gesture,
                        extendedImageGestureKey: gestureKey,
                        enableSlideOutPage: false,
                        clearMemoryCacheWhenDispose: false,
                        afterPaintImage: (_, _, image, _) {
                          if (_c._current(token.$1, token.$2, token.$3)) {
                            entry?.remember(image);
                          }
                          if (!_restorePending &&
                              _c._current(token.$1, token.$2, token.$3)) {
                            _captureReading();
                          }
                        },
                        onDoubleTap: (gesture) {
                          final base = gesture.imageGestureConfig!.initialScale;
                          gesture.handleDoubleTap(
                            scale:
                                gesture.gestureDetails!.totalScale! >
                                    base + 0.001
                                ? base
                                : base * 2,
                          );
                        },
                        initGestureConfigHandler: (_) => GestureConfig(
                          initialScale: baseline,
                          minScale: baseline,
                          maxScale: baseline * 4,
                          animationMinScale: baseline,
                          animationMaxScale: baseline * 4,
                          initialAlignment: baseline > 1
                              ? InitialAlignment.topCenter
                              : InitialAlignment.center,
                          inPageView: false,
                          cacheGesture: false,
                          inertialSpeed: 100,
                        ),
                        loadStateChanged: (state) {
                          if (state.extendedImageLoadState ==
                                  LoadState.loading &&
                              entry?.frame != null) {
                            return _ViewerPreview(
                              key: ValueKey(entry),
                              entry: entry!,
                              reading: _c._reading[item.id],
                            );
                          }
                          if (state.extendedImageLoadState ==
                              LoadState.failed) {
                            _report(
                              state.lastException is _ResourceLimitExceeded
                                  ? ViewerFailure.resourceLimit
                                  : ViewerFailure.decodeFailed,
                              token,
                            );
                            return const SizedBox.expand();
                          }
                          final image = state.extendedImageInfo?.image;
                          if (image != null) {
                            if (image.width != source.pixelSize.width ||
                                image.height != source.pixelSize.height) {
                              _report(ViewerFailure.invalidSource, token);
                              return const SizedBox.expand();
                            }
                            if (_reportedReady != token) {
                              _reportedReady = token;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  _c._reportReady(
                                    source,
                                    token.$1,
                                    token.$2,
                                    token.$3,
                                  );
                                }
                              });
                            }
                            _scheduleRestore(token, item.id, source);
                          }
                          return null;
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
