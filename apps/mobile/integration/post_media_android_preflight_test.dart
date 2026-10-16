import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

// Explicit host-only fixture preflight. Not part of test/ discovery and never
// substitutes for the real Photo Picker, native vault, or system gallery.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['POST_MEDIA_ANDROID_FIXTURES'];
  if (root == null) {
    throw StateError('Owned synthetic fixture directory required');
  }
  final manifest = jsonDecode(
    File('$root/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final items = (manifest['originals'] as List).cast<Map<String, dynamic>>();
  if (items.length != 9 || manifest['syntheticOnly'] != true) {
    throw StateError('Exactly nine synthetic originals required');
  }
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    test('host original preflight ${item['name']}', () async {
      final file = File('$root/${item['name']}');
      final original = await file.readAsBytes();
      final result = await inspectPostPhoto(
        PostPickedFile(length: file.length, openRead: file.openRead),
        'c0000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
      );
      expect(result.bytes, original);
      expect(result.selection.sha256, item['sha256']);
      expect(hashes.sha256.convert(result.bytes).toString(), item['sha256']);
      expect(result.selection.byteLength, item['byteLength']);
      expect(result.selection.width, item['width']);
      expect(result.selection.height, item['height']);
      expect(result.selection.mimeType, item['mimeType']);
      if (item['frames'] as int > 1) {
        final codec = await ui.instantiateImageCodec(original);
        try {
          expect(codec.frameCount, 3);
          expect(
            codec.repetitionCount,
            item['name'] == '06-finite.webp' ? 1 : -1,
          );
          for (var index = 0; index < codec.frameCount; index++) {
            final frame = await codec.getNextFrame();
            expect(frame.duration.inMilliseconds, 2000);
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    });
  }
  test('oversized source rejected before byte stream opens', () async {
    var opened = false;
    await expectLater(
      inspectPostPhoto(
        PostPickedFile(
          length: () async => 10 * 1024 * 1024 + 1,
          openRead: () {
            opened = true;
            return const Stream<List<int>>.empty();
          },
        ),
        'c0000000-0000-4000-8000-000000000010',
      ),
      throwsFormatException,
    );
    expect(opened, isFalse);
  });
}
