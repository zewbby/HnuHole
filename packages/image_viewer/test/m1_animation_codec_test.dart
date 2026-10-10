import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../tool/m1_animation_codec.dart';

Future<({int frames, int repeats, List<int> durations, List<Uint8List> rgba})>
inspect(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final rgba = <Uint8List>[], durations = <int>[];
  try {
    for (var i = 0; i < codec.frameCount; i++) {
      final frame = await codec.getNextFrame();
      durations.add(frame.duration.inMilliseconds);
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      rgba.add(Uint8List.fromList(data!.buffer.asUint8List()));
      frame.image.dispose();
    }
    return (
      frames: codec.frameCount,
      repeats: codec.repetitionCount,
      durations: durations,
      rgba: rgba,
    );
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final analysis = <String, Object?>{
    'scope': 'WINDOWS_FLUTTER_ENGINE_NOT_IOS_PHOTOS',
    'imageVersion': '4.10.1',
    'compatibilityProductEnabled': false,
    'loopCases': <Map<String, Object?>>[],
  };
  tearDownAll(() async {
    await File('../../docs/design/image-viewer-m1-animation-analysis.json')
        .writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(analysis)}\n',
        );
  });
  for (final entry in {
    'animation_binary.webp': 1,
    'animation_binary_infinite.webp': -1,
    'animation_binary_once.webp': 0,
  }.entries) {
    test(
      'compatibility GIF preserves frame count and Flutter loop meaning: ${entry.key}',
      () async {
        final original = await File('example/assets/fixtures/${entry.key}')
            .readAsBytes();
        final before = Uint8List.fromList(original);
        final source = await inspect(original);
        final converted = await inspect(compatibilityGifForProbe(original));
        expect(source.repeats, entry.value);
        expect(converted.repeats, source.repeats);
        expect(converted.frames, source.frames);
        expect(converted.durations, source.durations);
        expect(original, before);
        (analysis['loopCases'] as List).add({
          'fixture': entry.key,
          'sourceFrames': source.frames,
          'gifFrames': converted.frames,
          'sourceFlutterRepetitionCount': source.repeats,
          'gifFlutterRepetitionCount': converted.repeats,
          'durationsMs': converted.durations,
          'result': 'PASS',
        });
      },
    );
  }
  test('blind encodeGif changes finite WebP loop meaning', () async {
    final original = await File('example/assets/fixtures/animation.webp')
        .readAsBytes();
    final source = await inspect(original);
    final naive = await inspect(image.encodeGif(image.decodeWebP(original)!));
    expect(source.repeats, 1);
    expect(naive.repeats, 2);
    analysis['blindConversionLoopGap'] = {
      'sourceRepetitions': source.repeats,
      'naiveRepetitions': naive.repeats,
      'result': 'REPRODUCED',
      'fixedInProbe': true,
    };
  });
  test('non-10ms frame timing keeps full-cycle drift within 5ms', () async {
    final original = await File('example/assets/fixtures/animation_timing.webp')
        .readAsBytes();
    final source = await inspect(original);
    final result = await inspect(
      compatibilityGifForProbe(original, allowLossyAlphaForDiagnostic: true),
    );
    expect(source.durations, [37, 53, 87]);
    expect(result.durations, [40, 50, 90]);
    analysis['timing'] = {
      'sourceMs': source.durations,
      'gifMs': result.durations,
      'maxCycleDriftMs': 5,
      'productApproved': false,
    };
    expect(
      (result.durations.reduce((a, b) => a + b) -
              source.durations.reduce((a, b) => a + b))
          .abs(),
      lessThanOrEqualTo(5),
    );
  });
  test('conversion exposes semi-transparency loss rather than asserting equivalence', () async {
    final original = await File('example/assets/fixtures/animation.webp')
        .readAsBytes();
    final source = await inspect(original);
    final result = await inspect(
      compatibilityGifForProbe(original, allowLossyAlphaForDiagnostic: true),
    );
    final alphaChanged = <int>[];
    for (var f = 0; f < source.frames; f++) {
      var changed = 0;
      for (var p = 3; p < source.rgba[f].length; p += 4) {
        if (source.rgba[f][p] != result.rgba[f][p]) changed++;
      }
      alphaChanged.add(changed);
    }
    var blackDifference = 0.0, whiteDifference = 0.0;
    var channelCount = 0;
    for (var f = 0; f < source.frames; f++) {
      for (var p = 0; p < source.rgba[f].length; p += 4) {
        final sa = source.rgba[f][p + 3] / 255,
            ga = result.rgba[f][p + 3] / 255;
        for (var c = 0; c < 3; c++) {
          blackDifference +=
              (source.rgba[f][p + c] * sa - result.rgba[f][p + c] * ga).abs();
          whiteDifference +=
              (source.rgba[f][p + c] * sa +
                      255 * (1 - sa) -
                      result.rgba[f][p + c] * ga -
                      255 * (1 - ga))
                  .abs();
          channelCount++;
        }
      }
    }
    analysis['quality'] = {
      'fixture': 'animation.webp',
      'alphaChangedPixelsPerFrame': alphaChanged,
      'meanAbsoluteRgbDifferenceOnBlack': blackDifference / channelCount,
      'meanAbsoluteRgbDifferenceOnWhite': whiteDifference / channelCount,
      'gifBytes': compatibilityGifForProbe(
        original,
        allowLossyAlphaForDiagnostic: true,
      ).length,
      'sourceBytes': original.length,
      'result': 'LOSS_REPRODUCED_PRODUCT_DECISION_REQUIRED',
    };
    expect(
      alphaChanged.any((n) => n > 0),
      isTrue,
      reason: 'Fixture intentionally contains alpha=120; GIF conversion is not equivalent.',
    );
  });
  test(
    'invalid and above-budget conversion fails before full decoding',
    () async {
      expect(
        () => compatibilityGifForProbe(Uint8List(3)),
        throwsFormatException,
      );
      expect(
        () => compatibilityGifForProbe(Uint8List(1024 * 1024 + 1)),
        throwsFormatException,
      );
      final original = await File(
        'example/assets/fixtures/animation_over_limit.webp',
      ).readAsBytes();
      expect(() => compatibilityGifForProbe(original), throwsFormatException);
    },
  );

  test(
    'safe compatibility path preserves binary alpha and rejects semi-alpha',
    () async {
      final original = await File(
        'example/assets/fixtures/animation_binary.webp',
      ).readAsBytes();
      final source = await inspect(original),
          result = await inspect(compatibilityGifForProbe(original));
      for (var f = 0; f < source.frames; f++) {
        for (var p = 3; p < source.rgba[f].length; p += 4) {
          expect(result.rgba[f][p], source.rgba[f][p]);
        }
      }
      final semi = await File('example/assets/fixtures/animation.webp')
          .readAsBytes();
      expect(() => compatibilityGifForProbe(semi), throwsFormatException);
      analysis['safeAlphaPolicy'] = {
        'binaryAlpha': 'PASS_ON_THREE_FRAME_FIXTURE',
        'semiAlpha': 'REJECTED_PENDING_PRODUCT_DECISION',
        'defaultProductEnabled': false,
      };
    },
  );
}
