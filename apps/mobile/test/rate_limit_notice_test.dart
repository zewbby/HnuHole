import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/rate_limit_notice.dart';

void main() {
  testWidgets(
    'local countdown unlocks manual retry only and disposes its timer',
    (tester) async {
      final deadline = tester.binding.clock.now().add(
        const Duration(seconds: 2),
      );
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RateLimitDraftNotice(
              remaining: () =>
                  (deadline
                              .difference(tester.binding.clock.now())
                              .inMilliseconds /
                          1000)
                      .ceil()
                      .clamp(0, 2),
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      expect(find.textContaining('2 秒'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('1 秒'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('等待结束'), findsOneWidget);
      expect(retries, 0);
      await tester.tap(find.text('重试原草稿'));
      expect(retries, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
