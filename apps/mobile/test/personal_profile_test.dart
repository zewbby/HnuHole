import 'dart:async';

import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/identity/identity_avatar.dart';

import 'identity_test_support.dart';

import 'package:hnuhole_mobile/src/posts/x_feed.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'login_home_test_support.dart';
import 'feed_ui_test.dart' as feed;

import 'package:hnuhole_mobile/hnuhole_mobile.dart';

void main() {
  testWidgets(
    'home avatar follows identity selection and same-identity updates',
    (tester) async {
      final f = HomeTestFixture();
      final root = await f.create();
      const second = '22222222-2222-4222-8222-222222222222';
      const firstAvatar = 'avatar-v1:33333333-3333-4333-8333-333333333333';
      const nextAvatar = 'avatar-v1:44444444-4444-4444-8444-444444444444';
      f.identitiesApi.items = [
        identityTestItem(name: '甲', avatar: firstAvatar),
        identityTestItem(id: second, name: '乙', original: false),
      ];
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();
      final account = find.byKey(const ValueKey('feed-account'));
      IdentityAvatar avatar() => tester.widget<IdentityAvatar>(
        find.descendant(of: account, matching: find.byType(IdentityAvatar)),
      );
      expect(avatar().avatar, firstAvatar);
      await tester.tap(account);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换身份'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-identity-$second')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('destination:home')));
      await tester.pumpAndSettle();
      expect(avatar().avatar, 'default-v1');
      expect(
        find.descendant(of: account, matching: find.text('乙')),
        findsOneWidget,
      );
      f.identitiesApi.items[1] = identityTestItem(
        id: second,
        name: '乙',
        avatar: nextAvatar,
        original: false,
      );
      await root.identities.load();
      await tester.pumpAndSettle();
      expect(avatar().avatar, nextAvatar);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'personal uses same global palette as home and inbox: $brightness',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final f = HomeTestFixture();
        final root = await f.create();
        final post = feed.post(title: '主题一致的帖子');
        f.postApi.identityItems[identityTestId] = [
          OwnPostCard(post: post, serverSortAt: post.publishedAt),
        ];
        await tester.pumpWidget(root);
        await tester.pumpAndSettle();
        final palette = HhTelegramPalette.of(
          tester.element(find.byType(HhXPostFeed)),
        );
        await tester.tap(find.byKey(const ValueKey('feed-account')));
        await tester.pumpAndSettle();
        final profile = find.byType(PersonalPostsScreen);
        final scaffold = find
            .descendant(of: profile, matching: find.byType(Scaffold))
            .first;
        expect(
          tester.widget<Scaffold>(scaffold).backgroundColor,
          palette.surface,
        );
        expect(
          tester.widget<Text>(find.text(':)')).style!.color,
          palette.action,
        );
        final body = find.text('主题一致的帖子');
        expect(Theme.of(tester.element(body)).brightness, brightness);
        expect(
          HhTelegramPalette.of(tester.element(body)).surface,
          palette.surface,
        );
        expect(find.byKey(const ValueKey('personal-mood')), findsNothing);
        await tester.tap(find.byTooltip('切换身份'));
        await tester.pumpAndSettle();
        expect(
          HhTelegramPalette.of(tester.element(find.text('切换身份'))).surface,
          palette.surface,
        );
        await tester.tap(
          find.byKey(const ValueKey('profile-identity-$identityTestId')),
        );
        await tester.pumpAndSettle();
        f.postApi.identityItems[identityTestId] = [];
        await f.posts.loadPersonal();
        await tester.pumpAndSettle();
        final emptyAction = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '选择通道发帖',
          ),
        );
        expect((emptyAction.icon as Icon).color, palette.action);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'five labels animate on narrow screen; identities isolate posts but share collections',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = HomeTestFixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      const second = '22222222-2222-4222-8222-222222222222';
      f.identitiesApi.items.add(
        identityTestItem(id: second, name: '身份二', original: false),
      );
      final firstPost = feed.post(title: '第一身份的帖子');
      final secondPost = feed.post(
        id: '33333333-3333-4333-8333-333333333334',
        title: '第二身份的帖子',
      );
      f.postApi.identityItems[identityTestId] = [
        OwnPostCard(post: firstPost, serverSortAt: firstPost.publishedAt),
      ];
      f.postApi.identityItems[second] = [
        OwnPostCard(post: secondPost, serverSortAt: secondPost.publishedAt),
      ];
      f.postApi.items = [firstPost, secondPost];
      f.postApi.likedItems = [firstPost];
      f.postApi.favoriteItems = [secondPost];
      await tester.tap(find.byKey(const ValueKey('feed-account')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpAndSettle();
      for (final label in ['帖子', '回复', '转帖', '喜欢', '收藏']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text(':)'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      final chip = find.byKey(const ValueKey('personal-profile'));
      expect(
        find.descendant(
          of: chip,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('第一身份的帖子'), findsOneWidget);
      final small = tester.widget<Text>(find.text('喜欢')).style!.fontSize!;
      await tester.tap(find.text('喜欢'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final middle = tester.widget<Text>(find.text('喜欢')).style!.fontSize!;
      expect(middle, greaterThan(small));
      expect(middle, lessThan(14));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('喜欢')).style!.fontSize, 14);
      await tester.tap(find.byTooltip('切换身份'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-identity-$second')));
      await tester.pumpAndSettle();
      expect(find.text('身份二'), findsOneWidget);
      expect(find.text('第一身份的帖子'), findsOneWidget); // account-shared likes
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('第二身份的帖子'), findsOneWidget);
      await tester.tap(find.text('帖子'));
      await tester.pumpAndSettle();
      expect(find.text('第一身份的帖子'), findsNothing);
      expect(find.text('第二身份的帖子'), findsOneWidget);
      // Complete the older identity response after switching back: it cannot overwrite.
      final pending = Completer<PostResponse<PostsPage<OwnPostCard>>>();
      f.postApi.identityWaits[identityTestId] = pending;
      final old = f.posts.selectPersonalIdentity(identityTestId);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('第二身份的帖子'), findsNothing);
      await f.posts.selectPersonalIdentity(second);
      pending.complete(
        feed.reply(
          PostsPage(
            items: f.postApi.identityItems[identityTestId]!,
            nextCursor: null,
          ),
        ),
      );
      await old;
      await tester.pumpAndSettle();
      expect(find.text('第二身份的帖子'), findsOneWidget);
      expect(find.text('第一身份的帖子'), findsNothing);
      f.postApi.identityWaits.clear();
      await f.posts.selectPersonalIdentity(identityTestId);
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('第二身份的帖子'), findsOneWidget); // account-shared favorites
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'profile scrolls away while tabs pin and posts remain a single column',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = HomeTestFixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      final posts = List.generate(
        16,
        (i) => feed.post(
          id: '33333333-3333-4333-8333-${i.toString().padLeft(12, '0')}',
        ),
      );
      f.postApi.items = posts;
      f.postApi.ownItems = posts
          .map((p) => OwnPostCard(post: p, serverSortAt: p.publishedAt))
          .toList();
      await tester.tap(find.byKey(const ValueKey('feed-account')));
      await tester.pumpAndSettle();
      expect(find.byType(HhXPostItem), findsWidgets);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -550),
      );
      await tester.pumpAndSettle();
      final tabsY = tester.getTopLeft(find.byTooltip('帖子排序')).dy;
      expect(tabsY, lessThan(12));
      expect(find.byKey(const ValueKey('personal-profile')), findsNothing);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byTooltip('帖子排序')).dy, tabsY);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
