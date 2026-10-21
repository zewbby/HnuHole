import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'login_home_test_support.dart';

void main() {
  testWidgets(
    'welcome and login keep one theme through navigation and live toggles',
    (tester) async {
      final fixture = HomeTestFixture();
      await tester.pumpWidget(await fixture.create(signedIn: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auth-theme-toggle')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byKey(const ValueKey('auth-welcome'))))
            .brightness,
        Brightness.dark,
      );
      await tester.tap(find.byKey(const ValueKey('auth-start')));
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      final title = find.text('欢迎回来');
      expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('auth-theme-toggle')).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      Navigator.of(tester.element(title)).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-welcome')), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byKey(const ValueKey('auth-welcome'))))
            .brightness,
        Brightness.light,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
