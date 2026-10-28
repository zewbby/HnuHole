import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

import 'package:hnuhole_mobile/src/auth/welcome_at_mark.dart';

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
    'startup keeps the shared welcome mark until signed-out is confirmed',
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
      double entranceOpacity(String key) => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      expect(find.byKey(const ValueKey('auth-welcome')), findsOneWidget);
      expect(find.byType(WelcomeAtMark), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-feed')), findsNothing);
      expect(entranceOpacity('welcome-theme-controls-animation'), 0);
      expect(entranceOpacity('welcome-action-controls-animation'), 0);
      expect(find.bySemanticsLabel('开始使用'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.binding.transientCallbackCount, 0);
      directory.signOut();
      await tester.pumpWidget(
        MaterialApp(
          home: EntryScreen(directory: directory, onLoginRequested: () {}),
        ),
      );
      await tester.pump();
      expect(entranceOpacity('welcome-action-controls-animation'), 0);
      await tester.pump(const Duration(milliseconds: 230));
      final midEntrance = entranceOpacity('welcome-action-controls-animation');
      expect(midEntrance, greaterThan(0));
      expect(midEntrance, lessThan(1));
      await tester.pumpAndSettle();
      expect(entranceOpacity('welcome-action-controls-animation'), 1);
      expect(find.byKey(const ValueKey('auth-start')), findsOneWidget);
      expect(find.text('重新核对会话'), findsNothing);
    },
  );

  testWidgets('directory loading keeps the same logo-only welcome screen', (
    tester,
  ) async {
    final directoryResult = Completer<ChannelDirectoryResult>();
    final directory = ChannelDirectoryController(
      repository: _DeferredChannels(directoryResult.future),
    )..onSessionMetadata = (token, expiresAt, isCurrent) async => isCurrent();
    addTearDown(directory.dispose);
    final load = directory.setSessionToken('verified-session');
    expect(directory.status, ChannelDirectoryStatus.loading);
    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(directory: directory, onLoginRequested: () {}),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('auth-welcome')), findsOneWidget);
    expect(find.byType(WelcomeAtMark), findsOneWidget);
    expect(find.bySemanticsLabel('开始使用'), findsNothing);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(
                const ValueKey('welcome-action-controls-animation'),
              ),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0,
    );

    directoryResult.complete(
      await IdentityTestChannels().loadChannels(
        sessionToken: 'verified-session',
      ),
    );
    await load;
    await tester.pumpAndSettle();
    expect(directory.status, ChannelDirectoryStatus.ready);
    expect(find.byType(WelcomeAtMark), findsOneWidget);
    expect(find.bySemanticsLabel('开始使用'), findsNothing);

    directory.signOut();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('开始使用'), findsOneWidget);
  });
}

class _DeferredChannels implements ChannelRepository {
  const _DeferredChannels(this.result);

  final Future<ChannelDirectoryResult> result;

  @override
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken}) =>
      result;
}
