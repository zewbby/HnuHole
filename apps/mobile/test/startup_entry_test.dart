import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

void main() {
  testWidgets(
    'failure stays on login with a title-only dialog and preserves retry',
    (tester) async {
      final directory = ChannelDirectoryController(
        repository: IdentityTestChannels(),
      );
      addTearDown(directory.dispose);
      var retries = 0;
      directory.onSessionRetry = () async {
        retries++;
        directory.suspend();
      };
      directory.suspend();
      Widget screen() => MaterialApp(
        home: EntryScreen(directory: directory, onLoginRequested: () {}),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-welcome')), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-feed')), findsNothing);
      expect(find.text('暂时无法进入'), findsOneWidget);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).content,
        isNull,
      );
      expect(find.textContaining('会话'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(retries, 0);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      directory.signOut();
      await tester.pumpAndSettle();
      directory.suspend();
      await tester.pumpAndSettle();
      expect(find.text('暂时无法进入'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(find.text('暂时无法进入'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-welcome')), findsOneWidget);
    },
  );

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
      expect(find.byKey(const ValueKey('feed-account')), findsOneWidget);
      expect(find.text('推荐'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final header = tester.getTopLeft(
        find.byKey(const ValueKey('feed-account')),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('feed-account'))),
        header,
      );
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
