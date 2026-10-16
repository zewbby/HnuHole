import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

import 'm1_animation_codec.dart';

void main(List<String> args) {
  final file = File(args.first);
  final input = file.readAsBytesSync();
  final info = image.WebPDecoder().startDecode(input)!;
  final rssBefore = ProcessInfo.currentRss;
  final clock = Stopwatch()..start();
  final output = compatibilityGifForProbe(input);
  clock.stop();
  final decoded = image.decodeGif(output)!;
  final record = {
    'scope': 'WINDOWS_DART_PROCESS_NOT_PHONE_PERFORMANCE',
    'fixture': file.uri.pathSegments.last,
    'inputBytes': input.length,
    'outputBytes': output.length,
    'sizeRatio': output.length / input.length,
    'width': info.width,
    'height': info.height,
    'frames': info.numFrames,
    'decodedRgbaBytesLowerBound': info.width * info.height * info.numFrames * 4,
    'sourceDurationsMs': info.frames.map((f) => f.duration).toList(),
    'gifDurationsMs': decoded.frames.map((f) => f.frameDuration).toList(),
    'sourceTotalPlaysRaw': info.animLoopCount,
    'gifRepeatCountRaw': decoded.loopCount,
    'elapsedMs': clock.elapsedMilliseconds,
    'rssBeforeBytes': rssBefore,
    'rssAfterBytes': ProcessInfo.currentRss,
    'processPeakRssBytes': ProcessInfo.maxRss,
    'peakIncludesVmAndLibraries': true,
    'sha256Input': sha256.convert(input).toString(),
    'sha256Output': sha256.convert(output).toString(),
    'productEnabled': false,
  };
  if (args.length > 1) {
    File(args[1]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(record)}\n',
    );
  }
  stdout.writeln(jsonEncode(record));
}
