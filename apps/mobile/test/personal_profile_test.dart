import 'dart:async';

import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';

import 'identity_test_support.dart';

import 'dart:io';

import 'package:hnuhole_mobile/src/posts/x_feed.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'login_home_test_support.dart';
import 'feed_ui_test.dart' as feed;

import 'package:hnuhole_mobile/hnuhole_mobile.dart';

void main() {
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
        expect(tester.widget<Text>(find.text(':)')).style!.color, palette.ink);
        final body = find.text('主题一致的帖子');
        expect(Theme.of(tester.element(body)).brightness, brightness);
        expect(
          HhTelegramPalette.of(tester.element(body)).surface,
          palette.surface,
        );
        final mood = find.byKey(const ValueKey('personal-mood'));
        final moodSurface = find
            .ancestor(of: mood, matching: find.byType(Material))
            .first;
        expect(tester.widget<Material>(moodSurface).color, palette.surface);
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
        await tester.tap(mood);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
          palette.surface,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('mood-input')))
              .style!
              .color,
          palette.ink,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        f.postApi.identityItems[identityTestId] = [];
        await f.posts.loadPersonal();
        await tester.pumpAndSettle();
        final emptyAction = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '选择通道发帖',
          ),
        );
        expect((emptyAction.icon as Icon).color, palette.ink);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'five labels animate on narrow screen; identities isolate posts and mood but share collections',
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
      await tester.tap(find.byKey(const ValueKey('personal-mood')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mood-input')),
        '第二身份心情',
      );
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      f.postApi.identityWaits.clear();
      await f.posts.selectPersonalIdentity(identityTestId);
      await tester.pumpAndSettle();
      expect(find.text('第二身份心情'), findsNothing);
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
  testWidgets(
    'mood completion, emoji limit, cancellation and expiry on return',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in {
        'Roboto': 'assets/fonts/Roboto-Regular.ttf',
        'HhNotoSansSC': 'assets/fonts/NotoSansSC-Variable.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(
          entry.key,
        )..addFont(rootBundle.load(entry.value))).load();
      }
      final f = HomeTestFixture();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: await f.create()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-account')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('帖子排序'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('personal-mood')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('mood-input'));
      await tester.enterText(input, '一二三四五六七八九十好👨‍👩‍👧‍👦多');
      expect(
        tester.widget<TextField>(input).controller!.text.characters.length,
        12,
      );
      await tester.enterText(input, '今天也要开心');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('今天也要开心'), findsOneWidget);
      final state = await f.posts.readPersonalProfileState();
      final stored =
          (state['identityMoods'] as Map)[f.posts.personalIdentity!.id] as Map;
      expect(stored['mood'], '今天也要开心');
      expect(
        DateTime.parse(stored['moodExpiresAt'] as String)
            .difference(DateTime.now())
            .inHours,
        23,
      );
      if (Platform.environment['PROFILE_CAPTURE'] case final output?) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byKey(const ValueKey('personal-mood')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '取消的内容');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('今天也要开心'), findsOneWidget);
      await f.posts.savePersonalProfileState({
        'mood': '已过期',
        'moodExpiresAt': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      });
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, 350),
      );
      await tester.pumpAndSettle();
      expect(find.text('已过期'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
