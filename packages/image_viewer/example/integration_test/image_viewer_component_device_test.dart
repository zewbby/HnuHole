import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_viewer_m1/main.dart' as app;

/// Dedicated component example only. Native/device evidence is NOT_RUN until
/// this entry is actually executed on a separately authorized device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> finishSourceLoad(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      final controller = tester
          .widget<HnuImageViewer>(find.byType(HnuImageViewer))
          .controller;
      if (controller.status != ViewerLoadStatus.loading &&
          controller.status != ViewerLoadStatus.idle) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    fail('The synthetic component source did not settle.');
  }

  Future<void> open(WidgetTester tester, String fixture) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixture));
    await tester.pumpAndSettle();
    await finishSourceLoad(tester);
  }

  testWidgets('component route: reading gesture then new pull closes once', (
    tester,
  ) async {
    await open(tester, 'long.png');
    final finder = find.byType(HnuImageViewer);
    final controller = tester.widget<HnuImageViewer>(finder).controller;
    expect(controller.status, ViewerLoadStatus.ready);
    final bounds = tester.getRect(finder);
    Future<void> drag(Offset delta) async {
      final gesture = await tester.startGesture(bounds.center);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(delta / 8);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag(const Offset(0, -240));
    final gesture = await tester.startGesture(bounds.center);
    for (var i = 0; i < 16; i++) {
      await gesture.moveBy(const Offset(0, 45));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.active, isTrue);
      expect(find.byType(HnuImageViewer), findsOneWidget);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.active, isTrue);
    await drag(const Offset(0, 160));
    expect(find.byType(HnuImageViewer), findsNothing);
    expect(find.text('独立图片组件'), findsOneWidget);
  });

  testWidgets('component source error retry and access invalidation', (
    tester,
  ) async {
    await open(tester, '首次失败与手动重试');
    expect(find.text('图片加载失败'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-retry')));
    await tester.pumpAndSettle();
    await finishSourceLoad(tester);
    final controller = tester
        .widget<HnuImageViewer>(find.byType(HnuImageViewer))
        .controller;
    expect(controller.status, ViewerLoadStatus.ready);
    await tester.tap(find.byTooltip('模拟访问失效'));
    await tester.pumpAndSettle();
    expect(find.byType(HnuImageViewer), findsNothing);
    expect(find.text('独立图片组件'), findsOneWidget);
  });

  testWidgets(
    'native original GIF/WebP import; operator checks file and album separately',
    (tester) async {
      for (final name in ['animation.gif', 'animation.webp']) {
        await open(tester, name);
        await tester.tap(find.byKey(const ValueKey('viewer-save')));
        final elapsed = Stopwatch()..start();
        while (find.text('已保存到相册').evaluate().isEmpty &&
            elapsed.elapsed < const Duration(minutes: 1)) {
          // System permission dialogs require the dedicated device operator.
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('已保存到相册'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('viewer-close')));
        await tester.pumpAndSettle();
      }
    },
    skip:
        !const bool.fromEnvironment('VIEWER_ENABLE_NATIVE_EXPORT') ||
        appFlavor != 'nativecheck',
  );
}
