import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

void main() {
  testWidgets(
    'startup shows a static home shell until signed-out is confirmed',
    (tester) async {
      final directory = ChannelDirectoryController(
        repository: IdentityTestChannels(),
      );
      addTearDown(directory.dispose);
      directory.suspend();
      await tester.pumpWidget(
        MaterialApp(
          home: EntryScreen(
            directory: directory,
            restoringSession: true,
            onLoginRequested: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('startup-feed')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-start')), findsNothing);
      expect(find.text('HnuHole'), findsOneWidget);
      expect(find.text('推荐'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final header = tester.getTopLeft(find.text('HnuHole'));
      await tester.pump(const Duration(seconds: 10));
      expect(tester.getTopLeft(find.text('HnuHole')), header);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(
        find.byKey(const ValueKey('destination:personal')),
        warnIfMissed: false,
      );
      expect(find.byKey(const ValueKey('startup-feed')), findsOneWidget);
      expect(find.text('会话暂时无法确认，请重试。'), findsNothing);
      expect(find.text('重新核对会话'), findsNothing);
      directory.signOut();
      await tester.pumpWidget(
        MaterialApp(
          home: EntryScreen(directory: directory, onLoginRequested: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-start')), findsOneWidget);
      expect(find.text('重新核对会话'), findsNothing);
    },
  );
}
