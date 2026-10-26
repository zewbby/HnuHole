import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

void main() {
  late Uint8List ordinary, long;
  setUpAll(() async {
    ordinary = await File('example/assets/fixtures/ordinary.png').readAsBytes();
    long = await File('example/assets/fixtures/long.png').readAsBytes();
  });
  ViewerSource source({bool tall = false}) => ViewerSource(
    provider: MemoryImage(tall ? long : ordinary),
    pixelSize: tall ? const Size(480, 2400) : const Size(640, 480),
  );
  ViewerItem item(String id, {bool tall = false}) => ViewerItem(
    id: id,
    loadSource: () async => source(tall: tall),
  );
  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> open(WidgetTester tester, ViewerController c) async {
    tester.view.physicalSize = const Size(400, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xffff00ff),
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      HnuImageViewerRoute(
                        builder: (context) => HnuImageViewer(
                          controller: c,
                          enableAndroidSaving: false,
                          onClosed: (_) => Navigator.of(context).pop(),
                        ),
                      ),
                    );
                  },
                  child: const Text('原页面'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('原页面'));
    await frames(tester, 16);
    expect(c.status, ViewerLoadStatus.ready);
  }

  Rect viewport(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('viewer-pages')));
  double alpha(WidgetTester tester) => tester
      .widget<ColoredBox>(find.byKey(const ValueKey('viewer-backdrop')))
      .color
      .a;
  Future<void> capture(WidgetTester tester, String name) async {
    final folder = Platform.environment['VIEWER_CAPTURE_DIR'];
    if (folder == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    await tester.runAsync(() async {
      await Directory(folder).create(recursive: true);
      await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    image.dispose();
  }

  for (final direction in [-1.0, 1.0]) {
    testWidgets(
      'vertical $direction reveals caller while held and exits after animation',
      (tester) async {
        final c = ViewerController(items: [item('a')]);
        await open(tester, c);
        await capture(tester, 'open');
        final g = await tester.startGesture(viewport(tester).center);
        await g.moveBy(Offset(0, direction * 80));
        await tester.pump(const Duration(milliseconds: 50));
        expect(alpha(tester), inExclusiveRange(0, 1));
        expect(c.active, isTrue);
        final transform = tester.widget<Transform>(
          find.byKey(const ValueKey('viewer-dismiss-transform')),
        );
        expect(transform.transform.getTranslation().y, direction * 80);
        await capture(tester, direction > 0 ? 'pull-down' : 'pull-up');
        await g.moveBy(Offset(0, direction * 90));
        await tester.pump(const Duration(milliseconds: 50));
        await g.up();
        await tester.pump(const Duration(milliseconds: 16));
        expect(c.active, isTrue);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.active, isTrue);
        expect(find.text('查看已结束'), findsNothing);
        await capture(tester, direction > 0 ? 'release-down' : 'release-up');
        await frames(tester);
        expect(c.closeReason, ViewerCloseReason.gesture);
        expect(find.byType(HnuImageViewer), findsNothing);
        expect(find.text('原页面'), findsOneWidget);
        expect(find.text('查看已结束'), findsNothing);
      },
    );
  }
  testWidgets('short slow pull smoothly returns to the same image', (
    tester,
  ) async {
    final c = ViewerController(items: [item('a')]);
    await open(tester, c);
    final g = await tester.startGesture(viewport(tester).center);
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 70));
    }
    final pulled = alpha(tester);
    expect(pulled, lessThan(1));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(alpha(tester), greaterThan(pulled));
    expect(alpha(tester), lessThan(1));
    await frames(tester);
    expect(alpha(tester), 1);
    expect(c.active, isTrue);
    expect(c.status, ViewerLoadStatus.ready);
  });
  testWidgets('cancel and a second finger never commit a dismissal', (
    tester,
  ) async {
    final c = ViewerController(items: [item('a')]);
    await open(tester, c);
    final g = await tester.startGesture(viewport(tester).center, pointer: 40);
    await g.moveBy(const Offset(0, 180));
    await tester.pump();
    final second = await tester.startGesture(
      viewport(tester).center + const Offset(50, 0),
      pointer: 41,
    );
    await tester.pump();
    await second.up();
    await g.up();
    await frames(tester);
    expect(c.active, isTrue);
    expect(alpha(tester), 1);
    final cancelled = await tester.startGesture(
      viewport(tester).center,
      pointer: 42,
    );
    await cancelled.moveBy(const Offset(0, -180));
    await tester.pump();
    await cancelled.cancel();
    await frames(tester);
    expect(c.active, isTrue);
    expect(alpha(tester), 1);
  });
  testWidgets('backgrounding cancels an unfinished exit without a late pop', (
    tester,
  ) async {
    final c = ViewerController(items: [item('a')]);
    await open(tester, c);
    final g = await tester.startGesture(viewport(tester).center);
    await g.moveBy(const Offset(0, 180));
    await g.up();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await frames(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(tester);
    expect(c.active, isTrue);
    expect(alpha(tester), 1);
    expect(c.status, ViewerLoadStatus.ready);
  });
  testWidgets('revocation during the exit removes private pixels immediately', (
    tester,
  ) async {
    final c = ViewerController(items: [item('a')]);
    await open(tester, c);
    final g = await tester.startGesture(viewport(tester).center);
    await g.moveBy(const Offset(0, 180));
    await g.up();
    await tester.pump();
    c.invalidateAccess();
    await tester.pump();
    expect(find.byType(ExtendedImage), findsNothing);
    expect(c.closeReason, ViewerCloseReason.accessInvalidated);
    await frames(tester);
    expect(find.text('原页面'), findsOneWidget);
  });
  testWidgets('long image upward movement reads the image without dismissing', (
    tester,
  ) async {
    final c = ViewerController(items: [item('long', tall: true)]);
    await open(tester, c);
    final g = await tester.startGesture(viewport(tester).center);
    await g.moveBy(const Offset(0, -180));
    await tester.pump();
    expect(alpha(tester), 1);
    await g.up();
    await frames(tester);
    expect(c.active, isTrue);
  });
  testWidgets(
    'a neighbor loads when exposed, and visited pages do not reload or flash',
    (tester) async {
      final calls = <String, int>{};
      final c = ViewerController(
        items: [
          for (final id in ['a', 'b', 'c'])
            ViewerItem(
              id: id,
              loadSource: () async {
                calls[id] = (calls[id] ?? 0) + 1;
                return source(tall: id == 'b');
              },
            ),
        ],
      );
      await open(tester, c);
      expect(calls, {'a': 1});
      final g = await tester.startGesture(viewport(tester).center);
      await g.moveBy(const Offset(-80, 0));
      await frames(tester, 4);
      expect(c.index, 0);
      expect(calls, {'a': 1, 'b': 1});
      await capture(tester, 'paging-neighbor');
      await g.moveBy(const Offset(-240, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await frames(tester);
      expect(c.index, 1);
      c.select(0);
      await tester.pump();
      expect(find.text('正在加载图片'), findsNothing);
      await frames(tester);
      expect(calls, {'a': 1, 'b': 1});
      expect(c.status, ViewerLoadStatus.ready);
    },
  );
  testWidgets('session cache is bounded and discarded on replacement', (
    tester,
  ) async {
    final calls = <int, int>{};
    final c = ViewerController(
      items: [
        for (var i = 0; i < 4; i++)
          ViewerItem(
            id: '$i',
            loadSource: () async {
              calls[i] = (calls[i] ?? 0) + 1;
              return source();
            },
          ),
      ],
    );
    await open(tester, c);
    for (var i = 1; i < 4; i++) {
      c.select(i);
      await frames(tester);
    }
    c.select(0);
    await frames(tester);
    expect(calls[0], 2);
    c.replaceItems([
      ViewerItem(
        id: '0',
        loadSource: () async {
          calls[0] = calls[0]! + 1;
          return source();
        },
      ),
    ]);
    await frames(tester);
    expect(calls[0], 3);
    expect(c.status, ViewerLoadStatus.ready);
  });
  testWidgets('aggregate pixel budget evicts before the page-count limit', (
    tester,
  ) async {
    var reads = 0;
    final c = ViewerController(
      resourceLimits: const ViewerResourceLimits(maxPixels: 640 * 480),
      items: [
        for (var i = 0; i < 3; i++)
          ViewerItem(
            id: '$i',
            loadSource: () async {
              reads++;
              return source();
            },
          ),
      ],
    );
    await open(tester, c);
    c.select(1);
    await frames(tester);
    c.select(2);
    await frames(tester);
    expect(reads, 3);
    c.select(0);
    await frames(tester);
    expect(reads, 4);
    expect(c.status, ViewerLoadStatus.ready);
  });
  testWidgets('late exposed neighbor cannot survive group replacement', (
    tester,
  ) async {
    final pending = Completer<ViewerSource>();
    final c = ViewerController(
      items: [
        item('a'),
        ViewerItem(id: 'b', loadSource: () => pending.future),
      ],
    );
    await open(tester, c);
    final g = await tester.startGesture(viewport(tester).center);
    await g.moveBy(const Offset(-80, 0));
    await tester.pump();
    c.replaceItems([item('replacement')]);
    pending.complete(source(tall: true));
    await g.cancel();
    await frames(tester);
    expect(c.currentItem.id, 'replacement');
    expect(c.status, ViewerLoadStatus.ready);
    expect(c.resourceUsage!.height, 480);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zoomed images pan without starting either vertical dismissal', (
    tester,
  ) async {
    final c = ViewerController(items: [item('a')]);
    await open(tester, c);
    final state = tester.state<ExtendedImageGestureState>(
      find.byType(ExtendedImageGesture),
    );
    state.handleDoubleTap(
      scale: state.imageGestureConfig!.initialScale * 2,
      doubleTapPosition: viewport(tester).center,
    );
    await frames(tester);
    for (final direction in [-1, 1]) {
      final g = await tester.startGesture(viewport(tester).center);
      await g.moveBy(Offset(0, direction * 160));
      await tester.pump();
      expect(alpha(tester), 1);
      await g.up();
      await frames(tester);
      expect(c.active, isTrue);
    }
  });
  testWidgets('dark viewing surface requests readable status bar icons', (
    tester,
  ) async {
    final c = ViewerController(items: [item('a')]);
    await open(tester, c);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(HnuImageViewer),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
  });
}
