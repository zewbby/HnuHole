import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:image_viewer_m1/main.dart' as app;

/// Dedicated example only. No export unless explicitly enabled for that run.
/// A plugin success here never proves system-album animation playback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'long image: same gesture back to top cannot dismiss; new pull can',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();
      await tester.tap(find.text('long.png'));
      await tester.pumpAndSettle();
      final finder = find.byType(M1ViewerProbe);
      final state = tester.state<M1ViewerProbeState>(finder);
      final bounds = tester.getRect(finder);
      expect(state.imageRect!.width, closeTo(bounds.width, 1));
      expect(state.atTop, isTrue);
      Future<void> drag(Offset delta) async {
        final g = await tester.startGesture(bounds.center);
        for (var i = 0; i < 8; i++) {
          await g.moveBy(delta / 8);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pumpAndSettle();
      }

      await drag(const Offset(0, -240));
      expect(state.atTop, isFalse);
      final g = await tester.startGesture(
        bounds.topCenter + const Offset(0, 80),
      );
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, 45));
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.widget.metrics.closed, 0);
        expect(state.slideOffset, Offset.zero);
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(state.atTop, isTrue);
      expect(state.widget.metrics.maxSlideDistance, 0);
      await drag(const Offset(0, 160));
      expect(find.byType(app.ProbeLauncher), findsOneWidget);
    },
  );
  testWidgets(
    'original GIF/WebP export: operator grants permission, verifies album separately',
    (tester) async {
      if (!const bool.fromEnvironment('M1_EXPORT_FIXTURES')) return;
      app.main();
      await tester.pumpAndSettle();
      for (final name in ['animation.gif', 'animation.webp']) {
        await tester.tap(find.text(name));
        // Finite animations; frame callbacks settle after their declared loops.
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('保存当前原图'));
        await tester.pump(const Duration(seconds: 1));
        // System permission dialogs need the device operator.
        final wait = Stopwatch()..start();
        while (find.text('系统写入完成，请到相册检查动画回放').evaluate().isEmpty &&
            wait.elapsed < const Duration(minutes: 1)) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('系统写入完成，请到相册检查动画回放'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
    skip: !const bool.fromEnvironment('M1_EXPORT_FIXTURES'),
  );
}
