import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/identity/identity_avatar_photo.dart';

import 'post_upload_support.dart' show pickedBytes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = '10000000-0000-4000-8000-000000000001';
  test(
    'static JPEG with gallery trailer becomes a bounded standard PNG',
    () async {
      final jpeg = base64Decode(
        File('test/fixtures/oriented-jpeg.b64').readAsStringSync().trim(),
      );
      final original = Uint8List.fromList([...jpeg, ...List.filled(24, 78)]);
      final result = await prepareIdentityAvatar(pickedBytes(original), id);
      expect(result.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(result.sublist(result.length - 12), [
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
      ]);
      final codec = await ui.instantiateImageCodec(result);
      final frame = await codec.getNextFrame();
      expect(codec.frameCount, 1);
      expect(frame.image.width * frame.image.height, 6);
      frame.image.dispose();
      codec.dispose();
      expect(original.sublist(original.length - 24), List.filled(24, 78));
    },
  );
  test('animated and corrupt selections remain rejected', () async {
    final animated = await File(
      '../../packages/image_viewer/example/assets/fixtures/animation.webp',
    ).readAsBytes();
    await expectLater(
      prepareIdentityAvatar(pickedBytes(animated), id),
      throwsFormatException,
    );
    await expectLater(
      prepareIdentityAvatar(pickedBytes(Uint8List.fromList([1, 2, 3])), id),
      throwsA(anything),
    );
  });
  test(
    'user reproduction can export upload bytes for strict server validation',
    () async {
      final path = Platform.environment['AVATAR_REPRO_INPUT']!;
      final result = await prepareIdentityAvatar(
        pickedBytes(await File(path).readAsBytes()),
        id,
      );
      await File(Platform.environment['AVATAR_REPRO_OUTPUT']!)
          .writeAsBytes(result);
    },
    skip: Platform.environment['AVATAR_REPRO_INPUT'] == null,
  );
}
