import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as hashes;
import 'package:image_picker/image_picker.dart';

import 'post_upload_models.dart';

class PostPickedFile {
  PostPickedFile({required this.length, required this.openRead});
  final Future<int> Function() length;
  final Stream<List<int>> Function() openRead;
}

abstract interface class PostPhotoPicker {
  Future<List<PostPickedFile>> pick(int limit);
  Future<void> discardUnboundLostSelection();
}

class NativePostPhotoPicker implements PostPhotoPicker {
  final _picker = ImagePicker();
  @override
  Future<List<PostPickedFile>> pick(int limit) async {
    // The locked iOS adapter re-encodes via UIImage/CGImageDestination (including
    // GIF timing/loop changes). Keep that platform gated instead of silently
    // violating the original-format contract. No native fork is introduced.
    if (!Platform.isAndroid) throw const PostPhotoSelectionUnavailable();
    if (limit == 1) {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      return file == null
          ? []
          : [PostPickedFile(length: file.length, openRead: file.openRead)];
    }
    return [
      for (final file in await _picker.pickMultiImage(
        limit: limit,
        requestFullMetadata: false,
      ))
        PostPickedFile(length: file.length, openRead: file.openRead),
    ];
  }

  @override
  Future<void> discardUnboundLostSelection() async {
    // The native lost-data queue has no account/request binding. Never attach
    // those files to whoever happens to be signed in after process restoration.
    if (Platform.isAndroid) await _picker.retrieveLostData();
  }
}

class PostPhotoSelectionUnavailable implements Exception {
  const PostPhotoSelectionUnavailable();
  @override
  String toString() => 'Original photo selection unavailable on this platform';
}

/// Bounded preflight with Flutter's existing decoder. Originals are untouched;
/// server-side whole-container validation remains authoritative.
Future<({PostImageSelection selection, Uint8List bytes})> inspectPostPhoto(
  PostPickedFile file,
  String mediaId,
) async {
  const max = 10 * 1024 * 1024;
  final size = await file.length();
  if (size < 1 || size > max) {
    throw const FormatException('Image size unsupported');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (builder.length + chunk.length > max) {
      throw const FormatException('Image too large');
    }
    builder.add(chunk);
  }
  final bytes = builder.takeBytes();
  if (bytes.length != size) {
    throw const FormatException('Image changed while reading');
  }
  bool starts(List<int> signature) =>
      bytes.length >= signature.length &&
      List.generate(
        signature.length,
        (i) => bytes[i] == signature[i],
      ).every((v) => v);
  final mime = starts([137, 80, 78, 71, 13, 10, 26, 10])
      ? 'image/png'
      : starts([255, 216, 255])
      ? 'image/jpeg'
      : starts([71, 73, 70, 56])
      ? 'image/gif'
      : bytes.length >= 12 &&
            starts([82, 73, 70, 70]) &&
            String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
      ? 'image/webp'
      : null;
  if (mime == null) throw const FormatException('Unsupported original format');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  int width, height;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    width = descriptor.width;
    height = descriptor.height;
    // SOF is encoded JPEG geometry, independent of EXIF display orientation.
    if (mime == 'image/jpeg') {
      final size = _jpegGeometry(bytes);
      width = size.$1;
      height = size.$2;
    }
    if (width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        width * height > 12 * 1024 * 1024) {
      throw const FormatException('Image pixel budget exceeded');
    }
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount > 120 ||
        codec.frameCount > 1 &&
            (mime == 'image/png' ||
                width * height > 1024 * 1024 ||
                width * height * codec.frameCount > 16 * 1024 * 1024)) {
      throw const FormatException('Animation budget exceeded');
    }
    var cycle = Duration.zero;
    for (var i = 0; i < codec.frameCount; i++) {
      final frame = await codec.getNextFrame();
      try {
        if (!((frame.image.width == width && frame.image.height == height) ||
            (frame.image.width == height && frame.image.height == width))) {
          throw const FormatException('Invalid decoded geometry');
        }
        if (codec.frameCount > 1) {
          final duration = frame.duration < const Duration(milliseconds: 100)
              ? const Duration(milliseconds: 100)
              : frame.duration;
          cycle += duration;
          if (duration > const Duration(seconds: 15) ||
              cycle > const Duration(seconds: 60)) {
            throw const FormatException('Animation time budget exceeded');
          }
        }
      } finally {
        frame.image.dispose();
      }
    }
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
  return (
    selection: PostImageSelection.fromJson({
      'mediaId': mediaId,
      'sha256': hashes.sha256.convert(bytes).toString(),
      'byteLength': bytes.length,
      'mimeType': mime,
      'width': width,
      'height': height,
    }),
    bytes: bytes,
  );
}

(int, int) _jpegGeometry(Uint8List bytes) {
  var at = 2;
  while (at + 3 < bytes.length) {
    if (bytes[at++] != 255) throw const FormatException('Invalid JPEG marker');
    while (at < bytes.length && bytes[at] == 255) {
      at++;
    }
    if (at >= bytes.length) break;
    final marker = bytes[at++];
    if (marker == 217 || marker == 218) break;
    if (marker == 1 || marker >= 208 && marker <= 215) continue;
    if (at + 2 > bytes.length) break;
    final length = bytes[at] * 256 + bytes[at + 1];
    if (length < 2 || at + length > bytes.length) break;
    if ({
      192,
      193,
      194,
      195,
      197,
      198,
      199,
      201,
      202,
      203,
      205,
      206,
      207,
    }.contains(marker)) {
      if (length < 8) break;
      return (
        bytes[at + 5] * 256 + bytes[at + 6],
        bytes[at + 3] * 256 + bytes[at + 4],
      );
    }
    at += length;
  }
  throw const FormatException('Missing JPEG geometry');
}
