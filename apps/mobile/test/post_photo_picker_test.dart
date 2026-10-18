import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'post_upload_support.dart' show pickedBytes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Flutter preflight retains original PNG/GIF/WebP bytes and JPEG encoded EXIF geometry', () async {
    final golden = jsonDecode(
      File('test/fixtures/post-media-v1.json').readAsStringSync(),
    ) as Map;
    final gif = base64Decode(golden['originalBase64']);
    final jpeg = base64Decode(
      File('test/fixtures/oriented-jpeg.b64').readAsStringSync().trim(),
    );
    final files = <Uint8List>[
      await File(
        '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
      ).readAsBytes(),
      gif,
      jpeg,
      await File(
        '../../packages/image_viewer/example/assets/fixtures/animation.webp',
      ).readAsBytes(),
      await File(
        '../../packages/image_viewer/example/assets/fixtures/animation.gif',
      ).readAsBytes(),
    ];
    final types = [
      'image/png',
      'image/gif',
      'image/jpeg',
      'image/webp',
      'image/gif',
    ];
    for (var i = 0; i < files.length; i++) {
      final original = files[i], id = newPostMediaId();
      final inspected = await inspectPostPhoto(pickedBytes(original), id);
      expect(inspected.bytes, original);
      expect(
        inspected.selection.sha256,
        hashes.sha256.convert(original).toString(),
      );
      expect(inspected.selection.mimeType, types[i]);
      if (i == 2) {
        expect(inspected.selection.width, 2);
        expect(inspected.selection.height, 3);
      }
    }
  });
  test('invalid, changed or oversized originals are rejected with no silent conversion', () async {
    await expectLater(
      inspectPostPhoto(
        pickedBytes(Uint8List.fromList([1, 2, 3])),
        newPostMediaId(),
      ),
      throwsA(anything),
    );
    var read = false;
    final tooLarge = PostPickedFile(
      length: () async => 10 * 1024 * 1024 + 1,
      openRead: () {
        read = true;
        return const Stream.empty();
      },
    );
    await expectLater(
      inspectPostPhoto(tooLarge, newPostMediaId()),
      throwsFormatException,
    );
    expect(read, isFalse);
    final changed = PostPickedFile(
      length: () async => 8,
      openRead: () => Stream.value([1, 2]),
    );
    await expectLater(
      inspectPostPhoto(changed, newPostMediaId()),
      throwsFormatException,
    );
  });
  test('actual oversized pixel, frame and animation budgets are rejected before publication', () async {
    for (final name in [
      'android_dimension_over.png',
      'android_pixels_over.png',
      'android_frames_over.webp',
      'android_animation_work_over.webp',
      'android_duration_over.webp',
    ]) {
      final bytes = await File(
        '../../packages/image_viewer/example/assets/fixtures/$name',
      ).readAsBytes();
      await expectLater(
        inspectPostPhoto(pickedBytes(bytes), newPostMediaId()),
        throwsA(anything),
        reason: name,
      );
    }
  });
}
