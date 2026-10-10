import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Conditional compatibility experiment only. Not exported or enabled by saver.
Uint8List compatibilityGifForProbe(
  Uint8List input, {
  bool allowLossyAlphaForDiagnostic = false,
}) {
  if (input.length > 1024 * 1024) {
    throw const FormatException('probe byte limit');
  }
  final decoder = image.WebPDecoder();
  final info = decoder.startDecode(input);
  if (info == null || !info.hasAnimation || info.numFrames < 2) {
    throw const FormatException('animated WebP required');
  }
  if (info.width > 1024 ||
      info.height > 1024 ||
      info.numFrames > 30 ||
      info.width * info.height * info.numFrames > 4000000) {
    throw const FormatException('probe decoded-pixel limit');
  }
  if (info.frames.any((f) => f.duration < 20) ||
      info.frames.fold<int>(0, (sum, f) => sum + f.duration) > 60000) {
    throw const FormatException('probe timing limit');
  }
  final decoded = decoder.decode(input);
  if (decoded == null || decoded.frames.length != info.numFrames) {
    throw const FormatException('incomplete frames');
  }
  final partialAlpha = decoded.frames.any(
    (f) => f.any((p) => p.a > 0 && p.a < 255),
  );
  if (partialAlpha && !allowLossyAlphaForDiagnostic) {
    throw const FormatException('semi-transparency requires product choice');
  }
  // WebP counts total plays, GIF counts repeats after the first play.
  decoded.loopCount = info.animLoopCount == 0 ? 0 : info.animLoopCount - 1;
  // GIF units are 10 ms. Round cumulative time to keep cycle drift <= 5 ms.
  var sourceMs = 0, assignedTicks = 0;
  for (final frame in decoded.frames) {
    sourceMs += frame.frameDuration;
    final ticks = (sourceMs / 10).round();
    frame.frameDuration = (ticks - assignedTicks) * 10;
    assignedTicks = ticks;
  }
  var toEncode = decoded;
  // Reuse the library quantizer and GIF encoder, reserve one RGBA palette
  // entry for fully transparent pixels. Default image quantizers drop alpha.
  if (!allowLossyAlphaForDiagnostic &&
      decoded.frames.any((f) => f.any((p) => p.a == 0))) {
    image.Image? first;
    for (final frame in decoded.frames) {
      final quantizer = image.NeuralQuantizer(frame, numberOfColors: 255);
      final palette = image.PaletteUint8(256, 4);
      for (var i = 0; i < 255; i++) {
        palette.setRgba(
          i,
          quantizer.palette.get(i, 0),
          quantizer.palette.get(i, 1),
          quantizer.palette.get(i, 2),
          255,
        );
      }
      palette.setRgba(255, 0, 0, 0, 0);
      final indexed = image.Image(
        width: frame.width,
        height: frame.height,
        numChannels: 1,
        withPalette: true,
        palette: palette,
        frameDuration: frame.frameDuration,
      );
      for (final pixel in frame) {
        indexed.setPixelIndex(
          pixel.x,
          pixel.y,
          pixel.a == 0 ? 255 : quantizer.getColorIndex(pixel),
        );
      }
      if (first == null) {
        first = indexed;
      } else {
        first.addFrame(indexed);
      }
    }
    toEncode = first!..loopCount = decoded.loopCount;
  }
  final gif = image.encodeGif(toEncode);
  if (info.animLoopCount != 1) return gif;
  // image 4.10.1 always emits NETSCAPE2.0; zero would loop forever.
  // For single play remove only its known 19-byte application extension.
  // Image pixels/frames remain encoded by image. Fail closed if layout drifts.
  final expected = <int>[
    0x21,
    0xff,
    11,
    ...'NETSCAPE2.0'.codeUnits,
    3,
    1,
    0,
    0,
    0,
  ];
  if (gif.length < 32 ||
      String.fromCharCodes(gif.take(6)) != 'GIF89a' ||
      gif[10] != 0 ||
      !List.generate(19, (i) => gif[13 + i] == expected[i]).every((v) => v)) {
    throw const FormatException('encoder loop layout changed');
  }
  return Uint8List.fromList([...gif.take(13), ...gif.skip(32)]);
}
