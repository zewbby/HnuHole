import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../posts/post_photo_picker.dart';

/// Avatars are normalized static previews, unlike original post attachments.
/// Decode and re-encode so gallery-added trailers and metadata are not uploaded.
Future<Uint8List> prepareIdentityAvatar(PostPickedFile file, String id) async {
  if (await file.length() > 5 * 1024 * 1024) {
    throw const FormatException('Avatar too large');
  }
  final inspected = await inspectPostPhoto(file, id);
  final codec = await ui.instantiateImageCodec(inspected.bytes);
  try {
    if (codec.frameCount != 1) {
      throw const FormatException('Avatar must be static');
    }
    final frame = await codec.getNextFrame();
    try {
      final source = frame.image;
      final scale = math.min(1.0, 640 / math.max(source.width, source.height));
      final width = math.max(1, (source.width * scale).round());
      final height = math.max(1, (source.height * scale).round());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(width, height);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) {
            throw const FormatException('Avatar encoding failed');
          }
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
