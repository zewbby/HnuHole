part of 'viewer.dart';

/// Conservative limits. These reject media; they never resize or convert it.
/// Providers must use Flutter's supplied decoder callback for predecode checks.
/// A custom provider emitting already-decoded images owns its own allocation
/// budget; the surface still checks the delivered pixel dimensions.
class ViewerResourceLimits {
  const ViewerResourceLimits({
    this.maxEncodedBytes = 16 * 1024 * 1024,
    this.maxPixels = 12 * 1024 * 1024,
    this.maxDimension = 16384,
    this.maxAnimationPixels = 1024 * 1024,
    this.maxAnimationTotalPixels = 16 * 1024 * 1024,
    this.maxFrames = 120,
    this.maxCycleDuration = const Duration(seconds: 60),
    this.maxFrameDuration = const Duration(seconds: 15),
  });
  final int maxEncodedBytes,
      maxPixels,
      maxDimension,
      maxAnimationPixels,
      maxAnimationTotalPixels,
      maxFrames;
  final Duration maxCycleDuration, maxFrameDuration;

  void _validate() {
    if ([
          maxEncodedBytes,
          maxPixels,
          maxDimension,
          maxAnimationPixels,
          maxAnimationTotalPixels,
          maxFrames,
        ].any((value) => value <= 0) ||
        maxCycleDuration <= Duration.zero ||
        maxFrameDuration <= Duration.zero) {
      throw ArgumentError('Resource limits must be positive.');
    }
  }

  void _checkPixels(int width, int height, {bool animated = false}) {
    if (width > maxDimension ||
        height > maxDimension ||
        width * height > (animated ? maxAnimationPixels : maxPixels)) {
      throw const _ResourceLimitExceeded();
    }
  }
}

/// Counts from the current Flutter decoder, never a process memory estimate.
/// The owner may sample these without scheduling extra animation frames.
class ViewerResourceUsage {
  const ViewerResourceUsage({
    required this.encodedBytes,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.decodedFrames,
  });
  final int encodedBytes, width, height, frameCount, decodedFrames;
}

class _ResourceLimitExceeded implements Exception {
  const _ResourceLimitExceeded();
  @override
  String toString() => 'Image resource limit exceeded';
}

class _LimitedImageKey<T extends Object> {
  const _LimitedImageKey(this.original, this.owner);
  final T original;
  final Object owner;
  @override
  bool operator ==(Object other) =>
      other is _LimitedImageKey<T> &&
      other.original == original &&
      identical(other.owner, owner);
  @override
  int get hashCode => Object.hash(original, owner);
}

/// Wraps public Flutter APIs; the delegate/engine still decodes every frame.
class _LimitedImageProvider<T extends Object>
    extends ImageProvider<_LimitedImageKey<T>> {
  _LimitedImageProvider(this.original, this.limits, this.onUsage);
  final ImageProvider<T> original;
  final ViewerResourceLimits limits;
  final ValueChanged<ViewerResourceUsage> onUsage;

  @override
  Future<_LimitedImageKey<T>> obtainKey(
    ImageConfiguration configuration,
  ) async => _LimitedImageKey(await original.obtainKey(configuration), this);

  @override
  ImageStreamCompleter loadImage(
    _LimitedImageKey<T> key,
    ImageDecoderCallback decode,
  ) => original.loadImage(key.original, (buffer, {getTargetSize}) async {
    final bytes = buffer.length;
    ui.ImageDescriptor? descriptor;
    int width, height;
    try {
      if (bytes > limits.maxEncodedBytes) throw const _ResourceLimitExceeded();
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      width = descriptor.width;
      height = descriptor.height;
      limits._checkPixels(width, height);
    } catch (_) {
      descriptor?.dispose();
      descriptor = null;
      buffer.dispose();
      rethrow;
    } finally {
      descriptor?.dispose();
    }
    // Decoder callback takes ownership of the buffer. No target resizing
    // is added; an existing caller-specified target is passed unchanged.
    final codec = await decode(buffer, getTargetSize: getTargetSize);
    try {
      limits._checkPixels(width, height, animated: codec.frameCount > 1);
      if (codec.frameCount > limits.maxFrames ||
          (codec.frameCount > 1 &&
              width * height * codec.frameCount >
                  limits.maxAnimationTotalPixels)) {
        throw const _ResourceLimitExceeded();
      }
    } catch (_) {
      codec.dispose();
      rethrow;
    }
    return _LimitedCodec(codec, limits, bytes, width, height, onUsage);
  });
}

class _LimitedCodec implements ui.Codec {
  _LimitedCodec(
    this.inner,
    this.limits,
    this.bytes,
    this.width,
    this.height,
    this.onUsage,
  );
  final ui.Codec inner;
  final ViewerResourceLimits limits;
  final int bytes, width, height;
  final ValueChanged<ViewerResourceUsage> onUsage;
  bool _disposed = false;
  int _frames = 0;
  Duration _cycle = Duration.zero;
  @override
  int get frameCount => inner.frameCount;
  @override
  int get repetitionCount => inner.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = await inner.getNextFrame();
    if (_disposed) {
      frame.image.dispose();
      // Flutter disposes and clears its codec, then checks that field
      // after this await. Release our late frame and let that cancellation path
      // finish; throwing here reports a spurious image error after route close.
      return frame;
    }
    _frames++;
    if (_frames <= frameCount) _cycle += frame.duration;
    if (frameCount > 1 &&
        (frame.duration > limits.maxFrameDuration ||
            _cycle > limits.maxCycleDuration)) {
      frame.image.dispose();
      dispose();
      throw const _ResourceLimitExceeded();
    }
    onUsage(
      ViewerResourceUsage(
        encodedBytes: bytes,
        width: width,
        height: height,
        frameCount: frameCount,
        decodedFrames: _frames,
      ),
    );
    return frame;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    inner.dispose();
  }
}
