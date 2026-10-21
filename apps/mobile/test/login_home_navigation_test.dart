import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';
import 'login_home_test_support.dart';

void expectHome(
  WidgetTester tester,
  HomeTestFixture fixture, {
  String? channelId,
  String title = '推荐',
}) {
  expect(find.byType(FeedScreen), findsOneWidget);
  expect(find.byType(EntryScreen), findsNothing);
  expect(find.byType(AuthScreen), findsNothing);
  expect(fixture.posts.timelineChannelId, channelId);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('feed-channel-picker')),
      matching: find.text(title),
    ),
    findsOneWidget,
  );
  final context = tester.element(find.byType(FeedScreen));
  expect(ModalRoute.of(context)!.isFirst, isTrue);
  expect(Navigator.of(context).canPop(), isFalse);
  final home = find
      .ancestor(
        of: find.byKey(const ValueKey('destination:home')),
        matching: find.byType(Semantics),
      )
      .first;
  expect(tester.widget<Semantics>(home).properties.selected, isTrue);
}

Future<void> pickChannel(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
  await tester.pumpAndSettle();
  final choice = find.byKey(ValueKey('choose-channel:$id'));
  await tester.scrollUntilVisible(
    choice,
    150,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('channel-options')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('password login goes directly to recommended root home', (
    tester,
  ) async {
    final f = HomeTestFixture();
    await tester.pumpWidget(await f.create(signedIn: false));
    await tester.pumpAndSettle();
    expect(find.byType(FeedScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('auth-start')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'device_a');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'valid-password-123',
    );
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(f.sessionApi.logins, 1);
    expectHome(tester, f);
    expect(f.postApi.calls, contains('feed:recommended:first:20'));
    await disposeApp(tester);
  });

  testWidgets(
    'restored session opens recommended home with no selection page',
    (tester) async {
      final f = HomeTestFixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      expect(f.sessionApi.logins, 0);
      expectHome(tester, f);
      // Returning from a post cannot reveal a former selection page.
      await tester.tap(find.text('今天的校园'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(PostDetailScreen))).pop();
      await tester.pumpAndSettle();
      expectHome(tester, f);
      await disposeApp(tester);
    },
  );

  for (final sameAccount in [false, true]) {
    testWidgets(
      'login retains only this account channel within app run; sameAccount=$sameAccount',
      (tester) async {
        final f = HomeTestFixture();
        await tester.pumpWidget(await f.create());
        await tester.pumpAndSettle();
        final oldHome = tester.state(find.byType(FeedScreen));
        final channel = f.directory.channels.last.id;
        await pickChannel(tester, channel);
        expect(f.posts.timelineChannelId, channel);
        await tester.tap(find.byKey(const ValueKey('feed-account')));
        await tester.pumpAndSettle();
        await f.loginB(
          tester,
          account: sameAccount
              ? identityTestAccount
              : '00000000-0000-0000-0000-000000000002',
          openPersonal: false,
          expectedChannelId: sameAccount ? channel : null,
        );
        expectHome(
          tester,
          f,
          channelId: sameAccount ? channel : null,
          title: sameAccount ? f.directory.channels.last.name : '推荐',
        );
        expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
        expect(
          find.byType(PersonalPostsScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          identical(oldHome, tester.state(find.byType(FeedScreen))),
          isFalse,
        );
        await disposeApp(tester);
      },
    );
  }

  testWidgets(
    'home button preserves selected channel, loaded data and root route',
    (tester) async {
      final f = HomeTestFixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      final channel = f.directory.channels.first;
      await pickChannel(tester, channel.id);
      final home = tester.state(find.byType(FeedScreen));
      final calls = List.of(f.postApi.calls);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('destination:home')));
        await tester.pumpAndSettle();
        expectHome(tester, f, channelId: channel.id, title: channel.name);
        expect(identical(home, tester.state(find.byType(FeedScreen))), isTrue);
        expect(f.postApi.calls, calls);
      }
      await disposeApp(tester);
    },
  );

  for (final fromDetail in [true, false]) {
    testWidgets(
      'return from another page preserves selected channel; detail=$fromDetail',
      (tester) async {
        final f = HomeTestFixture();
        await tester.pumpWidget(await f.create());
        await tester.pumpAndSettle();
        final channel = f.directory.channels.first;
        await pickChannel(tester, channel.id);
        final home = tester.state(find.byType(FeedScreen));
        if (fromDetail) {
          await tester.tap(find.text('今天的校园'));
          await tester.pumpAndSettle();
          Navigator.of(tester.element(find.byType(PostDetailScreen))).pop();
        } else {
          await tester.tap(find.byKey(const ValueKey('feed-account')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('首页'));
        }
        await tester.pumpAndSettle();
        expectHome(tester, f, channelId: channel.id, title: channel.name);
        expect(identical(home, tester.state(find.byType(FeedScreen))), isTrue);
        await disposeApp(tester);
      },
    );
  }

  testWidgets(
    'new app run starts recommended after the prior run selected a channel',
    (tester) async {
      final first = HomeTestFixture();
      await tester.pumpWidget(await first.create());
      await tester.pumpAndSettle();
      await pickChannel(tester, first.directory.channels.first.id);
      await disposeApp(tester);
      final next = HomeTestFixture();
      await tester.pumpWidget(await next.create());
      await tester.pumpAndSettle();
      expectHome(tester, next);
      await disposeApp(tester);
    },
  );

  testWidgets('same-token deadline renewal preserves channel and home state', (
    tester,
  ) async {
    final f = HomeTestFixture();
    await tester.pumpWidget(await f.create());
    await tester.pumpAndSettle();
    final channel = f.directory.channels.first.id;
    await pickChannel(tester, channel);
    final home = tester.state(find.byType(FeedScreen));
    await f.sessions.persistSessionMetadata(
      identityTestToken,
      identityTestRenewed,
      () => true,
    );
    await tester.pumpAndSettle();
    expect(f.posts.timelineChannelId, channel);
    expect(identical(home, tester.state(find.byType(FeedScreen))), isTrue);
    await disposeApp(tester);
  });

  testWidgets('post loading failure keeps recommended home and allows retry', (
    tester,
  ) async {
    final f = HomeTestFixture();
    f.postApi.timelineFailure = const PostFailure(
      kind: PostFailureKind.transport,
    );
    await tester.pumpWidget(await f.create());
    await tester.pumpAndSettle();
    expectHome(tester, f);
    expect(find.text('重新加载'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expectHome(tester, f);
    expect(find.text('今天的校园'), findsOneWidget);
    await disposeApp(tester);
  });
}
