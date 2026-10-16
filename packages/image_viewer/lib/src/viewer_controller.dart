part of 'viewer.dart';

typedef ViewerSourceLoader = Future<ViewerSource> Function();

/// Caller-authorized provider and its actual decoder-output pixel dimensions.
/// No credentials, URLs or long-lived private disk cache are created here.
class ViewerSource {
  ViewerSource({required this.provider, required Size pixelSize})
    : pixelSize = _validatedSize(pixelSize);

  final ImageProvider provider;
  final Size pixelSize;

  static Size _validatedSize(Size value) {
    if (!value.width.isFinite ||
        !value.height.isFinite ||
        value.width <= 0 ||
        value.height <= 0 ||
        value.width != value.width.roundToDouble() ||
        value.height != value.height.roundToDouble()) {
      throw ArgumentError('Pixel dimensions must be finite positive integers.');
    }
    return value;
  }
}

/// A stable ID identifies the same content throughout one session.
/// Changed content must receive a new ID. Resolvers retain caller ownership.
class ViewerItem {
  ViewerItem({
    required String id,
    required this.loadSource,
    this.semanticLabel,
    this.resolveOriginal,
    this.saveAllowed = true,
  }) : id = _validatedId(id);

  factory ViewerItem.provider({
    required String id,
    required ImageProvider provider,
    required Size pixelSize,
    String? semanticLabel,
    ViewerOriginalResolver? resolveOriginal,
    bool saveAllowed = true,
  }) {
    final source = ViewerSource(provider: provider, pixelSize: pixelSize);
    return ViewerItem(
      id: id,
      loadSource: () async => source,
      semanticLabel: semanticLabel,
      resolveOriginal: resolveOriginal,
      saveAllowed: saveAllowed,
    );
  }

  final String id;
  final ViewerSourceLoader loadSource;
  final String? semanticLabel;
  final ViewerOriginalResolver? resolveOriginal;
  final bool saveAllowed;

  static String _validatedId(String id) {
    if (id.isEmpty || id.trim() != id) {
      throw ArgumentError('A stable ID must be nonempty without outer spaces.');
    }
    return id;
  }
}

enum ViewerLoadStatus { idle, loading, ready, failed }

enum ViewerFailure { sourceFailed, invalidSource, decodeFailed, resourceLimit }

enum ViewerCloseReason {
  button,
  gesture,
  systemBack,
  accessInvalidated,
  detached,
}

/// Relative baseline zoom and the image point at the viewport center.
class ViewerReadingPosition {
  const ViewerReadingPosition({
    required this.zoomFactor,
    required this.normalizedAnchor,
  });
  final double zoomFactor;
  final Offset normalizedAnchor;
}

/// Safe callback data. It never contains providers, original paths or errors.
class ViewerSnapshot {
  const ViewerSnapshot({
    required this.itemId,
    required this.index,
    required this.itemCount,
    required this.status,
    required this.failure,
    required this.active,
    required this.foreground,
    required this.generation,
    required this.selectionRevision,
    required this.closeReason,
  });
  final String itemId;
  final int index;
  final int itemCount;
  final ViewerLoadStatus status;
  final ViewerFailure? failure;
  final bool active;
  final bool foreground;
  final int generation;
  final int selectionRevision;
  final ViewerCloseReason? closeReason;
}

/// One viewing session, attached to at most one [HnuImageViewer].
///
/// Only the selected item loads. Source work is logically cancelled, never
/// claimed physically cancelled: late results are ignored. Replacement clears
/// reading positions; retry keeps the same-content position. Close, access
/// invalidation and widget removal are terminal. The caller must dispose this.
class ViewerController extends ChangeNotifier {
  ViewerController({
    required List<ViewerItem> items,
    int initialIndex = 0,
    this.resourceLimits = const ViewerResourceLimits(),
  }) : _items = _validatedItems(items, initialIndex),
       _index = initialIndex {
    resourceLimits._validate();
  }

  final ViewerResourceLimits resourceLimits;
  ViewerResourceUsage? _resourceUsage;
  ViewerResourceUsage? get resourceUsage => _resourceUsage;
  ImageProvider? _limitedProvider;

  List<ViewerItem> _items;
  int _index;
  int _generation = 0;
  int _selectionRevision = 0;
  int _attempt = 0;
  bool _accessValid = true;
  bool _foreground = true;
  bool _disposed = false;
  ViewerCloseReason? _closeReason;
  ViewerLoadStatus _status = ViewerLoadStatus.idle;
  ViewerFailure? _failure;
  ViewerSource? _source;
  Object? _owner;
  Object? _surfaceOwner;
  VoidCallback? _captureReading;
  final Map<String, ViewerReadingPosition> _reading = {};

  List<ViewerItem> get items => _items;
  int get index => _index;
  ViewerItem get currentItem => _items[_index];
  int get generation => _generation;
  int get selectionRevision => _selectionRevision;
  bool get accessValid => _accessValid;
  bool get foreground => _foreground;
  bool get active => !_disposed && _accessValid && _closeReason == null;
  ViewerLoadStatus get status => _status;
  ViewerFailure? get failure => _failure;
  ViewerCloseReason? get closeReason => _closeReason;
  ViewerReadingPosition? readingPosition(String id) => _reading[id];
  ViewerSnapshot get snapshot => ViewerSnapshot(
    itemId: currentItem.id,
    index: index,
    itemCount: items.length,
    status: status,
    failure: failure,
    active: active,
    foreground: foreground,
    generation: generation,
    selectionRevision: selectionRevision,
    closeReason: closeReason,
  );

  static List<ViewerItem> _validatedItems(List<ViewerItem> items, int index) {
    if (items.isEmpty || index < 0 || index >= items.length) {
      throw ArgumentError('The group must be nonempty and index in range.');
    }
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw ArgumentError('Stable IDs must be unique within the group.');
    }
    return List<ViewerItem>.unmodifiable(items);
  }

  void _attach(Object owner) {
    if (!active || _owner != null) {
      throw StateError('Use one active controller for one attached viewer.');
    }
    _owner = owner;
  }

  void _detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _terminate(ViewerCloseReason.detached, notify: false);
    _captureReading = null;
    _surfaceOwner = null;
  }

  bool _current(int generation, int selection, int attempt) =>
      active &&
      foreground &&
      _owner != null &&
      generation == _generation &&
      selection == _selectionRevision &&
      attempt == _attempt;

  Future<void> _loadCurrent() async {
    if (!active ||
        !foreground ||
        _owner == null ||
        _status != ViewerLoadStatus.idle) {
      return;
    }
    final generation = _generation;
    final selection = _selectionRevision;
    final attempt = ++_attempt;
    final item = currentItem;
    _status = ViewerLoadStatus.loading;
    _failure = null;
    notifyListeners();
    try {
      final source = await item.loadSource();
      if (!_current(generation, selection, attempt)) return;
      resourceLimits._checkPixels(
        source.pixelSize.width.toInt(),
        source.pixelSize.height.toInt(),
      );
      _limitedProvider = _LimitedImageProvider(
        source.provider,
        resourceLimits,
        (usage) {
          // Diagnostics must not hide decoder work while in the background.
          // Lifecycle revisions change, but this still belongs to the same
          // current source. It emits no notification or scheduled UI frame.
          if (active &&
              _owner != null &&
              generation == _generation &&
              identical(_source, source) &&
              currentItem.id == item.id) {
            _resourceUsage = usage;
          }
        },
      );
      _source = source;
      // The provider still has to decode. Ready is reported by the surface only
      // after a real frame matches the declared pixel dimensions.
    } catch (error) {
      if (!_current(generation, selection, attempt)) return;
      _source = null;
      _limitedProvider = null;
      _resourceUsage = null;
      _status = ViewerLoadStatus.failed;
      _failure = error is _ResourceLimitExceeded
          ? ViewerFailure.resourceLimit
          : ViewerFailure.sourceFailed;
    }
    notifyListeners();
  }

  void select(int index) {
    if (!active) return;
    if (index < 0 || index >= _items.length) {
      throw RangeError.index(index, _items);
    }
    if (index == _index) return;
    _captureReading?.call();
    _index = index;
    _selectionRevision++;
    _attempt++;
    _source = null;
    _limitedProvider = null;
    _resourceUsage = null;
    _status = ViewerLoadStatus.idle;
    _failure = null;
    notifyListeners();
    _loadCurrent();
  }

  void replaceItems(List<ViewerItem> items, {int initialIndex = 0}) {
    final validated = _validatedItems(items, initialIndex);
    if (!active) throw StateError('A finished session cannot be replaced.');
    _captureReading?.call();
    _items = validated;
    _index = initialIndex;
    _generation++;
    _selectionRevision++;
    _attempt++;
    _reading.clear();
    _source = null;
    _limitedProvider = null;
    _resourceUsage = null;
    _status = ViewerLoadStatus.idle;
    _failure = null;
    notifyListeners();
    _loadCurrent();
  }

  void retry() {
    if (!active || !foreground || _status != ViewerLoadStatus.failed) return;
    _attempt++;
    _source = null;
    _limitedProvider = null;
    _resourceUsage = null;
    _status = ViewerLoadStatus.idle;
    _failure = null;
    _loadCurrent();
  }

  void _reportFailure(
    ViewerFailure failure,
    int generation,
    int selection,
    int attempt,
  ) {
    if (!_current(generation, selection, attempt)) return;
    _source = null;
    _limitedProvider = null;
    _resourceUsage = null;
    _status = ViewerLoadStatus.failed;
    _failure = failure;
    notifyListeners();
  }

  void _reportReady(
    ViewerSource source,
    int generation,
    int selection,
    int attempt,
  ) {
    if (!_current(generation, selection, attempt) ||
        !identical(_source, source) ||
        _status != ViewerLoadStatus.loading) {
      return;
    }
    _status = ViewerLoadStatus.ready;
    notifyListeners();
  }

  void _setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _captureReading?.call();
    _foreground = value;
    _selectionRevision++;
    if (_status == ViewerLoadStatus.loading) {
      _attempt++;
      _source = null;
      _limitedProvider = null;
      _resourceUsage = null;
      _status = ViewerLoadStatus.idle;
    }
    if (_owner != null) notifyListeners();
    if (value) _loadCurrent();
  }

  void invalidateAccess() {
    if (!active) return;
    _accessValid = false;
    _terminate(ViewerCloseReason.accessInvalidated);
  }

  void close([ViewerCloseReason reason = ViewerCloseReason.button]) {
    if (!active) return;
    _terminate(reason);
  }

  void _terminate(ViewerCloseReason reason, {bool notify = true}) {
    if (_closeReason != null) return;
    _captureReading?.call();
    _closeReason = reason;
    _generation++;
    _selectionRevision++;
    _attempt++;
    _source = null;
    _limitedProvider = null;
    _resourceUsage = null;
    _status = ViewerLoadStatus.idle;
    _failure = null;
    _reading.clear();
    if (notify && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _terminate(ViewerCloseReason.detached);
    _owner = null;
    _captureReading = null;
    _surfaceOwner = null;
    _disposed = true;
    super.dispose();
  }
}
