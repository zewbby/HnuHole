import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

class _PendingProvider extends ImageProvider<_PendingProvider> {
  final completer = _ControlledCompleter();
  @override
  Future<_PendingProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _PendingProvider key,
    ImageDecoderCallback decode,
  ) => completer;
}

class _ControlledCompleter extends ImageStreamCompleter {
  void publish(ImageInfo image) => setImage(image);
}

class _UiGallery implements ViewerGalleryWriter {
  Completer<void>? pendingWrite;
  int writes = 0;
  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<void> putImage(String originalPath) async {
    writes++;
    await pendingWrite?.future;
  }
}

void main() {
  final bytes = <String, Uint8List>{};
  setUpAll(() async {
    for (final name in [
      'ordinary.png',
      'long.png',
      'animation_infinite.gif',
      'animation_infinite.webp',
    ]) {
      bytes[name] = await File('example/assets/fixtures/$name').readAsBytes();
    }
  });

  ViewerSource source([String name = 'ordinary.png']) => ViewerSource(
    provider: MemoryImage(Uint8List.fromList(bytes[name]!)),
    pixelSize: name == 'long.png'
        ? const Size(480, 2400)
        : name == 'ordinary.png'
        ? const Size(640, 480)
        : const Size(96, 72),
  );

  ViewerItem item(String id, [String name = 'ordinary.png']) => ViewerItem(
    id: id,
    loadSource: () async => source(name),
    semanticLabel: '合成测试图片$id',
  );

  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '$platform default saving is Android only and never requests access on view',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final calls = <String>[];
        const channel = MethodChannel('gal');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final controller = ViewerController(
          items: [
            ViewerItem(
              id: 'original',
              loadSource: () async => source(),
              resolveOriginal: () async => ViewerOriginal.bytes(
                bytes['ordinary.png']!,
                ViewerOriginalFormat.png,
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: HnuImageViewer(controller: controller)),
          ),
        );
        await frames(tester);
        expect(controller.status, ViewerLoadStatus.ready);
        final button = tester.widget<IconButton>(
          find.byKey(const ValueKey('viewer-save')),
        );
        expect(button.onPressed != null, platform == TargetPlatform.android);
        expect(calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'Android saving can be disabled without disposing caller adapter',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final controller = ViewerController(
        items: [
          ViewerItem(
            id: 'original',
            loadSource: () async => source(),
            resolveOriginal: () async => ViewerOriginal.bytes(
              bytes['ordinary.png']!,
              ViewerOriginalFormat.png,
            ),
          ),
        ],
      );
      Future<void> show({
        bool enabled = true,
        ViewerSaveCoordinator? saver,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HnuImageViewer(
                controller: controller,
                enableAndroidSaving: enabled,
                saveCoordinator: saver,
              ),
            ),
          ),
        );
        await frames(tester);
      }

      await show();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('viewer-save')))
            .onPressed,
        isNotNull,
      );
      await show(enabled: false);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('viewer-save')))
            .onPressed,
        isNull,
      );
      final saver = ViewerSaveCoordinator(gallery: _UiGallery());
      await show(enabled: false, saver: saver);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('viewer-save')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      expect(saver.active, isTrue);
      saver.dispose();
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  Future<void> mount(
    WidgetTester tester,
    ViewerController controller, {
    ValueChanged<ViewerCloseReason>? onClosed,
    ValueChanged<ViewerSnapshot>? onChanged,
    Size size = const Size(400, 600),
    double textScale = 1,
    ViewerSaveCoordinator? saveCoordinator,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: const ValueKey('viewer-screenshot'),
            child: Scaffold(
              body: HnuImageViewer(
                controller: controller,
                saveCoordinator: saveCoordinator,
                enableAndroidSaving: false,
                onClosed: onClosed,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
  }

  ExtendedImageGestureState gesture(WidgetTester tester) =>
      tester.state(find.byType(ExtendedImageGesture));

  Future<void> drag(WidgetTester tester, Offset delta, {int steps = 8}) async {
    final rect = tester.getRect(find.byKey(const ValueKey('viewer-pages')));
    final pointer = await tester.startGesture(rect.center);
    await tester.pump();
    for (var i = 0; i < steps; i++) {
      await pointer.moveBy(delta / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pointer.up();
    await frames(tester, 5);
  }

  test('stable IDs reject empty and outer whitespace in release code', () {
    for (final id in ['', ' ', ' id', 'id ']) {
      expect(
        () => ViewerItem(id: id, loadSource: () async => source()),
        throwsArgumentError,
      );
    }
  });
  test('pixel dimensions reject zero, negative, fraction and nonfinite', () {
    for (final size in [
      const Size(0, 1),
      const Size(-1, 2),
      const Size(1.5, 2),
      const Size(double.infinity, 2),
      const Size(2, double.nan),
    ]) {
      expect(
        () =>
            ViewerSource(provider: const AssetImage('unused'), pixelSize: size),
        throwsArgumentError,
      );
    }
  });
  test('group rejects empty, duplicate IDs and invalid initial index', () {
    expect(() => ViewerController(items: []), throwsArgumentError);
    expect(
      () => ViewerController(items: [item('a'), item('a')]),
      throwsArgumentError,
    );
    for (final index in [-1, 1]) {
      expect(
        () => ViewerController(items: [item('a')], initialIndex: index),
        throwsArgumentError,
      );
    }
  });
  test('controller copies group and invalid replacement is atomic', () {
    final input = [item('a')];
    final controller = ViewerController(items: input);
    input.clear();
    expect(controller.items.length, 1);
    expect(() => controller.items.clear(), throwsUnsupportedError);
    expect(() => controller.replaceItems([]), throwsArgumentError);
    expect(controller.currentItem.id, 'a');
    expect(controller.generation, 0);
    controller.dispose();
  });
  testWidgets('initial index loads only current source, not the whole group', (
    tester,
  ) async {
    final calls = [0, 0, 0];
    final controller = ViewerController(
      items: List.generate(
        3,
        (i) => ViewerItem(
          id: '$i',
          loadSource: () async {
            calls[i]++;
            return source();
          },
        ),
      ),
      initialIndex: 1,
    );
    expect(calls, [0, 0, 0]);
    await mount(tester, controller);
    expect(calls, [0, 1, 0]);
    expect(controller.status, ViewerLoadStatus.ready);
    controller.select(2);
    await frames(tester);
    expect(calls, [0, 1, 1]);
  });
  testWidgets('source failure is sanitized, explicit retry succeeds', (
    tester,
  ) async {
    var calls = 0;
    final snapshots = <ViewerSnapshot>[];
    final controller = ViewerController(
      items: [
        ViewerItem(
          id: 'a',
          loadSource: () async {
            if (++calls == 1) throw StateError('private URL and secret path');
            return source();
          },
        ),
      ],
    );
    await mount(tester, controller, onChanged: snapshots.add);
    expect(controller.failure, ViewerFailure.sourceFailed);
    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('viewer-retry')));
    await frames(tester);
    expect(calls, 2);
    expect(controller.status, ViewerLoadStatus.ready);
    expect(snapshots.last.status, ViewerLoadStatus.ready);
  });
  testWidgets('decoded dimensions must match the input contract', (
    tester,
  ) async {
    final controller = ViewerController(
      items: [
        ViewerItem.provider(
          id: 'a',
          provider: MemoryImage(bytes['ordinary.png']!),
          pixelSize: const Size(1, 1),
        ),
      ],
    );
    await mount(tester, controller);
    expect(controller.failure, ViewerFailure.invalidSource);
    expect(find.text('图片尺寸与来源不匹配'), findsOneWidget);
    expect(find.byType(ExtendedImageGesture), findsNothing);
  });
  testWidgets('decode failure is a recoverable current-item failure', (
    tester,
  ) async {
    var calls = 0;
    final controller = ViewerController(
      items: [
        ViewerItem(
          id: 'a',
          loadSource: () async => ++calls == 1
              ? ViewerSource(
                  provider: MemoryImage(Uint8List.fromList([1, 2, 3])),
                  pixelSize: const Size(1, 1),
                )
              : source(),
        ),
      ],
    );
    await mount(tester, controller);
    expect(controller.failure, ViewerFailure.decodeFailed);
    controller.retry();
    await frames(tester);
    expect(controller.status, ViewerLoadStatus.ready);
  });
  testWidgets(
    'late source completion after paging cannot replace current image',
    (tester) async {
      final pending = Completer<ViewerSource>();
      final controller = ViewerController(
        items: [
          ViewerItem(id: 'a', loadSource: () => pending.future),
          item('b'),
        ],
      );
      await mount(tester, controller);
      controller.select(1);
      await frames(tester);
      pending.complete(source('long.png'));
      await frames(tester);
      expect(controller.currentItem.id, 'b');
      expect(
        gesture(tester).gestureDetails!.destinationRect!.height,
        closeTo(300, 0.1),
      );
    },
  );
  testWidgets('group replacement isolates late source even if ID is reused', (
    tester,
  ) async {
    final pending = Completer<ViewerSource>();
    final controller = ViewerController(
      items: [ViewerItem(id: 'a', loadSource: () => pending.future)],
    );
    await mount(tester, controller);
    controller.replaceItems([item('a')]);
    await frames(tester);
    pending.complete(source('long.png'));
    await frames(tester);
    expect(controller.generation, 1);
    expect(
      gesture(tester).gestureDetails!.destinationRect!.height,
      closeTo(300, 0.1),
    );
  });
  testWidgets(
    'old provider frame between selection and rebuild cannot mark new source ready',
    (tester) async {
      final provider = _PendingProvider();
      final pending = Completer<ViewerSource>();
      final controller = ViewerController(
        items: [
          ViewerItem.provider(
            id: 'a',
            provider: provider,
            pixelSize: const Size(640, 480),
          ),
          ViewerItem(id: 'b', loadSource: () => pending.future),
        ],
      );
      await mount(tester, controller);
      expect(controller.status, ViewerLoadStatus.loading);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 640, 480), Paint());
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(640, 480));
      picture.dispose();
      controller.select(1);
      provider.completer.publish(ImageInfo(image: image!));
      await frames(tester, 3);
      expect(controller.currentItem.id, 'b');
      expect(controller.status, ViewerLoadStatus.loading);
      expect(controller.failure, isNull);
      pending.complete(source());
      await frames(tester);
      expect(controller.status, ViewerLoadStatus.ready);
    },
  );
  testWidgets('access invalidation ends reads and emits one close callback', (
    tester,
  ) async {
    final pending = Completer<ViewerSource>();
    var calls = 0;
    final reasons = <ViewerCloseReason>[];
    final controller = ViewerController(
      items: [
        ViewerItem(
          id: 'a',
          loadSource: () {
            calls++;
            return pending.future;
          },
        ),
      ],
    );
    await mount(tester, controller, onClosed: reasons.add);
    controller.invalidateAccess();
    controller.retry();
    pending.complete(source());
    await frames(tester);
    expect(calls, 1);
    expect(controller.active, isFalse);
    expect(controller.accessValid, isFalse);
    expect(reasons, [ViewerCloseReason.accessInvalidated]);
    expect(find.text('访问已失效'), findsOneWidget);
    expect(find.byType(ExtendedImage), findsNothing);
  });
  testWidgets(
    'detaching suppresses queued and late callbacks and is terminal',
    (tester) async {
      final pending = Completer<ViewerSource>();
      final snapshots = <ViewerSnapshot>[];
      final controller = ViewerController(
        items: [ViewerItem(id: 'a', loadSource: () => pending.future)],
      );
      await mount(tester, controller, onChanged: snapshots.add);
      final count = snapshots.length;
      await tester.pumpWidget(const SizedBox());
      pending.complete(source());
      await frames(tester);
      expect(controller.closeReason, ViewerCloseReason.detached);
      expect(snapshots.length, count);
      expect(() => controller.replaceItems([item('b')]), throwsStateError);
    },
  );
  testWidgets(
    'background invalidates pending read and resumes with a new load',
    (tester) async {
      final pending = Completer<ViewerSource>();
      var calls = 0;
      final controller = ViewerController(
        items: [
          ViewerItem(
            id: 'a',
            loadSource: () =>
                ++calls == 1 ? pending.future : Future.value(source()),
          ),
        ],
      );
      await mount(tester, controller);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(source('long.png'));
      await frames(tester, 3);
      expect(controller.status, ViewerLoadStatus.idle);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester);
      expect(calls, 2);
      expect(controller.status, ViewerLoadStatus.ready);
    },
  );
  testWidgets(
    'ancestor TickerMode visibility pauses pending reads and reloads on return',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final pending = Completer<ViewerSource>();
      var calls = 0;
      final controller = ViewerController(
        items: [
          ViewerItem(
            id: 'a',
            loadSource: () =>
                ++calls == 1 ? pending.future : Future.value(source()),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, value, child) =>
                  TickerMode(enabled: value, child: child!),
              child: HnuImageViewer(controller: controller),
            ),
          ),
        ),
      );
      await frames(tester, 3);
      visible.value = false;
      await frames(tester, 2);
      pending.complete(source('long.png'));
      await frames(tester, 2);
      expect(controller.foreground, isFalse);
      expect(controller.status, ViewerLoadStatus.idle);
      visible.value = true;
      await frames(tester);
      expect(calls, 2);
      expect(controller.foreground, isTrue);
      expect(controller.status, ViewerLoadStatus.ready);
    },
  );
  testWidgets('ordinary image is centered; long image fits width from top', (
    tester,
  ) async {
    final controller = ViewerController(
      items: [item('short'), item('long', 'long.png')],
    );
    await mount(tester, controller);
    var details = gesture(tester).gestureDetails!;
    expect(details.destinationRect!.center, details.layoutRect!.center);
    controller.select(1);
    await frames(tester);
    details = gesture(tester).gestureDetails!;
    expect(details.destinationRect!.width, closeTo(400, 0.1));
    expect(details.destinationRect!.top, closeTo(details.layoutRect!.top, 0.1));
  });
  testWidgets('reading position follows stable ID across paging', (
    tester,
  ) async {
    final controller = ViewerController(
      items: [item('long', 'long.png'), item('b')],
    );
    await mount(tester, controller);
    await drag(tester, const Offset(0, -220));
    final before = gesture(tester).gestureDetails!.destinationRect!.top;
    controller.select(1);
    await frames(tester);
    expect(controller.readingPosition('long'), isNotNull);
    controller.select(0);
    await frames(tester);
    expect(
      gesture(tester).gestureDetails!.destinationRect!.top,
      closeTo(before, 1),
    );
  });
  testWidgets(
    'rotation preserves current ID, relative zoom and reading anchor',
    (tester) async {
      final controller = ViewerController(
        items: [item('long', 'long.png'), item('b')],
      );
      await mount(tester, controller);
      final beforeZoom = gesture(tester);
      beforeZoom.handleDoubleTap(
        scale: beforeZoom.imageGestureConfig!.initialScale * 2,
        doubleTapPosition: const Offset(200, 300),
      );
      await frames(tester);
      await drag(tester, const Offset(0, -300));
      final old = gesture(tester).gestureDetails!;
      final expectedAnchor =
          (old.layoutRect!.center.dy - old.destinationRect!.top) /
          old.destinationRect!.height;
      tester.view.physicalSize = const Size(600, 400);
      // Android may change lifecycle revision after layout queued a restore
      // but before its post-frame callback. The new revision must retry it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 400)),
            child: RepaintBoundary(
              key: const ValueKey('viewer-screenshot'),
              child: Scaffold(body: HnuImageViewer(controller: controller)),
            ),
          ),
        ),
      );
      await frames(tester);
      final details = gesture(tester).gestureDetails!;
      final anchor =
          (details.layoutRect!.center.dy - details.destinationRect!.top) /
          details.destinationRect!.height;
      expect(controller.currentItem.id, 'long');
      expect(
        details.totalScale! / gesture(tester).imageGestureConfig!.initialScale,
        closeTo(2, 0.01),
      );
      expect(anchor, closeTo(expectedAnchor, 0.005));
      tester.view.physicalSize = const Size(400, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 600)),
            child: RepaintBoundary(
              key: const ValueKey('viewer-screenshot'),
              child: Scaffold(body: HnuImageViewer(controller: controller)),
            ),
          ),
        ),
      );
      await frames(tester);
      final returned = gesture(tester).gestureDetails!;
      expect(
        returned.totalScale! / gesture(tester).imageGestureConfig!.initialScale,
        closeTo(2, 0.01),
      );
      expect(
        (returned.layoutRect!.center.dy - returned.destinationRect!.top) /
            returned.destinationRect!.height,
        closeTo(expectedAnchor, 0.005),
      );
    },
  );
  testWidgets('returning to top cannot close until a new pointer gesture', (
    tester,
  ) async {
    final reasons = <ViewerCloseReason>[];
    final controller = ViewerController(items: [item('long', 'long.png')]);
    await mount(tester, controller, onClosed: reasons.add);
    await drag(tester, const Offset(0, -220));
    final rect = tester.getRect(find.byKey(const ValueKey('viewer-pages')));
    final pointer = await tester.startGesture(rect.center);
    for (var i = 0; i < 12; i++) {
      await pointer.moveBy(const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 16));
      final slide = tester.state<ExtendedImageSlidePageState>(
        find.byType(ExtendedImageSlidePage),
      );
      expect(slide.offset, Offset.zero);
      expect(reasons, isEmpty);
    }
    await pointer.up();
    await frames(tester, 4);
    await drag(tester, const Offset(0, 160));
    expect(reasons, [ViewerCloseReason.gesture]);
    expect(find.byType(HnuImageViewer), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
  testWidgets('horizontal paging respects supplied group and zoom gate', (
    tester,
  ) async {
    final controller = ViewerController(
      items: [item('long', 'long.png'), item('b')],
    );
    await mount(tester, controller);
    final state = gesture(tester);
    state.handleDoubleTap(
      scale: state.imageGestureConfig!.initialScale * 2,
      doubleTapPosition: const Offset(200, 200),
    );
    await frames(tester, 3);
    await drag(tester, const Offset(-340, 0));
    expect(controller.index, 0);
    gesture(tester).reset();
    await frames(tester, 3);
    await drag(tester, const Offset(-340, 0));
    expect(controller.index, 1);
    await drag(tester, const Offset(-340, 0));
    expect(controller.index, 1);
  });
  for (final name in ['animation_infinite.gif', 'animation_infinite.webp']) {
    testWidgets('$name detaches animation listeners offpage/background/close', (
      tester,
    ) async {
      final animated = source(name);
      final controller = ViewerController(
        items: [
          ViewerItem(id: 'animated', loadSource: () async => animated),
          item('b'),
        ],
      );
      await mount(tester, controller);
      // Inspect the stream actually shown, including its resource guard.
      final resolved = tester
          .widget<ExtendedImage>(find.byType(ExtendedImage))
          .image
          .resolve(const ImageConfiguration());
      await frames(tester, 2);
      final stream = resolved.completer!;
      expect(stream.hasListeners, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await frames(tester, 3);
      expect(stream.hasListeners, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester, 4);
      expect(stream.hasListeners, isTrue);
      controller.select(1);
      await frames(tester, 4);
      expect(stream.hasListeners, isFalse);
      controller.close();
      await frames(tester, 4);
      expect(stream.hasListeners, isFalse);
    });
  }
  testWidgets('small screen at 3x text retains controls and image semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final controller = ViewerController(items: [item('a'), item('b')]);
      await mount(tester, controller, size: const Size(320, 480), textScale: 3);
      expect(tester.takeException(), isNull);
      for (final name in [
        'viewer-close',
        'viewer-save',
        'viewer-previous',
        'viewer-next',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(name)));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(480));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('viewer-save')))
            .onPressed,
        isNull,
      );
      final screenshotDirectory = Platform.environment['VIEWER_SCREENSHOT_DIR'];
      if (screenshotDirectory != null) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('viewer-screenshot')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$screenshotDirectory/viewer-large-text.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      expect(find.bySemanticsLabel('关闭图片查看'), findsOneWidget);
      expect(find.bySemanticsLabel('下一张图片'), findsOneWidget);
      expect(find.bySemanticsLabel('合成测试图片a'), findsOneWidget);
      final semanticEvidence = StringBuffer();
      for (final key in [
        'viewer-close',
        'viewer-save',
        'viewer-previous',
        'viewer-next',
      ]) {
        final data = tester
            .getSemantics(find.byKey(ValueKey(key)))
            .getSemanticsData();
        semanticEvidence.writeln(
          '$key: label=${data.label}; tooltip=${data.tooltip}; '
          'tap=${data.hasAction(ui.SemanticsAction.tap)}; rect=${data.rect}',
        );
        expect(
          data.hasAction(ui.SemanticsAction.tap),
          key == 'viewer-close' || key == 'viewer-next',
        );
      }
      if (screenshotDirectory != null) {
        await tester.runAsync(
          () =>
              File('$screenshotDirectory/viewer-large-text-semantics.txt')
                  .writeAsString(semanticEvidence.toString()),
        );
      }
      await tester.tap(find.byKey(const ValueKey('viewer-next')));
      await frames(tester);
      expect(controller.index, 1);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'close button reports once and never implicitly pops host route',
    (tester) async {
      final reasons = <ViewerCloseReason>[];
      final controller = ViewerController(items: [item('a')]);
      await mount(tester, controller, onClosed: reasons.add);
      await tester.tap(find.byKey(const ValueKey('viewer-close')));
      await frames(tester, 3);
      controller.close(ViewerCloseReason.systemBack);
      await frames(tester, 3);
      expect(reasons, [ViewerCloseReason.button]);
      expect(find.byType(Scaffold), findsOneWidget);
    },
  );
  testWidgets('system back reports once without popping the caller route', (
    tester,
  ) async {
    final reasons = <ViewerCloseReason>[];
    final controller = ViewerController(items: [item('a')]);
    await mount(tester, controller, onClosed: reasons.add);
    await tester.binding.handlePopRoute();
    await frames(tester, 3);
    expect(reasons, [ViewerCloseReason.systemBack]);
    expect(find.byType(HnuImageViewer), findsOneWidget);
  });
  testWidgets('one controller cannot attach to two viewers concurrently', (
    tester,
  ) async {
    final controller = ViewerController(items: [item('a')]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(child: HnuImageViewer(controller: controller)),
            Expanded(child: HnuImageViewer(controller: controller)),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'swapping controller detaches old session and its pending source',
    (tester) async {
      final pending = Completer<ViewerSource>();
      final old = ViewerController(
        items: [ViewerItem(id: 'old', loadSource: () => pending.future)],
      );
      final next = ViewerController(items: [item('new')]);
      addTearDown(next.dispose);
      await mount(tester, old);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 600)),
            child: RepaintBoundary(
              key: const ValueKey('viewer-screenshot'),
              child: Scaffold(body: HnuImageViewer(controller: next)),
            ),
          ),
        ),
      );
      pending.complete(source('long.png'));
      await frames(tester);
      expect(old.closeReason, ViewerCloseReason.detached);
      expect(next.currentItem.id, 'new');
      expect(next.status, ViewerLoadStatus.ready);
    },
  );
  for (final scenario in [
    (size: const Size(400, 600), scale: 1.0),
    (size: const Size(320, 240), scale: 3.0),
  ]) {
    testWidgets(
      'save feedback preserves viewport and bottom controls at ${scenario.scale}x text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final gallery = _UiGallery();
          final coordinator = ViewerSaveCoordinator(gallery: gallery);
          addTearDown(coordinator.dispose);
          final controller = ViewerController(
            items: [
              ViewerItem(
                id: 'a',
                loadSource: () async => source(),
                resolveOriginal: () async => ViewerOriginal.file(
                  File('example/assets/fixtures/ordinary.png').absolute.path,
                  ViewerOriginalFormat.png,
                ),
              ),
              item('b'),
            ],
          );
          await mount(
            tester,
            controller,
            saveCoordinator: coordinator,
            size: scenario.size,
            textScale: scenario.scale,
          );
          final viewportBefore = tester.getRect(
            find.byKey(const ValueKey('viewer-pages')),
          );
          final nextBefore = tester.getRect(
            find.byKey(const ValueKey('viewer-next')),
          );
          await tester.tap(find.byKey(const ValueKey('viewer-save')));
          await frames(tester, 4);
          expect(gallery.writes, 1);
          expect(find.text('已保存到相册'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final viewportAfter = tester.getRect(
            find.byKey(const ValueKey('viewer-pages')),
          );
          final nextAfter = tester.getRect(
            find.byKey(const ValueKey('viewer-next')),
          );
          expect(nextAfter, nextBefore);
          expect(
            viewportBefore.height - viewportAfter.height,
            lessThanOrEqualTo(scenario.size.height / 4 + 0.01),
          );
          expect(viewportAfter.height, greaterThan(0));
          expect(
            tester
                .getSemantics(find.text('已保存到相册'))
                .getSemanticsData()
                .flagsCollection
                .isLiveRegion,
            isTrue,
          );
          await tester.tap(find.byKey(const ValueKey('viewer-next')));
          await frames(tester);
          expect(controller.index, 1);
          expect(find.text('已保存到相册'), findsNothing);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  testWidgets(
    'save stays busy while closing remains available and late result is hidden',
    (tester) async {
      final gallery = _UiGallery()..pendingWrite = Completer<void>();
      final coordinator = ViewerSaveCoordinator(gallery: gallery);
      addTearDown(coordinator.dispose);
      final controller = ViewerController(
        items: [
          ViewerItem(
            id: 'a',
            loadSource: () async => source(),
            resolveOriginal: () async => ViewerOriginal.file(
              File('example/assets/fixtures/ordinary.png').absolute.path,
              ViewerOriginalFormat.png,
            ),
          ),
        ],
      );
      await mount(tester, controller, saveCoordinator: coordinator);
      await tester.tap(find.byKey(const ValueKey('viewer-save')));
      await frames(tester, 3);
      expect(gallery.writes, 1);
      expect(coordinator.busy, isTrue);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('viewer-save')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('viewer-close')));
      gallery.pendingWrite!.complete();
      await frames(tester, 3);
      expect(controller.active, isFalse);
      expect(find.text('已保存到相册'), findsNothing);
    },
  );
  testWidgets('replacing saver suppresses its pending late feedback', (
    tester,
  ) async {
    final gallery = _UiGallery()..pendingWrite = Completer<void>();
    final oldSaver = ViewerSaveCoordinator(gallery: gallery);
    final newSaver = ViewerSaveCoordinator(gallery: _UiGallery());
    addTearDown(oldSaver.dispose);
    addTearDown(newSaver.dispose);
    final controller = ViewerController(
      items: [
        ViewerItem(
          id: 'a',
          loadSource: () async => source(),
          resolveOriginal: () async => ViewerOriginal.file(
            File('example/assets/fixtures/ordinary.png').absolute.path,
            ViewerOriginalFormat.png,
          ),
        ),
      ],
    );
    await mount(tester, controller, saveCoordinator: oldSaver);
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await frames(tester, 3);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 600)),
          child: RepaintBoundary(
            key: const ValueKey('viewer-screenshot'),
            child: Scaffold(
              body: HnuImageViewer(
                controller: controller,
                saveCoordinator: newSaver,
              ),
            ),
          ),
        ),
      ),
    );
    gallery.pendingWrite!.complete();
    await frames(tester, 4);
    expect(controller.active, isTrue);
    expect(find.text('已保存到相册'), findsNothing);
  });
}
