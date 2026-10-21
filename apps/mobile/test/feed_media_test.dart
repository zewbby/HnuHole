import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/src/posts/post_images.dart';

import 'feed_ui_test.dart' as fixture;

import 'package:hnuhole_mobile/src/posts/post_controller.dart';

void main() {
  late MemoryImage image;
  setUpAll(() async {
    image = MemoryImage(
      await File(
        '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
      ).readAsBytes(),
    );
  });
  PostImage media(String id, Size size, {Future<ImageProvider>? pending}) =>
      PostImage.deferred(
        pixelSize: size,
        loadThumbnail: () => pending ?? Future.value(image),
        item: ViewerItem.provider(
          id: id,
          provider: image,
          pixelSize: size,
          saveAllowed: false,
        ),
      );
  PostImages group(
    List<PostImage> images,
    ValueNotifier<bool> access, {
    VoidCallback? release,
  }) => PostImages(
    postId: fixture.postId,
    images: images,
    accessGranted: access,
    onRelease: release,
  );
  Widget section(ValueNotifier<bool> authority, PostImages value) =>
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 317,
              child: PostImagesSection(
                postId: fixture.postId,
                expectedCount: value.images.length,
                feedPreview: true,
                loadImages: (_) async => value,
                authority: authority,
                isCurrent: () => authority.value,
              ),
            ),
          ),
        ),
      );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets(
    'single landscape and portrait preserve metadata ratio; extreme preview is bounded',
    (tester) async {
      final authority = ValueNotifier(true), access = ValueNotifier(true);
      for (final size in [
        const Size(1600, 900),
        const Size(900, 1200),
        const Size(900, 900),
        const Size(100, 3000),
      ]) {
        await tester.pumpWidget(
          section(authority, group([media('single', size)], access)),
        );
        await frames(tester);
        final actual = tester.getSize(
          find.byKey(const ValueKey(('feed-image', 'single'))),
        );
        expect(actual.width, 317);
        expect(
          actual.height,
          closeTo(317 / (size.width / size.height).clamp(.75, 2), .1),
        );
        expect(actual.height, lessThan(424));
        if (size.height == 3000) expect(find.text('点击查看完整图片'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
      authority.dispose();
      access.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'FA-O02 expired single and carousel keep geometry without protected images',
    (tester) async {
      for (final sizes in [
        [const Size(1600, 900)],
        [const Size(900, 1200)],
        [const Size(100, 3000)],
        [const Size(900, 1200), const Size(1600, 900), const Size(900, 900)],
      ]) {
        final authority = ValueNotifier(true), access = ValueNotifier(true);
        await tester.pumpWidget(
          section(
            authority,
            group([
              for (var i = 0; i < sizes.length; i++)
                media('image-$i', sizes[i]),
            ], access),
          ),
        );
        await frames(tester);
        final before = tester.getSize(find.byType(PostImagesSection));
        access.value = false;
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(PostImagesSection)), before);
        expect(find.byType(Image, skipOffstage: false), findsNothing);
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);
        expect(find.text('图片已不可访问'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        authority.dispose();
        access.dispose();
      }
    },
  );
  testWidgets(
    'FA-O02 reload pending and failure retain known geometry and late bytes stay hidden',
    (tester) async {
      final authority = ValueNotifier(true),
          oldAccess = ValueNotifier(true),
          newAccess = ValueNotifier(true);
      final pendingBytes = Completer<ImageProvider>();
      final oldGroup = group([
        media('old', const Size(1600, 900), pending: pendingBytes.future),
      ], oldAccess);
      final freshGroup = group([
        media('fresh', const Size(1600, 900)),
      ], newAccess);
      var calls = 0;
      final reload = Completer<PostImages>();
      Future<PostImages> loader(String _) async {
        calls++;
        if (calls == 1) return oldGroup;
        if (calls == 2) return reload.future;
        return freshGroup;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 317,
              child: PostImagesSection(
                postId: fixture.postId,
                expectedCount: 1,
                feedPreview: true,
                loadImages: loader,
                authority: authority,
                isCurrent: () => authority.value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byType(PostImagesSection));
      oldAccess.value = false;
      await tester.pumpAndSettle();
      pendingBytes.complete(image);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('重新读取图片'));
      await tester.pump();
      expect(tester.getSize(find.byType(PostImagesSection)), before);
      expect(find.byType(Image), findsNothing);
      reload.completeError(StateError('synthetic unavailable'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PostImagesSection)), before);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('重新加载图片'));
      await frames(tester);
      expect(tester.getSize(find.byType(PostImagesSection)), before);
      expect(find.byType(Image), findsOneWidget);
      expect(calls, 3);
      authority.value = false;
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PostImagesSection)).height, 0);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      authority.dispose();
      oldAccess.dispose();
      newAccess.dispose();
    },
  );
  for (final expiresDuringGesture in [true, false]) {
    testWidgets(
      'FA-O02 lease changes during pointer gesture never open parent or viewer ($expiresDuringGesture)',
      (tester) async {
        final authority = ValueNotifier(true),
            oldAccess = ValueNotifier(true),
            freshAccess = ValueNotifier(true);
        final oldGroup = group([
          media('old', const Size(1600, 900)),
        ], oldAccess);
        final freshGroup = group([
          media('fresh', const Size(1600, 900)),
        ], freshAccess);
        final reload = Completer<PostImages>();
        var calls = 0, parentTaps = 0;
        Future<PostImages> loader(String _) async =>
            ++calls == 1 ? oldGroup : reload.future;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InkWell(
                onTap: () => parentTaps++,
                child: SizedBox(
                  width: 317,
                  child: PostImagesSection(
                    postId: fixture.postId,
                    expectedCount: 1,
                    feedPreview: true,
                    loadImages: loader,
                    authority: authority,
                    isCurrent: () => authority.value,
                  ),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        final position = tester.getCenter(
          find.byKey(const ValueKey(('feed-image', 'old'))),
        );
        if (!expiresDuringGesture) {
          oldAccess.value = false;
          await tester.pump();
          await tester.tap(find.text('重新读取图片'));
          await tester.pump();
        }
        final gesture = await tester.startGesture(position);
        await tester.pump();
        if (expiresDuringGesture) {
          oldAccess.value = false;
          await tester.pump();
          expect(find.byType(Image, skipOffstage: false), findsNothing);
        } else {
          reload.complete(freshGroup);
          await frames(tester);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(parentTaps, 0);
        expect(find.byType(HnuImageViewer), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        authority.dispose();
        oldAccess.dispose();
        freshAccess.dispose();
      },
    );
  }
  testWidgets(
    'FA-O02 narrow large-text status scrolls to retry without overflow',
    (tester) async {
      for (final scale in [2.0, 3.0]) {
        final authority = ValueNotifier(true), access = ValueNotifier(true);
        final value = group([media('wide', const Size(1600, 800))], access);
        final pending = Completer<PostImages>();
        var calls = 0;
        Future<PostImages> loader(String _) async =>
            ++calls == 1 ? value : pending.future;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 180,
                  child: PostImagesSection(
                    postId: fixture.postId,
                    expectedCount: 1,
                    feedPreview: true,
                    loadImages: loader,
                    authority: authority,
                    isCurrent: () => authority.value,
                  ),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        final before = tester.getSize(find.byType(PostImagesSection));
        access.value = false;
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(PostImagesSection)), before);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('重新读取图片'));
        await tester.tap(find.text('重新读取图片'));
        await tester.pump();
        expect(calls, 2);
        expect(tester.getSize(find.byType(PostImagesSection)), before);
        expect(tester.takeException(), isNull);
        pending.completeError(StateError('synthetic unavailable'));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(PostImagesSection)), before);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('重新加载图片'));
        expect(find.text('重新加载图片').hitTestable(), findsOneWidget);
        expect(find.byType(Image, skipOffstage: false), findsNothing);
        await tester.pumpWidget(const SizedBox());
        authority.dispose();
        access.dispose();
      }
    },
  );
  testWidgets('metadata fixes geometry while image bytes load or fail', (
    tester,
  ) async {
    final authority = ValueNotifier(true), access = ValueNotifier(true);
    final pending = Completer<ImageProvider>();
    await tester.pumpWidget(
      section(
        authority,
        group([
          media('pending', const Size(1600, 900), pending: pending.future),
        ], access),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(
      find.byKey(const ValueKey(('feed-image', 'pending'))),
    );
    pending.completeError(StateError('fixture decode unavailable'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey(('feed-image', 'pending')))),
      before,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    authority.dispose();
    access.dispose();
  });
  testWidgets(
    'horizontal mixed media drags independently, opens correct index and revokes',
    (tester) async {
      final authority = ValueNotifier(true), access = ValueNotifier(true);
      var released = 0;
      await tester.pumpWidget(
        section(
          authority,
          group(
            [
              media('one', const Size(900, 1200)),
              media('two', const Size(1600, 900)),
              media('three', const Size(900, 900)),
            ],
            access,
            release: () => released++,
          ),
        ),
      );
      await frames(tester);
      final rail = find.byKey(const ValueKey('feed-media:${fixture.postId}'));
      final second = find.byKey(const ValueKey(('feed-image', 'two')));
      expect(tester.getTopLeft(second).dx, lessThan(317));
      final before = tester.getTopLeft(second).dx;
      await tester.drag(rail, const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(second).dx, lessThan(before));
      await tester.tap(second);
      await frames(tester);
      final viewer = tester.widget<HnuImageViewer>(find.byType(HnuImageViewer));
      expect(viewer.controller.index, 1);
      access.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(HnuImageViewer), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(released, 1);
      authority.dispose();
      access.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'render production feed and controls with synthetic protected media',
    (tester) async {
      tester.view.physicalSize = const Size(402, 806);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in {
        'Roboto': 'HNUHOLE_UI_RENDER_LATIN_FONT',
        'HhNotoSansSC': 'HNUHOLE_UI_RENDER_FONT',
        'MaterialIcons': 'HNUHOLE_UI_RENDER_ICON_FONT',
      }.entries) {
        final path = Platform.environment[entry.value];
        if (path != null) {
          await tester.runAsync(() async {
            final loader = FontLoader(entry.key)
              ..addFont(
                File(path).readAsBytes().then((b) => ByteData.sublistView(b)),
              );
            if (entry.key == 'Roboto') {
              for (final env in [
                'HNUHOLE_UI_RENDER_LATIN_MEDIUM_FONT',
                'HNUHOLE_UI_RENDER_LATIN_BOLD_FONT',
              ]) {
                final extra = Platform.environment[env];
                if (extra != null) {
                  loader.addFont(
                    File(extra)
                        .readAsBytes()
                        .then((b) => ByteData.sublistView(b)),
                  );
                }
              }
            }
            await loader.load();
          });
        }
      }
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final renderMedia = <String, MemoryImage>{};
        Future<void> createMedia(String id, Size size) async {
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            final rect = Offset.zero & size;
            canvas.drawRect(
              rect,
              Paint()
                ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFDDEEE7), Color(0xFFB4CFD3)],
                ).createShader(rect),
            );
            canvas.drawCircle(
              Offset(size.width * .78, size.height * .23),
              size.shortestSide * .09,
              Paint()..color = const Color(0xFFFFF1CC),
            );
            canvas.drawPath(
              Path()
                ..moveTo(0, size.height * .67)
                ..quadraticBezierTo(
                  size.width * .4,
                  size.height * .28,
                  size.width,
                  size.height * .72,
                )
                ..lineTo(size.width, size.height)
                ..lineTo(0, size.height)
                ..close(),
              Paint()..color = const Color(0xFF6D9F8D),
            );
            canvas.drawRect(
              Rect.fromLTWH(
                size.width * .16,
                size.height * .43,
                size.width * .42,
                size.height * .32,
              ),
              Paint()..color = const Color(0xFFF9F7EC),
            );
            for (var i = 0; i < 4; i++) {
              canvas.drawRect(
                Rect.fromLTWH(
                  size.width * (.2 + i * .085),
                  size.height * .51,
                  size.width * .047,
                  size.height * .1,
                ),
                Paint()..color = const Color(0xFF517684),
              );
            }
            final picture = recorder.endRecording();
            final bitmap = await picture.toImage(
              size.width.toInt(),
              size.height.toInt(),
            );
            final bytes = await bitmap.toByteData(
              format: ui.ImageByteFormat.png,
            );
            renderMedia[id] = MemoryImage(bytes!.buffer.asUint8List());
            bitmap.dispose();
            picture.dispose();
          });
        }

        for (final size in [
          const Size(1600, 900),
          const Size(900, 1200),
          const Size(900, 900),
        ]) {
          await createMedia('${size.width}/${size.height}', size);
        }
        PostImage renderedMedia(String id, Size size) {
          final provider = renderMedia['${size.width}/${size.height}']!;
          return PostImage(
            thumbnail: provider,
            pixelSize: size,
            item: ViewerItem.provider(
              id: id,
              provider: provider,
              pixelSize: size,
              saveAllowed: false,
            ),
          );
        }

        final out = Directory(
          Platform.environment['HNUHOLE_FEED_RENDER_DIR'] ??
              'build/feed-ui-render',
        );
        await tester.runAsync(() => out.create(recursive: true));
        final f = await fixture.FeedFixture.create();
        addTearDown(f.dispose);
        final access = ValueNotifier(true);
        final boundary = GlobalKey();
        Future<void> capture(String name) async {
          await frames(tester);
          await tester.pumpAndSettle();
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final png = await render.toImage(pixelRatio: 2);
            final bytes = await png.toByteData(format: ui.ImageByteFormat.png);
            await File('${out.path}/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            png.dispose();
          });
          expect(tester.takeException(), isNull);
        }

        Future<void> mount({
          bool multi = false,
          Size size = const Size(1600, 900),
          Brightness brightness = Brightness.light,
        }) async {
          f.api.items = [fixture.post(images: multi ? 3 : 1)];
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: fixture.screen(
                f,
                brightness: brightness,
                loader: (_) async => group([
                  renderedMedia('landscape', size),
                  if (multi) renderedMedia('portrait', const Size(900, 1200)),
                  if (multi) renderedMedia('square', const Size(900, 900)),
                ], access),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await f.controller.loadTimeline();
          await tester.pumpAndSettle();
        }

        await mount();
        await capture('feed-light');
        await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
        await tester.pumpAndSettle();
        await capture('channels');
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('feed-block-filter')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('block-channel:${fixture.otherChannelId}')),
        );
        await tester.pumpAndSettle();
        await capture('blocked');
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await mount(size: const Size(900, 1200));
        await capture('portrait');
        await tester.pumpWidget(const SizedBox());
        await mount(multi: true);
        await capture('carousel');
        await tester.pumpWidget(const SizedBox());
        await mount(brightness: Brightness.dark);
        await capture('feed-dark');
        await tester.pumpWidget(const SizedBox());
        access.dispose();
      } finally {
        debugDisableShadows = previousShadows;
      }
    },
  );
}
