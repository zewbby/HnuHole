import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';
import 'login_home_test_support.dart';

const _channel = '00000000-0000-0000-0000-000000000001';

void main() {
  for (final fromFeed in [false, true]) {
    testWidgets(
      'root My route switches A to B and fences old publication; feed=$fromFeed',
      (tester) async {
        final f = HomeTestFixture();
        await tester.pumpWidget(await f.create());
        await tester.pumpAndSettle();
        State? oldFeed;
        if (fromFeed) {
          await f.posts.loadTimeline(channelId: _channel);
          await tester.pumpAndSettle();
          oldFeed = tester.state(find.byType(FeedScreen));
          tester.widget<FeedScreen>(find.byType(FeedScreen)).onOpenPersonal!();
        } else {
          await tester.tap(find.byKey(const ValueKey('feed-account')));
        }
        await tester.pumpAndSettle();
        expect(find.text('账号A的身份'), findsOneWidget);
        final oldPersonal = tester.widget<PersonalPostsScreen>(
          find.byType(PersonalPostsScreen),
        );
        final oldState = tester.state(find.byType(PersonalPostsScreen));
        await f.sessions.persistSessionMetadata(
          identityTestToken,
          identityTestRenewed,
          () => true,
        );
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(PersonalPostsScreen)), oldState),
          isTrue,
        );
        await f.loginB(tester);
        expect(find.text('账号B的身份'), findsOneWidget);
        expect(find.text('账号A的身份'), findsNothing);
        expect(find.text('请重新核对登录状态'), findsNothing);
        expect(f.postApi.personalTokens, contains(identityTestOtherToken));
        oldPersonal.onPublishedToChannel!(_channel);
        await tester.pumpAndSettle();
        expect(find.byType(PersonalPostsScreen), findsOneWidget);
        final current = tester.widget<PersonalPostsScreen>(
          find.byType(PersonalPostsScreen),
        );
        current.onPublishedToChannel!(_channel);
        await tester.pumpAndSettle();
        expect(find.byType(FeedScreen), findsOneWidget);
        expect(find.text('请重新核对登录状态'), findsNothing);
        if (fromFeed) {
          expect(
            identical(tester.state(find.byType(FeedScreen)), oldFeed),
            isFalse,
          );
        }
        final currentFeed = tester.state(find.byType(FeedScreen));
        tester.widget<FeedScreen>(find.byType(FeedScreen)).onOpenPersonal!();
        await tester.pumpAndSettle();
        tester
            .widget<PersonalPostsScreen>(find.byType(PersonalPostsScreen))
            .onPublishedToChannel!(_channel);
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(FeedScreen)), currentFeed),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final status in [null, 401, 503]) {
    testWidgets(
      'late personal read from A cannot change B route/session: $status',
      (tester) async {
        final f = HomeTestFixture();
        f.postApi.oldPersonal = Completer();
        await tester.pumpWidget(await f.create());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('feed-account')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await f.loginB(tester);
        expect(find.text('账号B的身份'), findsOneWidget);
        final token = f.store.current!.session!.token;
        final expiry = f.store.current!.session!.expiresAt;
        if (status == null) {
          f.postApi.oldPersonal!.complete(
            feed.reply(PostsPage(items: [], nextCursor: null)),
          );
        } else {
          f.postApi.oldPersonal!.completeError(
            PostFailure(
              kind: status == 401
                  ? PostFailureKind.unauthorized
                  : PostFailureKind.unavailable,
              statusCode: status,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('账号B的身份'), findsOneWidget);
        expect(find.text('请重新核对登录状态'), findsNothing);
        expect(f.sessions.isAuthenticated, isTrue);
        expect(f.store.current!.session!.token, token);
        expect(f.store.current!.session!.expiresAt, expiry);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('same-account explicit new login recreates My window', (
    tester,
  ) async {
    final f = HomeTestFixture();
    await tester.pumpWidget(await f.create());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feed-account')));
    await tester.pumpAndSettle();
    final old = tester.state(find.byType(PersonalPostsScreen));
    await f.loginB(tester, account: identityTestAccount, name: '同账号的新窗口');
    expect(find.text('同账号的新窗口'), findsOneWidget);
    expect(
      identical(tester.state(find.byType(PersonalPostsScreen)), old),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('delayed B directory gates home until the complete directory', (
    tester,
  ) async {
    final f = HomeTestFixture();
    await tester.pumpWidget(await f.create());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feed-account')));
    await tester.pumpAndSettle();
    f.channels.wait = Completer();
    await f.loginB(tester, directoryPending: true);
    expect(find.byType(FeedScreen), findsNothing);
    expect(find.text('正在准备首页…'), findsOneWidget);
    f.channels.wait!.complete(
      await IdentityTestChannels().loadChannels(
        sessionToken: identityTestOtherToken,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FeedScreen>(find.byType(FeedScreen)).channels,
      hasLength(7),
    );
    expect(f.posts.timelineChannelId, isNull);
    expect(find.byType(PersonalPostsScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('feed-account')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PersonalPostsScreen>(find.byType(PersonalPostsScreen))
          .channelNames,
      hasLength(7),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final status in [503, 401]) {
    testWidgets('root feed recovers $status with the correct session policy', (
      tester,
    ) async {
      final f = HomeTestFixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      final oldToken = f.store.current!.session!.token;
      f.postApi.timelineFailure = PostFailure(
        kind: status == 401
            ? PostFailureKind.unauthorized
            : PostFailureKind.unavailable,
        code: status == 401 ? 'SESSION_INVALID' : 'AUTHORIZATION_UNAVAILABLE',
        statusCode: status,
      );
      await f.posts.loadTimeline();
      await tester.pumpAndSettle();
      expect(f.sessions.isAuthenticated, isFalse);
      expect(f.store.current!.session?.token, status == 503 ? oldToken : null);
      if (status == 503) {
        await tester.tap(find.text('重新核对会话'));
      } else {
        await tester.tap(find.byKey(const ValueKey('auth-start')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'device_a');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'valid-password-123',
        );
        await tester.tap(find.byKey(const ValueKey('login-submit')));
      }
      await tester.pumpAndSettle();
      expect(f.sessions.isAuthenticated, isTrue);
      expect(f.sessionApi.logins, status == 503 ? 0 : 1);
      expect(
        f.store.current!.session!.token,
        status == 503 ? oldToken : identityTestOtherToken,
      );
      expect(find.byType(AuthScreen), findsNothing);
      expect(find.text('登录或核对会话'), findsNothing);
      expect(find.text('请重新登录'), findsNothing);
      expect(find.text('今天的校园'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
