part of 'viewer.dart';

class _ViewerCachedSource {
  _ViewerCachedSource(this.source, this.provider);
  final ViewerSource source;
  final ImageProvider provider;
  ViewerResourceUsage? usage;
  ui.Image? frame;
  bool _disposed = false;
  void remember(ui.Image image) {
    if (!_disposed) frame ??= image.clone();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(provider.evict());
    final image = frame;
    frame = null;
    // RawImage may still be in the old render tree until the next frame.
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }
}

/// Only an exposed neighbor decodes a still preview. Remove the stream listener
/// after its first frame so invisible GIF/WebP pages never keep playing.
class _ViewerPreview extends StatefulWidget {
  const _ViewerPreview({required this.entry, this.reading, super.key});
  final _ViewerCachedSource entry;
  final ViewerReadingPosition? reading;
  @override
  State<_ViewerPreview> createState() => _ViewerPreviewState();
}

class _ViewerPreviewState extends State<_ViewerPreview> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.entry.frame == null && _stream == null) {
      _stream = widget.entry.provider.resolve(
        createLocalImageConfiguration(context),
      );
      _listener = ImageStreamListener(
        (info, synchronous) {
          final size = widget.entry.source.pixelSize;
          if (info.image.width == size.width &&
              info.image.height == size.height) {
            widget.entry.remember(info.image);
          }
          info.dispose();
          _stream?.removeListener(_listener!);
          if (!synchronous && mounted) setState(() {});
        },
        onError: (Object error, StackTrace? stack) {
          _stream?.removeListener(_listener!);
        },
      );
      _stream!.addListener(_listener!);
    }
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: CustomPaint(
      painter: _ViewerPreviewPainter(widget.entry.frame, widget.reading),
      size: Size.infinite,
    ),
  );
}

class _ViewerPreviewPainter extends CustomPainter {
  _ViewerPreviewPainter(this.image, this.reading);
  final ui.Image? image;
  final ViewerReadingPosition? reading;
  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) return;
    final contain = math.min(
      size.width / image.width,
      size.height / image.height,
    );
    final baseline = math.max(contain, size.width / image.width);
    final scale = baseline * (reading?.zoomFactor ?? 1);
    final width = image.width * scale, height = image.height * scale;
    final anchor =
        reading?.normalizedAnchor ??
        Offset(.5, height > size.height ? size.height / (2 * height) : .5);
    final left = width <= size.width
        ? (size.width - width) / 2
        : (size.width / 2 - width * anchor.dx)
              .clamp(size.width - width, 0)
              .toDouble();
    final top = height <= size.height
        ? (size.height - height) / 2
        : (size.height / 2 - height * anchor.dy)
              .clamp(size.height - height, 0)
              .toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(left, top, width, height),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_ViewerPreviewPainter old) =>
      old.image != image || old.reading != reading;
}
