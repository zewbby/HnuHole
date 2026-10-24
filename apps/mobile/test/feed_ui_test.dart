import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/feed_api.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';

import 'identity_test_support.dart';

const channelId = '11111111-1111-4111-8111-111111111111';
const otherChannelId = '22222222-2222-4222-8222-222222222222';
const postId = '33333333-3333-4333-8333-333333333333';
final at = DateTime.utc(2026, 10, 19);
const author = PostAuthor(
  state: PostAuthorState.active,
  avatar: 'default-v1',
  nickname: '林间来信',
);
FeedPost post({
  String id = postId,
  String channel = channelId,
  int images = 0,
  int views = 1260,
}) => FeedPost(
  postId: id,
  channelId: channel,
  title: '今天的校园',
  body: '傍晚的风刚刚好，分享一段平常的校园时光。',
  author: author,
  publishedAt: at,
  viewCount: views,
  imageCount: images,
);
PostResponse<T> reply<T>(T value) => PostResponse(
  value: value,
  serverTime: at,
  sessionExpiresAt: identityTestRenewed,
  requestId: AuthCrypto.encode(List.filled(16, 9)),
  statusCode: 200,
);

class FeedTestApi implements PostApi, FeedApi {
  final calls = <String>[];
  final writes = <Set<String>>[];
  Set<String> blocked = {};
  List<FeedPost> items = [post()];
  String? cursor;
  int views = 1261;
  bool writeLost = false, commitLost = false, readFails = false;
  PostFailure? timelineFailure;
  Completer<PostResponse<PostsPage<FeedPost>>>? pageWait;
  Completer<PostResponse<FeedPreferences>>? writeWait;
  Completer<PostResponse<PostViews>>? viewWait;
  Completer<PostResponse<PostDetail>>? detailWait;
  @override
  Future<PostResponse<FeedPreferences>> feedPreferences({
    required String sessionToken,
  }) async {
    calls.add('preferences:$sessionToken');
    if (readFails) throw const PostFailure(kind: PostFailureKind.transport);
    return reply(FeedPreferences(blocked));
  }

  @override
  Future<PostResponse<FeedPreferences>> saveFeedPreferences({
    required String sessionToken,
    required Set<String> blockedChannelIds,
  }) async {
    writes.add(Set.of(blockedChannelIds));
    if (writeWait != null) return writeWait!.future;
    if (!writeLost || commitLost) blocked = Set.of(blockedChannelIds);
    if (writeLost) throw const PostFailure(kind: PostFailureKind.transport);
    return reply(FeedPreferences(blocked));
  }

  @override
  Future<PostResponse<PostsPage<FeedPost>>> timeline({
    required String sessionToken,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) async {
    calls.add('feed:${channelId ?? 'recommended'}:${cursor ?? 'first'}:$limit');
    if (pageWait != null) return pageWait!.future;
    final failure = timelineFailure;
    timelineFailure = null;
    if (failure != null) throw failure;
    return reply(
      PostsPage(
        items: items
            .where(
              (p) =>
                  !blocked.contains(p.channelId) &&
                  (channelId == null || p.channelId == channelId),
            )
            .toList(),
        nextCursor: this.cursor,
      ),
    );
  }

  @override
  Future<PostResponse<PostViews>> registerPostView({
    required String sessionToken,
    required String postId,
  }) async {
    calls.add('view:$postId');
    return viewWait?.future ?? reply(PostViews(postId, views));
  }

  @override
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  }) async {
    calls.add('detail:$postId');
    final p = items.firstWhere((p) => p.postId == postId);
    return detailWait?.future ??
        reply(
          PostDetail(
            postId: postId,
            channelId: p.channelId,
            title: p.title,
            body: p.body,
            author: p.author,
            publishedAt: p.publishedAt,
            imageCount: p.imageCount,
          ),
        );
  }

  @override
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  }) async =>
      reply(PostCapabilities(postId: postId, canDelete: false, canEdit: false));
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected post operation ${invocation.memberName}');
}

class FeedTestController extends PostController {
  FeedTestController(IdentityTestFixture auth, FeedTestApi api)
    : super(
        api: api,
        sessions: auth.sessions,
        authStore: auth.store,
        identities: auth.api,
        openStore: (_) async => throw const PostStorageFailure(),
        pollInterval: Duration.zero,
      );
  PostPublicationNotice? notice;
  @override
  PostPublicationNotice? get latestPublicationNotice =>
      available ? notice : null;
  void announce(String channel) {
    notice = PostPublicationNotice(
      sequence: (notice?.sequence ?? 0) + 1,
      postId: postId,
      channelId: channel,
    );
    notifyListeners();
  }
}

class FeedFixture {
  FeedFixture(this.auth, this.api) {
    controller = FeedTestController(auth, api);
  }
  final IdentityTestFixture auth;
  final FeedTestApi api;
  late final FeedTestController controller;
  static Future<FeedFixture> create() async =>
      FeedFixture(await IdentityTestFixture.create(), FeedTestApi());
  void dispose() {
    controller.dispose();
    auth.dispose();
  }
}

final channels = [
  for (var i = 0; i < 7; i++)
    Channel(
      id: i == 0
          ? channelId
          : i == 1
          ? otherChannelId
          : '00000000-0000-0000-0000-00000000000${i + 1}',
      code: ChannelDirectory.requiredCodes[i],
      name: ['吐槽', '避雷', '安利', '搭子', '情感', '互助', '科技'][i],
      initiallyVisible: i < 5,
      displayOrder: i + 1,
    ),
];

Widget screen(
  FeedFixture f, {
  PostImagesLoader? loader,
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: HhTelegramTheme.create(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: FeedScreen(
    controller: f.controller,
    channels: channels,
    composeChannel: channels.first,
    onManageIdentities: () async {},
    onAuthenticationRequired: () {},
    loadImages: loader,
  ),
);

void main() {
  testWidgets(
    'same-scope refresh retains posts, widget state and cursor through failure',
    (tester) async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      f.api.cursor = 'retained-page';
      await tester.pumpWidget(screen(f));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('post:$postId'));
      final element = tester.element(item);
      f.api.pageWait = Completer();
      final refresh = f.controller.loadTimeline();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(item, findsOneWidget);
      expect(identical(tester.element(item), element), isTrue);
      expect(f.controller.timelineCursor, 'retained-page');
      f.api.pageWait!.completeError(
        const PostFailure(kind: PostFailureKind.transport),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(item, findsOneWidget);
      expect(f.controller.timelineCursor, 'retained-page');
      f.api.pageWait = null;
      await f.controller.loadTimeline();
      await tester.pumpAndSettle();
      expect(f.controller.timelineError, isNull);
      expect(identical(tester.element(item), element), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'new block rules remove retained rows; channel switch hides prior rows',
    () async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      f.api.blocked = {channelId};
      f.api.pageWait = Completer();
      final refresh = f.controller.loadTimeline();
      await Future<void>.delayed(Duration.zero);
      expect(f.controller.timelineItems, isEmpty);
      f.api.pageWait!.complete(reply(PostsPage(items: [], nextCursor: null)));
      await refresh;
      f.api.pageWait = null;
      f.api.blocked = {};
      await f.controller.loadTimeline();
      expect(f.controller.timelineItems, isNotEmpty);
      f.api.pageWait = Completer();
      final change = f.controller.loadTimeline(channelId: otherChannelId);
      expect(f.controller.timelineItems, isEmpty);
      f.api.pageWait!.complete(reply(PostsPage(items: [], nextCursor: null)));
      await change;
    },
  );

  testWidgets(
    'compose semantics follow selected channel and recommended picker',
    (tester) async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(screen(f));
        await tester.pumpAndSettle();
        expect(find.byTooltip('选择通道写帖子'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('feed-compose')))
              .getSemanticsData()
              .tooltip,
          '选择通道写帖子',
        );
        await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('choose-channel:${channels.last.id}')),
          100,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('channel-options')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(
          find.byKey(ValueKey('choose-channel:${channels.last.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('发布到科技'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('feed-compose')))
              .getSemanticsData()
              .tooltip,
          '发布到科技',
        );
        expect(find.byTooltip('发布到吐槽'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('feed-compose')));
        await tester.pumpAndSettle();
        expect(find.text('写帖子'), findsOneWidget);
        expect(find.text('科技'), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  test(
    'preferences precede feed, renewal persists, list does not count views',
    () async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      expect(f.api.calls.first, startsWith('preferences:'));
      expect(f.api.calls[1], 'feed:recommended:first:20');
      expect(f.controller.postViewCount(postId), 1260);
      expect(f.auth.store.current!.session!.expiresAt, identityTestRenewed);
      expect(f.api.calls.where((s) => s.startsWith('view:')), isEmpty);
    },
  );
  test('late old channel response cannot overwrite newer selection', () async {
    final f = await FeedFixture.create();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final pending = Completer<PostResponse<PostsPage<FeedPost>>>();
    f.api.pageWait = pending;
    final old = f.controller.loadTimeline(channelId: channelId);
    await Future<void>.delayed(Duration.zero);
    f.api.pageWait = null;
    await f.controller.loadTimeline(channelId: otherChannelId);
    pending.complete(reply(PostsPage(items: [post()], nextCursor: 'old')));
    await old;
    expect(f.controller.timelineChannelId, otherChannelId);
    expect(f.controller.timelineItems, isEmpty);
    expect(f.controller.timelineCursor, isNull);
  });
  test(
    'opaque pagination is reused, cursor invalid restarts first page',
    () async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      f.api.cursor = 'opaque';
      await f.controller.loadTimeline();
      f.api.timelineFailure = const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 400,
        code: 'CURSOR_INVALID',
      );
      f.api.cursor = null;
      await f.controller.loadTimeline(more: true);
      expect(
        f.api.calls,
        containsAllInOrder([
          'feed:recommended:opaque:20',
          'feed:recommended:first:20',
        ]),
      );
      expect(f.controller.timelineItems.length, 1);
      expect(f.controller.timelineError, isNull);
    },
  );
  test('complete writes serialize; blocked channel stays selectable; reset persists', () async {
    final f = await FeedFixture.create();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final wait = Completer<PostResponse<FeedPreferences>>();
    f.api.writeWait = wait;
    final first = f.controller.saveBlockedChannels({channelId});
    final second = f.controller.saveBlockedChannels({
      channelId,
      otherChannelId,
    });
    await Future<void>.delayed(Duration.zero);
    expect(f.api.writes.length, 1);
    f.api.writeWait = null;
    f.api.blocked = {channelId};
    wait.complete(reply(FeedPreferences({channelId})));
    await Future.wait([first, second]);
    expect(f.api.writes.length, 2);
    await f.controller.loadTimeline(channelId: channelId);
    expect(f.controller.timelineItems, isEmpty);
    expect(f.controller.blockedChannelIds, contains(channelId));
    await f.controller.saveBlockedChannels({});
    expect(f.controller.timelineItems.length, 1);
    expect(f.controller.blockedChannelIds, isEmpty);
  });
  test(
    'unknown write reconciles server truth without assuming success',
    () async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      f.api.writeLost = true;
      await f.controller.saveBlockedChannels({channelId});
      expect(f.controller.blockedChannelIds, isEmpty);
      expect(f.controller.preferencesError, isNotNull);
      f.api.commitLost = true;
      await f.controller.saveBlockedChannels({channelId});
      expect(f.controller.blockedChannelIds, {channelId});
      expect(f.controller.preferencesError, isNull);
      f.api.readFails = true;
      await f.controller.saveBlockedChannels({});
      expect(f.controller.timelineError, isNotNull);
      expect(f.controller.timelineItems, isEmpty);
    },
  );
  test('logout discards delayed preferences, pages and counts', () async {
    final f = await FeedFixture.create();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final count = Completer<PostResponse<PostViews>>();
    f.api.viewWait = count;
    final view = f.controller.registerVisiblePost(postId);
    final wait = Completer<PostResponse<FeedPreferences>>();
    f.api.writeWait = wait;
    final save = f.controller.saveBlockedChannels({channelId});
    await Future<void>.delayed(Duration.zero);
    await f.auth.sessions.logout();
    wait.complete(reply(FeedPreferences({channelId})));
    count.complete(reply(const PostViews(postId, 9000)));
    await Future.wait([save, view]);
    expect(f.controller.blockedChannelIds, isEmpty);
    expect(f.controller.timelineItems, isEmpty);
    expect(f.controller.postViewCount(postId), isNull);
  });
  test(
    '503 preserves session; session_replaced clears all feed state',
    () async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      f.api.timelineFailure = const PostFailure(
        kind: PostFailureKind.unavailable,
        statusCode: 503,
      );
      await f.controller.loadTimeline();
      expect(f.auth.store.current!.session, isNotNull);
      f.api.timelineFailure = const PostFailure(
        kind: PostFailureKind.unauthorized,
        statusCode: 401,
        code: 'session_replaced',
      );
      await f.controller.loadTimeline();
      expect(f.controller.available, false);
      expect(f.controller.timelineItems, isEmpty);
    },
  );
  test('account switch discards old page and queued writes before loading new account', () async {
    final f = await FeedFixture.create();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final pending = Completer<PostResponse<PostsPage<FeedPost>>>();
    f.api.pageWait = pending;
    final old = f.controller.loadTimeline();
    await Future<void>.delayed(Duration.zero);
    f.auth.sessionApi.account = otherChannelId;
    await f.auth.sessions.acceptSession(
      AuthSession(
        accountId: otherChannelId,
        sessionToken: identityTestOtherToken,
        expiresAt: identityTestExpiry,
      ),
    );
    f.api.pageWait = null;
    f.api.items = [post(channel: otherChannelId, views: 4)];
    await f.controller.loadTimeline();
    pending.complete(
      reply(PostsPage(items: [post(views: 9999)], nextCursor: 'old')),
    );
    await old;
    expect(f.controller.accountId, otherChannelId);
    expect(f.controller.timelineItems.single.channelId, otherChannelId);
    expect(f.controller.postViewCount(postId), 4);
    expect(f.controller.timelineCursor, isNull);
  });
  test(
    'first page refresh synchronizes preferences changed by another device',
    () async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      f.api.blocked = {channelId};
      await f.controller.loadTimeline();
      expect(f.controller.blockedChannelIds, {channelId});
      expect(f.controller.timelineItems, isEmpty);
    },
  );
  testWidgets(
    'unknown preference read disables toggles until explicit reconciliation',
    (tester) async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      f.api.readFails = true;
      await tester.pumpWidget(screen(f));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-block-filter')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('block-channel:$channelId')),
            )
            .onChanged,
        isNull,
      );
      f.api.readFails = false;
      await tester.tap(find.text('重新核对设置'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('block-channel:$channelId')),
            )
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets('production entry, plain channel picker, saved block and reset', (
    tester,
  ) async {
    final f = await FeedFixture.create();
    addTearDown(f.dispose);
    await tester.pumpWidget(screen(f));
    await tester.pumpAndSettle();
    expect(find.text('推荐'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byKey(const ValueKey('choose-channel:$channelId')));
    await tester.pumpAndSettle();
    expect(f.controller.timelineChannelId, channelId);
    await tester.tap(find.byKey(const ValueKey('feed-block-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-channel:$channelId')));
    await tester.pumpAndSettle();
    expect(f.api.blocked, {channelId});
    expect(find.text('已屏蔽 1 个通道'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reset-blocks')));
    await tester.pumpAndSettle();
    expect(f.api.blocked, isEmpty);
    // Other-channel publication facts are consumed once without a stale toast.
    f.controller.announce(otherChannelId);
    await tester.pumpAndSettle();
    expect(find.text('发布成功！'), findsNothing);
    await f.controller.loadTimeline(channelId: otherChannelId);
    await tester.pumpAndSettle();
    expect(find.text('发布成功！'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('channel sheet hides old authorized directory on logout', (
    tester,
  ) async {
    final f = await FeedFixture.create();
    addTearDown(f.dispose);
    await tester.pumpWidget(screen(f));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
    await tester.pumpAndSettle();
    expect(find.text('切换通道'), findsOneWidget);
    await f.auth.sessions.logout();
    await tester.pumpAndSettle();
    expect(find.text('切换通道'), findsNothing);
    expect(
      find.byKey(const ValueKey('choose-channel:$channelId')),
      findsNothing,
    );
    expect(find.text('请重新登录'), findsWidgets);
  });

  testWidgets(
    'detail read retry removes stale transport error after content recovers',
    (tester) async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(screen(f));
      await tester.pumpAndSettle();
      f.api.detailWait = Completer<PostResponse<PostDetail>>();
      await tester.tap(find.text('今天的校园'));
      await tester.pump();
      f.api.detailWait!.completeError(
        const PostFailure(kind: PostFailureKind.transport),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新核对'), findsOneWidget);
      f.api.detailWait = null;
      await tester.tap(find.text('重新核对'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('原操作已保留'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'only rendered detail body counts once; rebuild and exposure do not',
    (tester) async {
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(screen(f));
      await tester.pumpAndSettle();
      expect(f.api.calls.where((s) => s.startsWith('view:')), isEmpty);
      await tester.tap(find.text('今天的校园'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(f.api.calls.where((s) => s.startsWith('view:')).length, 1);
      await tester.pump();
      expect(f.controller.postViewCount(postId), 1261);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(f.api.calls.where((s) => s.startsWith('view:')).length, 1);
    },
  );
  testWidgets(
    'large type picker and block sheet reach last channel without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await FeedFixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(screen(f, scale: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-block-filter')));
      await tester.pumpAndSettle();
      final key = ValueKey('block-channel:${channels.last.id}');
      await tester.scrollUntilVisible(
        find.byKey(key),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('block-options')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(f.api.blocked, contains(channels.last.id));
      expect(tester.takeException(), isNull);
    },
  );
}
