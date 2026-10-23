import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_images.dart';

class _Authority extends ChangeNotifier {
  bool current = true;
  void revoke() {
    current = false;
    notifyListeners();
  }
}

void main() {
  late MemoryImage ordinary, long;
  setUpAll(() async {
    ordinary = MemoryImage(
      await File(
        '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
      ).readAsBytes(),
    );
    long = MemoryImage(
      await File('../../packages/image_viewer/example/assets/fixtures/long.png')
          .readAsBytes(),
    );
  });
  Future<void> frames(WidgetTester tester, [int count = 16]) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  PostImages group(
    ValueNotifier<bool> access, {
    String postId = 'post-a',
    List<PostImage>? images,
  }) => PostImages(
    postId: postId,
    accessGranted: access,
    images:
        images ??
        [
          PostImage(
            thumbnail: ordinary,
            item: ViewerItem.provider(
              id: 'ordinary-v1',
              provider: ordinary,
              pixelSize: const Size(640, 480),
              saveAllowed: false,
            ),
          ),
          PostImage(
            thumbnail: ordinary,
            item: ViewerItem.provider(
              id: 'long-v1',
              provider: long,
              pixelSize: const Size(480, 2400),
              resolveOriginal: () async =>
                  ViewerOriginal.bytes(long.bytes, ViewerOriginalFormat.png),
            ),
          ),
        ],
  );
  Widget section(
    _Authority authority,
    PostImagesLoader loader, {
    String postId = 'post-a',
  }) => PostImagesSection(
    postId: postId,
    loadImages: loader,
    authority: authority,
    isCurrent: () => authority.current,
  );
  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await frames(tester);
  }

  for (final status in [403, 404]) {
    testWidgets(
      'natural expiry closes its viewer and a fresh denial $status never loops',
      (tester) async {
        final authority = _Authority(), access = ValueNotifier(true);
        var expired = false, reads = 0;
        final media = group(access);
        Future<PostImages> load(String _) async {
          if (++reads > 1) {
            throw PostFailure(
              kind: PostFailureKind.rejected,
              statusCode: status,
            );
          }
          return PostImages(
            postId: media.postId,
            images: media.images,
            accessGranted: access,
            isExpired: () => expired,
          );
        }

        await mount(tester, section(authority, load));
        await tester.tap(
          find.byKey(const ValueKey(('post-image', 'ordinary-v1'))),
        );
        await frames(tester);
        expect(find.byType(HnuImageViewer), findsOneWidget);
        expired = true;
        access.value = false;
        await frames(tester);
        expect(reads, 2);
        expect(find.byType(HnuImageViewer), findsNothing);
        expect(find.text('图片暂时无法读取'), findsOneWidget);
        await tester.pump(const Duration(minutes: 2));
        await frames(tester);
        expect(reads, 2);
        expect(access.value, isFalse);
        await tester.pumpWidget(const SizedBox());
        authority.dispose();
        access.dispose();
      },
    );
  }

  testWidgets('detail count mismatch releases the rejected host lease', (
    tester,
  ) async {
    final authority = _Authority();
    final access = ValueNotifier(true);
    var released = 0;
    final original = group(access);
    await mount(
      tester,
      PostImagesSection(
        postId: 'post-a',
        expectedCount: 1,
        loadImages: (_) async => PostImages(
          postId: 'post-a',
          images: original.images,
          accessGranted: access,
          onRelease: () => released++,
        ),
        authority: authority,
        isCurrent: () => authority.current,
      ),
    );
    expect(find.text('图片暂时无法读取'), findsOneWidget);
    expect(released, 1);
    await tester.pumpWidget(const SizedBox());
    authority.dispose();
    access.dispose();
  });

  testWidgets(
    'expired group closes the viewer and explicit reload uses a fresh lease',
    (tester) async {
      final authority = _Authority();
      final first = ValueNotifier(true), second = ValueNotifier(true);
      var calls = 0, released = 0;
      Future<PostImages> load(String _) async {
        final value = group(++calls == 1 ? first : second);
        return PostImages(
          postId: value.postId,
          images: value.images,
          accessGranted: value.accessGranted,
          onRelease: () => released++,
        );
      }

      await mount(tester, section(authority, load));
      await tester.tap(
        find.byKey(const ValueKey(('post-image', 'ordinary-v1'))),
      );
      await frames(tester);
      first.value = false;
      await frames(tester);
      expect(find.byType(HnuImageViewer), findsNothing);
      expect(find.text('图片已不可访问'), findsOneWidget);
      await tester.tap(find.text('重新读取图片'));
      await frames(tester);
      expect(calls, 2);
      expect(first.value, isFalse);
      expect(find.byKey(const ValueKey('post-image-grid')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(released, 2);
      authority.dispose();
      first.dispose();
      second.dispose();
    },
  );

  testWidgets(
    'equal square thumbnails open the full group at the clicked index',
    (tester) async {
      final authority = _Authority(), access = ValueNotifier(true);
      final media = group(access);
      await mount(tester, section(authority, (_) async => media));
      final tiles = find.byType(InkWell);
      expect(tester.getSize(tiles.at(0)), tester.getSize(tiles.at(1)));
      expect(
        tester.getSize(tiles.at(0)).width,
        tester.getSize(tiles.at(0)).height,
      );
      expect(tester.widget<Image>(find.byType(Image).first).fit, BoxFit.cover);
      await tester.tap(find.byKey(const ValueKey(('post-image', 'long-v1'))));
      await frames(tester);
      final viewer = tester.widget<HnuImageViewer>(find.byType(HnuImageViewer));
      expect(viewer.controller.index, 1);
      expect(viewer.controller.currentItem.id, 'long-v1');
      expect(viewer.controller.status, ViewerLoadStatus.ready);
      expect(viewer.controller.resourceUsage!.height, 2400);
      await tester.tap(find.byKey(const ValueKey('viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PostImagesSection), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      authority.dispose();
      access.dispose();
    },
  );

  testWidgets(
    'viewing never fetches originals and item permission disables save',
    (tester) async {
      final authority = _Authority(), access = ValueNotifier(true);
      var resolves = 0;
      final media = group(
        access,
        images: [
          PostImage(
            thumbnail: ordinary,
            item: ViewerItem.provider(
              id: 'no-save',
              provider: ordinary,
              pixelSize: const Size(640, 480),
              saveAllowed: false,
              resolveOriginal: () async {
                resolves++;
                return ViewerOriginal.bytes(
                  ordinary.bytes,
                  ViewerOriginalFormat.png,
                );
              },
            ),
          ),
        ],
      );
      await mount(tester, section(authority, (_) async => media));
      await tester.tap(find.byKey(const ValueKey(('post-image', 'no-save'))));
      await frames(tester);
      expect(resolves, 0);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('viewer-save')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      authority.dispose();
      access.dispose();
    },
  );

  testWidgets(
    'group revocation closes its viewer without popping a newer dialog',
    (tester) async {
      final authority = _Authority(), access = ValueNotifier(true);
      await mount(tester, section(authority, (_) async => group(access)));
      await tester.tap(
        find.byKey(const ValueKey(('post-image', 'ordinary-v1'))),
      );
      await frames(tester);
      final context = tester.element(find.byType(HnuImageViewer));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('保留的其他弹窗')),
        ),
      );
      await tester.pumpAndSettle();
      access.value = false;
      await frames(tester);
      expect(find.text('保留的其他弹窗'), findsOneWidget);
      expect(find.byType(HnuImageViewer, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox());
      authority.dispose();
      access.dispose();
    },
  );

  testWidgets('lost post authority ignores late group completion', (
    tester,
  ) async {
    final authority = _Authority(), access = ValueNotifier(true);
    final pending = Completer<PostImages>();
    await mount(tester, section(authority, (_) => pending.future));
    authority.revoke();
    pending.complete(group(access));
    await frames(tester);
    expect(find.byKey(const ValueKey('post-image-grid')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    authority.dispose();
    access.dispose();
  });

  testWidgets('authority revocation closes an already open viewer', (
    tester,
  ) async {
    final authority = _Authority(), access = ValueNotifier(true);
    await mount(tester, section(authority, (_) async => group(access)));
    await tester.tap(find.byKey(const ValueKey(('post-image', 'ordinary-v1'))));
    await frames(tester);
    authority.revoke();
    await frames(tester);
    expect(find.byType(HnuImageViewer, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('post-image-grid')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    authority.dispose();
    access.dispose();
  });

  test('group enforces post identity, unique images and maximum nine', () {
    final access = ValueNotifier(true);
    final media = group(access);
    expect(() => group(access, postId: ' '), throwsArgumentError);
    expect(
      () => group(access, images: [media.images.first, media.images.first]),
      throwsArgumentError,
    );
    expect(
      () => group(access, images: List.filled(10, media.images.first)),
      throwsArgumentError,
    );
    access.dispose();
  });

  if (Platform.environment['POST_IMAGES_RENDER_DIR'] case final directory?) {
    testWidgets('render actual post image integration layout', (tester) async {
      final authority = _Authority(), access = ValueNotifier(true);
      final key = GlobalKey();
      await tester.runAsync(() async {
        final font = FontLoader('PostImageSnapshot')
          ..addFont(
            File('C:/Windows/Fonts/msyh.ttc')
                .readAsBytes()
                .then(ByteData.sublistView),
          );
        await font.load();
      });
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'PostImageSnapshot'),
            home: Scaffold(
              appBar: AppBar(title: const Text('帖子')),
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '图片查看接入',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('普通图与长图使用相同大小预览，点开后查看完整原图。'),
                    section(authority, (_) async => group(access)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/post-images.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      authority.dispose();
      access.dispose();
    });
  }

  testWidgets('wrong-post group is sanitized and explicit retry can recover', (
    tester,
  ) async {
    final authority = _Authority(), access = ValueNotifier(true);
    var calls = 0;
    await mount(
      tester,
      section(
        authority,
        (_) async =>
            group(access, postId: ++calls == 1 ? 'other-post' : 'post-a'),
      ),
    );
    expect(find.text('图片暂时无法读取'), findsOneWidget);
    expect(find.textContaining('other-post'), findsNothing);
    await tester.tap(find.text('重新加载图片'));
    await frames(tester);
    expect(find.byKey(const ValueKey('post-image-grid')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    authority.dispose();
    access.dispose();
  });

  testWidgets('replacement post rejects completion from an older loader', (
    tester,
  ) async {
    final authority = _Authority(), access = ValueNotifier(true);
    final pending = Completer<PostImages>();
    await mount(tester, section(authority, (_) => pending.future));
    await mount(
      tester,
      section(
        authority,
        (_) async => group(access, postId: 'post-b'),
        postId: 'post-b',
      ),
    );
    pending.complete(group(access));
    await frames(tester);
    expect(find.byKey(const ValueKey('post-image-grid')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(('post-image', 'ordinary-v1'))));
    await frames(tester);
    expect(
      tester
          .widget<HnuImageViewer>(find.byType(HnuImageViewer))
          .controller
          .status,
      ViewerLoadStatus.ready,
    );
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    authority.dispose();
    access.dispose();
  });

  testWidgets('empty authorized group renders no gallery or fake placeholder', (
    tester,
  ) async {
    final authority = _Authority(), access = ValueNotifier(true);
    await mount(
      tester,
      section(authority, (_) async => group(access, images: [])),
    );
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    authority.dispose();
    access.dispose();
  });
}
