import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'post_upload_support.dart';

void main() {
  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 70));
    }
  }

  testWidgets(
    'composer adds equal-sized photos, reorders/removes, previews and accepts image-only content',
    (tester) async {
      final f = (await tester.runAsync(MediaComposerFixture.create))!;
      debugPrint('composer-host: fixture ready');
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final png = (await tester.runAsync(
        () => File(
          '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
        ).readAsBytes(),
      ))!;
      final e = f.editor();
      f.picker.next = [pickedBytes(png), pickedBytes(png)];
      for (final entry in <String, String?>{
        'Microsoft YaHei': Platform.environment['HNUHOLE_UI_RENDER_FONT'],
        'MaterialIcons': Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'],
      }.entries) {
        if (entry.value != null) {
          await tester.runAsync(() async {
            final loader = FontLoader(entry.key)
              ..addFont(
                File(entry.value!)
                    .readAsBytes()
                    .then((b) => ByteData.sublistView(b)),
              );
            await loader.load();
          });
        }
      }
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Microsoft YaHei'),
          home: RepaintBoundary(
            key: capture,
            child: PostComposerScreen(
              controller: f.posts,
              editor: e,
              channelName: '搭子',
              onManageIdentities: () async {},
              onAuthenticationRequired: () {},
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('post-add-images')));
      await tester.tap(find.byKey(const ValueKey('post-add-images')));
      for (var i = 0; i < 150 && e.mediaBusy; i++) {
        await frames(tester, 1);
      }
      expect(e.mediaBusy, isFalse);
      debugPrint('composer-host: photos imported');
      expect(e.images.length, 2);
      expect(e.images.every((i) => i.ready), isTrue);
      expect(find.text('2/9'), findsOneWidget);
      final first = e.images.first.mediaId;
      final tile1 = find.bySemanticsLabel('第1张图片');
      final tile2 = find.bySemanticsLabel('第2张图片');
      final size1 = tester.getSize(tile1), size2 = tester.getSize(tile2);
      expect(size1, size2);
      expect(size1.width, size1.height);
      final gesture = await tester.startGesture(tester.getCenter(tile1));
      await tester.pump(const Duration(milliseconds: 650));
      await gesture.moveTo(tester.getCenter(tile2));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await frames(tester);
      expect(e.images.last.mediaId, first);
      debugPrint('composer-host: reordered');
      await tester.tap(find.byTooltip('移除第1张图片'));
      await frames(tester);
      expect(e.images.length, 1);
      expect(e.images.single.mediaId, first);
      debugPrint('composer-host: removed');
      for (
        var i = 0;
        i < 200 && (e.saving || find.byType(Image).evaluate().isEmpty);
        i++
      ) {
        await frames(tester, 1);
      }
      expect(e.saving, isFalse);
      expect(find.byType(Image), findsOneWidget);
      final out = Platform.environment['POST_COMPOSER_RENDER_DIR'];
      if (out != null) {
        await tester.pump();
        debugPrint('composer-host: fonts loaded');
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          debugPrint('composer-host: rendering');
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final dir = Directory(out);
          await dir.create(recursive: true);
          await File('${dir.path}/composer-selected.png')
              .writeAsBytes(data!.buffer.asUint8List());
        });
      }
      debugPrint('composer-host: rendered');
      await tester.ensureVisible(find.text('下一步'));
      await tester.tap(find.text('下一步'));
      await frames(tester);
      expect(find.text('确认发布'), findsOneWidget);
      debugPrint('composer-host: confirmation shown');
      expect(e.body, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await frames(tester, 2);
      debugPrint('composer-host: unmounted');
      var closed = false;
      final closing = f.close().then((_) => closed = true);
      for (var i = 0; i < 200 && !closed; i++) {
        await frames(tester, 1);
      }
      expect(closed, isTrue);
      await closing;
      debugPrint('composer-host: closed');
    },
  );
}
