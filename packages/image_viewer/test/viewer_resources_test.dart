import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

// Capture the decoder passed through the real viewer resource provider. The
// test controls the exact dispose-before-frame-completion ordering.
class _CaptureDecoder extends ImageProvider<_CaptureDecoder> {
  ImageDecoderCallback? decode;
  @override
  Future<_CaptureDecoder> obtainKey(ImageConfiguration configuration) async =>
      this;
  @override
  ImageStreamCompleter loadImage(
    _CaptureDecoder key,
    ImageDecoderCallback decoder,
  ) {
    decode = decoder;
    return _PendingImageStream();
  }
}

class _PendingImageStream extends ImageStreamCompleter {}

class _NoWriteGallery implements ViewerGalleryWriter {
  int writes = 0;
  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<void> putImage(String path) async {
    writes++;
  }
}

void main() {
  testWidgets(
    'disposing before native frame completion frees it without usage or errors',
    (tester) async {
      final bytes = await tester.runAsync(
        () => File('example/assets/fixtures/ordinary.png').readAsBytes(),
      );
      final provider = _CaptureDecoder();
      final controller = ViewerController(
        items: [
          ViewerItem.provider(
            id: 'closing',
            provider: provider,
            pixelSize: const Size(640, 480),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: HnuImageViewer(controller: controller)),
      );
      await tester.pump();
      expect(provider.decode, isNotNull);
      final frame = await tester.runAsync(() async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes!);
        final codec = await provider.decode!(buffer);
        final pending = codec.getNextFrame();
        codec.dispose();
        return pending;
      });
      expect(frame!.image.debugDisposed, isTrue);
      expect(controller.resourceUsage, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  Future<ViewerController> show(
    WidgetTester tester,
    String name,
    Size size, {
    ViewerResourceLimits limits = const ViewerResourceLimits(),
  }) async {
    final bytes = await tester.runAsync(
      () => File('example/assets/fixtures/$name').readAsBytes(),
    );
    final c = ViewerController(
      resourceLimits: limits,
      items: [
        ViewerItem.provider(
          id: name,
          provider: MemoryImage(bytes!),
          pixelSize: size,
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HnuImageViewer(controller: c)),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    return c;
  }

  test('resource policy rejects nonpositive values in release code', () {
    expect(
      () => ViewerController(
        items: [
          ViewerItem(
            id: 'a',
            loadSource: () async => ViewerSource(
              provider: const AssetImage('unused'),
              pixelSize: const Size(1, 1),
            ),
          ),
        ],
        resourceLimits: const ViewerResourceLimits(maxFrames: 0),
      ),
      throwsArgumentError,
    );
  });

  for (final entry in [
    ('android_pixels_over.png', const Size(3073, 4096)),
    ('android_dimension_over.png', const Size(1, 16385)),
    ('android_frames_over.webp', const Size(128, 96)),
    ('android_duration_over.webp', const Size(128, 96)),
    ('android_animation_work_over.webp', const Size(1024, 1024)),
  ]) {
    testWidgets('${entry.$1} fails explicitly and can still close', (
      tester,
    ) async {
      final c = await show(tester, entry.$1, entry.$2);
      expect(c.status, ViewerLoadStatus.failed);
      expect(c.failure, ViewerFailure.resourceLimit);
      expect(find.text('图片超出支持上限，请选择其他图片'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('viewer-close')));
      await tester.pump();
      expect(c.active, isFalse);
    });
  }
  testWidgets(
    'encoded bytes are rejected before a Flutter frame is allocated',
    (tester) async {
      final c = await show(
        tester,
        'ordinary.png',
        const Size(640, 480),
        limits: const ViewerResourceLimits(maxEncodedBytes: 20),
      );
      expect(c.failure, ViewerFailure.resourceLimit);
      expect(c.resourceUsage, isNull);
    },
  );
  testWidgets(
    'supported 120-frame animation keeps codec frames and infinite loop',
    (tester) async {
      final c = await show(
        tester,
        'android_frames_limit.webp',
        const Size(128, 96),
      );
      expect(c.status, ViewerLoadStatus.ready);
      expect(c.resourceUsage!.frameCount, 120);
      expect(c.resourceUsage!.decodedFrames, greaterThan(1));
    },
  );
  testWidgets(
    'cycle budget rejects instead of silently skipping a late frame',
    (tester) async {
      final c = await show(
        tester,
        'animation.webp',
        const Size(96, 72),
        limits: const ViewerResourceLimits(
          maxCycleDuration: Duration(milliseconds: 250),
        ),
      );
      expect(c.failure, ViewerFailure.resourceLimit);
    },
  );
  for (var orientation = 1; orientation <= 8; orientation++) {
    testWidgets('JPEG EXIF $orientation matches actual decoder output', (
      tester,
    ) async {
      final c = await show(
        tester,
        'android_exif_$orientation.jpg',
        orientation >= 5 ? const Size(128, 192) : const Size(192, 128),
      );
      expect(c.status, ViewerLoadStatus.ready);
      expect(c.failure, isNull);
    });
  }
  test('oversized original bytes/file are refused without staging or native writes', () async {
    final root = await Directory.systemTemp.createTemp('viewer-budget-test-');
    final file = File('${root.path}/original.png');
    await file.writeAsBytes(List.filled(32, 1));
    final gallery = _NoWriteGallery();
    var staging = 0;
    final saver = ViewerSaveCoordinator(
      gallery: gallery,
      maxOriginalBytes: 16,
      createTemporaryDirectory: () async {
        staging++;
        return root.createTemp('owned-');
      },
    );
    try {
      for (final original in [
        ViewerOriginal.file(file.path, ViewerOriginalFormat.png),
        ViewerOriginal.bytes(
          await file.readAsBytes(),
          ViewerOriginalFormat.png,
        ),
      ]) {
        final result = await saver.save(
          itemId: 'original',
          resolveOriginal: () async => original,
        );
        expect(result.status, ViewerSaveStatus.resourceLimit);
        expect(result.systemWriteStarted, isFalse);
        expect(saver.busy, isFalse);
      }
      expect(gallery.writes, 0);
      expect(staging, 0);
      expect(await file.length(), 32);
    } finally {
      saver.dispose();
      await root.delete(recursive: true);
    }
  });
}
