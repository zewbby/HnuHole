import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

void main() {
  final data = <String, Uint8List>{};
  setUpAll(() async {
    for (final name in [
      'ordinary.png',
      'long.png',
      'animation_infinite.gif',
      'animation_infinite.webp',
    ]) {
      data[name] = await File('example/assets/fixtures/$name').readAsBytes();
    }
  });
  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> open(
    WidgetTester tester,
    GlobalKey<M1ViewerProbeState> key,
    ProbeMetrics metrics,
    List<String> names, {
    ValueNotifier<bool>? access,
  }) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = names
        .map(
          (name) => ProbeImage(
            name,
            MemoryImage(Uint8List.fromList(data[name]!)),
            name == 'long.png'
                ? const Size(480, 2400)
                : name == 'ordinary.png'
                ? const Size(640, 480)
                : const Size(96, 72),
          ),
        )
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: access == null
                      ? M1ViewerProbe(
                          key: key,
                          images: images,
                          metrics: metrics,
                        )
                      : ValueListenableBuilder<bool>(
                          valueListenable: access,
                          builder: (context, active, child) => M1ViewerProbe(
                            key: key,
                            images: images,
                            metrics: metrics,
                            active: active,
                          ),
                        ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await frames(tester, 20);
  }

  Future<void> dragSteps(
    WidgetTester tester,
    Offset delta, {
    int steps = 8,
  }) async {
    final gesture = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(delta / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester, 5);
  }

  testWidgets('long image fits viewport width and starts at top', (
    tester,
  ) async {
    final key = GlobalKey<M1ViewerProbeState>();
    await open(tester, key, ProbeMetrics(), ['long.png']);
    expect(key.currentState!.baseline, closeTo(10 / 3, 0.001));
    expect(key.currentState!.imageRect!.width, closeTo(400, 0.1));
    expect(key.currentState!.imageRect!.top, closeTo(0, 0.1));
    expect(key.currentState!.atTop, isTrue);
  });
  testWidgets(
    'reading back to top in the same gesture never slides or closes',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['long.png']);
      await dragSteps(tester, const Offset(0, -260));
      expect(key.currentState!.atTop, isFalse);
      final g = await tester.startGesture(const Offset(200, 120));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 16));
        expect(m.closed, 0);
        expect(key.currentState!.slideOffset, Offset.zero);
      }
      expect(key.currentState!.atTop, isTrue);
      await g.up();
      await frames(tester, 5);
      expect(m.slideUpdates, 0);
      expect(m.closed, 0);
      await dragSteps(tester, const Offset(0, 160));
      expect(m.closed, 1);
      expect(find.text('open'), findsOneWidget);
    },
  );
  testWidgets('short downward pull cancels and a new pull can close', (
    tester,
  ) async {
    final key = GlobalKey<M1ViewerProbeState>();
    final m = ProbeMetrics();
    await open(tester, key, m, ['long.png']);
    await dragSteps(tester, const Offset(0, 60));
    expect(m.closed, 0);
    expect(key.currentState!.slideOffset, Offset.zero);
    await dragSteps(tester, const Offset(0, 160));
    expect(m.closed, 1);
  });
  testWidgets(
    'one-frame pointer burst still requires a new gesture at the top',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['long.png']);
      await dragSteps(tester, const Offset(0, -200));
      final g = await tester.startGesture(const Offset(200, 100));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, 40));
      }
      await g.up();
      await frames(tester, 5);
      expect(m.closed, 0);
      expect(m.maxSlideDistance, 0);
      final next = await tester.startGesture(const Offset(200, 100));
      for (var i = 0; i < 4; i++) {
        await next.moveBy(const Offset(0, 40));
      }
      await next.up();
      await frames(tester, 5);
      expect(m.closed, 1);
    },
  );
  testWidgets('horizontal gesture switches only inside the supplied group', (
    tester,
  ) async {
    final key = GlobalKey<M1ViewerProbeState>();
    final m = ProbeMetrics();
    await open(tester, key, m, ['ordinary.png', 'long.png']);
    await dragSteps(tester, const Offset(-340, 0));
    expect(key.currentState!.index, 1);
    expect(m.closed, 0);
    expect(m.maxSlideDistance, 0);
    await dragSteps(tester, const Offset(-340, 0));
    expect(key.currentState!.index, 1);
  });
  testWidgets('two-pointer zoom and zoomed drag cannot dismiss or switch', (
    tester,
  ) async {
    final key = GlobalKey<M1ViewerProbeState>();
    final m = ProbeMetrics();
    await open(tester, key, m, ['long.png', 'ordinary.png']);
    final a = await tester.startGesture(const Offset(120, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(280, 300), pointer: 2);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await a.moveBy(const Offset(-15, 0));
      await b.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await frames(tester, 5);
    expect(key.currentState!.scale, greaterThan(key.currentState!.baseline));
    await dragSteps(tester, const Offset(0, 160));
    await dragSteps(tester, const Offset(-340, 0));
    expect(key.currentState!.index, 0);
    expect(m.closed, 0);
  });
  testWidgets(
    'adding a second pointer while pulling revokes close eligibility',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['long.png']);
      final a = await tester.startGesture(const Offset(200, 100), pointer: 1);
      await tester.pump();
      await a.moveBy(const Offset(0, 60));
      await tester.pump();
      final b = await tester.startGesture(const Offset(280, 160), pointer: 2);
      await tester.pump();
      await a.moveBy(const Offset(0, 160));
      await b.moveBy(const Offset(0, 160));
      await tester.pump();
      await a.up();
      await b.up();
      await frames(tester, 5);
      expect(m.closed, 0);
    },
  );
  for (final name in ['animation_infinite.gif', 'animation_infinite.webp']) {
    testWidgets(
      '$name stops stream listening off page, background, and close',
      (tester) async {
        final key = GlobalKey<M1ViewerProbeState>();
        final m = ProbeMetrics();
        await open(tester, key, m, [name, 'ordinary.png']);
        expect(m.frames[name]!, greaterThan(2));
        expect(m.streams[name]!.hasListeners, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await frames(tester, 3);
        final stopped = m.frames[name];

        expect(m.streams[name]!.hasListeners, isFalse);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await frames(tester, 12);
        expect(m.frames[name], stopped);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await frames(tester, 6);
        expect(m.frames[name]!, greaterThan(stopped!));
        key.currentState!.nextForProbe();
        await frames(tester, 5);
        expect(m.streams[name]!.hasListeners, isFalse);
        final afterPage = m.frames[name];
        await frames(tester, 12);
        expect(m.frames[name], afterPage);
        Navigator.of(key.currentContext!).pop();
        await frames(tester, 8);
        expect(m.streams[name]!.hasListeners, isFalse);
      },
    );
  }

  testWidgets('ordinary image is contained and centered, and can dismiss', (
    tester,
  ) async {
    final key = GlobalKey<M1ViewerProbeState>();
    final m = ProbeMetrics();
    await open(tester, key, m, ['ordinary.png']);
    expect(key.currentState!.imageRect!.size, const Size(400, 300));
    expect(key.currentState!.imageRect!.center, const Offset(200, 300));
    await dragSteps(tester, const Offset(0, 160));
    expect(m.closed, 1);
  });
  testWidgets(
    'long image can page forward and back at its width-fit baseline',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['long.png', 'ordinary.png']);
      await dragSteps(tester, const Offset(-340, 0));
      await frames(tester, 8);
      expect(key.currentState!.index, 1);
      await dragSteps(tester, const Offset(340, 0));
      await frames(tester, 8);
      expect(key.currentState!.index, 0);
      expect(m.closed, 0);
    },
  );
  testWidgets('double tap zooms and returns to the per-image baseline', (
    tester,
  ) async {
    final key = GlobalKey<M1ViewerProbeState>();
    final m = ProbeMetrics();
    await open(tester, key, m, ['long.png']);
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(const Offset(200, 220));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await frames(tester, 4);
    expect(
      key.currentState!.scale,
      closeTo(key.currentState!.baseline * 2, 0.01),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(const Offset(200, 220));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await frames(tester, 4);
    expect(key.currentState!.scale, closeTo(key.currentState!.baseline, 0.01));
    expect(m.closed, 0);
  });
  testWidgets(
    'pointer cancellation above close threshold cancels instead of dismissing',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['long.png']);
      final g = await tester.startGesture(const Offset(200, 100));
      await g.moveBy(const Offset(0, 130));
      await tester.pump();
      await g.cancel();
      await frames(tester, 8);
      expect(m.closed, 0);
      expect(key.currentState!.slideOffset, Offset.zero);
      await dragSteps(tester, const Offset(0, 160));
      expect(m.closed, 1);
    },
  );
  testWidgets(
    'access revocation disposes animation and closes pending gestures',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      final access = ValueNotifier(true);
      addTearDown(access.dispose);
      await open(tester, key, m, ['animation_infinite.gif'], access: access);
      expect(m.frames['animation_infinite.gif']!, greaterThan(1));
      access.value = false;
      await frames(tester, 5);
      final stopped = m.frames['animation_infinite.gif'];
      expect(find.text('访问已失效'), findsOneWidget);
      expect(m.streams['animation_infinite.gif']!.hasListeners, isFalse);
      await frames(tester, 12);
      expect(m.frames['animation_infinite.gif'], stopped);
    },
  );

  testWidgets(
    'vertical reading cannot change into paging before all pointers lift',
    (tester) async {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['long.png', 'ordinary.png']);
      await dragSteps(tester, const Offset(0, -160));
      final g = await tester.startGesture(const Offset(200, 180));
      await g.moveBy(const Offset(0, -50));
      await tester.pump();
      await g.moveBy(const Offset(-340, 0));
      await tester.pump();
      await g.up();
      await frames(tester, 8);
      expect(key.currentState!.index, 0);
      expect(m.closed, 0);
    },
  );
  testWidgets('repeated open and close releases each animated stream', (
    tester,
  ) async {
    for (var i = 0; i < 4; i++) {
      final key = GlobalKey<M1ViewerProbeState>();
      final m = ProbeMetrics();
      await open(tester, key, m, ['animation_infinite.webp']);
      expect(m.frames['animation_infinite.webp']!, greaterThan(1));
      final exitDuration = ModalRoute.of(key.currentContext!)!
          .reverseTransitionDuration;
      Navigator.of(key.currentContext!).pop();
      await frames(tester, (exitDuration.inMilliseconds / 40).ceil() + 3);
      expect(key.currentState, isNull);
      expect(m.streams['animation_infinite.webp']!.hasListeners, isFalse);
    }
  });
}
