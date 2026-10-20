import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/post_interactions_api.dart';

import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';

PostInteractions summary({
  bool liked = false,
  bool favorite = false,
  int comments = 8,
}) => PostInteractions(
  postId: feed.postId,
  likeCount: liked ? 13 : 12,
  favoriteCount: favorite ? 4 : 3,
  commentCount: comments,
  likedByMe: liked,
  favoritedByMe: favorite,
);

class InteractionTestApi extends feed.FeedTestApi
    implements PostInteractionsApi {
  PostInteractions actual = summary();
  final changes = <String>[];
  int reads = 0;
  PostFailure? failure;
  bool mutationCommitLost = false,
      summaryReadFails = false,
      missingBatch = false;
  Completer<PostResponse<List<PostInteractions>>>? batchWait;
  Completer<PostResponse<PostInteractions>>? mutationWait, readWait;
  @override
  Future<PostResponse<List<PostInteractions>>> interactions({
    required String sessionToken,
    required List<String> postIds,
  }) async {
    reads++;
    if (missingBatch) {
      missingBatch = false;
      items = [];
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        code: 'POST_NOT_FOUND',
        statusCode: 404,
      );
    }
    if (summaryReadFails) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return batchWait?.future ?? feed.reply([actual]);
  }

  @override
  Future<PostResponse<PostInteractions>> postInteractions({
    required String sessionToken,
    required String postId,
  }) async {
    reads++;
    if (summaryReadFails) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return readWait?.future ?? feed.reply(actual);
  }

  Future<PostResponse<PostInteractions>> write(
    String token,
    bool desired,
    bool like,
  ) async {
    changes.add('${like ? 'like' : 'favorite'}:$desired:$token');
    if (mutationWait != null) return mutationWait!.future;
    if (failure == null || mutationCommitLost) {
      actual = summary(
        liked: like ? desired : actual.likedByMe,
        favorite: like ? actual.favoritedByMe : desired,
      );
    }
    if (failure case final error?) throw error;
    return feed.reply(actual);
  }

  @override
  Future<PostResponse<PostInteractions>> setPostLike({
    required String sessionToken,
    required String postId,
    required bool liked,
  }) => write(sessionToken, liked, true);
  @override
  Future<PostResponse<PostInteractions>> setPostFavorite({
    required String sessionToken,
    required String postId,
    required bool favorited,
  }) => write(sessionToken, favorited, false);
}

Future<feed.FeedFixture> fixture() async =>
    feed.FeedFixture(await IdentityTestFixture.create(), InteractionTestApi());
InteractionTestApi api(feed.FeedFixture f) => f.api as InteractionTestApi;
PostInteractionState state(feed.FeedFixture f) =>
    f.controller.interaction(feed.postId);

class _RenewingApi extends IdentityTestSessionApi {
  @override
  Future<DateTime> renewSession(String token) async => identityTestRenewed;
}

Future<IdentityTestFixture> renewingAuth() async {
  final vault = IdentityTestVault();
  final store = AuthStore(vault);
  await store.update(
    (s) => s.copyWith(
      session: SessionRecord(
        token: identityTestToken,
        accountId: identityTestAccount,
        expiresAt: identityTestExpiry,
      ),
    ),
  );
  final sessionApi = _RenewingApi();
  final directory = ChannelDirectoryController(
    repository: IdentityTestChannels(),
  );
  final sessions = AuthSessionController(
    api: sessionApi,
    store: store,
    directory: directory,
  );
  await sessions.start();
  final identityApi = IdentityTestApi();
  final management = IdentityManagementController(
    api: identityApi,
    store: store,
    sessions: sessions,
  );
  return IdentityTestFixture(
    vault,
    store,
    sessionApi,
    sessions,
    directory,
    identityApi,
    management,
  );
}

void main() {
  test(
    'same-token activity renewal preserves pending write and authority window',
    () async {
      final auth = await renewingAuth();
      final f = feed.FeedFixture(auth, InteractionTestApi());
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      final wait = Completer<PostResponse<PostInteractions>>();
      api(f).mutationWait = wait;
      final write = f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      await Future<void>.delayed(Duration.zero);
      final epoch = f.controller.authorityVersion;
      await auth.store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            token: identityTestToken,
            accountId: identityTestAccount,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
          ),
        ),
      );
      await auth.sessions.onActivity();
      expect(f.controller.authorityVersion, epoch);
      expect(state(f).unresolved, true);
      expect(state(f).sending, true);
      wait.complete(feed.reply(summary(liked: true)));
      await write;
      expect(state(f).value!.likedByMe, true);
    },
  );
  test('comment refresh during pending write is replayed after old complete snapshot', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final wait = Completer<PostResponse<PostInteractions>>();
    api(f).mutationWait = wait;
    final write = f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    await Future<void>.delayed(Duration.zero);
    api(f).actual = summary(liked: true, comments: 9);
    await f.controller.loadInteractions([feed.postId], single: true);
    wait.complete(feed.reply(summary(liked: true, comments: 8)));
    await write;
    expect(state(f).value!.commentCount, 9);
  });
  test(
    'batch follows page, empty page skips batch, no view registration',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      expect(state(f).value!.commentCount, 8);
      expect(api(f).reads, 1);
      expect(f.auth.store.current!.session!.expiresAt, identityTestRenewed);
      f.api.items = [];
      await f.controller.loadTimeline();
      expect(api(f).reads, 1);
      expect(f.api.calls.where((c) => c.startsWith('view:')), isEmpty);
    },
  );
  test('rapid taps lock synchronously across both operations; response replaces count', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final wait = Completer<PostResponse<PostInteractions>>();
    api(f).mutationWait = wait;
    final first = f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    for (var i = 0; i < 20; i++) {
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.favorite,
      );
    }
    expect(state(f).liked, true);
    expect(state(f).likes, 13);
    expect(api(f).changes.length, 1);
    wait.complete(feed.reply(summary(liked: true)));
    await first;
    expect(state(f).likes, 13);
    expect(state(f).canChange, true);
  });
  test('older batch cannot overwrite successful mutation', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final wait = Completer<PostResponse<List<PostInteractions>>>();
    api(f).batchWait = wait;
    final read = f.controller.loadInteractions([feed.postId]);
    await Future<void>.delayed(Duration.zero);
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    wait.complete(feed.reply([summary()]));
    await read;
    expect(state(f).value!.likedByMe, true);
  });
  test(
    'out-of-order detail reads and refreshed pages use latest ticket',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      final wait = Completer<PostResponse<PostInteractions>>();
      api(f).readWait = wait;
      final read = f.controller.loadInteractions([feed.postId], single: true);
      await Future<void>.delayed(Duration.zero);
      api(f).actual = summary(comments: 3);
      await f.controller.loadTimeline();
      wait.complete(feed.reply(summary(comments: 999)));
      await read;
      expect(state(f).value!.commentCount, 3);
    },
  );
  test(
    'timeout with committed result reconciles without double increment',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      api(f).failure = const PostFailure(
        kind: PostFailureKind.transport,
        code: 'TIMEOUT',
      );
      api(f).mutationCommitLost = true;
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.favorite,
      );
      expect(state(f).value!.favoritedByMe, true);
      expect(state(f).value!.favoriteCount, 4);
      expect(state(f).error, isNull);
    },
  );
  test('timeout read of old value keeps reversal locked; retry repeats same desired PUT', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    api(f).failure = const PostFailure(
      kind: PostFailureKind.transport,
      code: 'TIMEOUT',
    );
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    expect(state(f).unresolved, true);
    expect(state(f).sending, false);
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    expect(api(f).changes.length, 1);
    await f.controller.loadTimeline();
    expect(state(f).unresolved, true);
    api(f).failure = null;
    await f.controller.retryInteraction(feed.postId);
    expect(api(f).changes.map((c) => c.split(':').take(2).join(':')), [
      'like:true',
      'like:true',
    ]);
    expect(state(f).value!.likedByMe, true);
    expect(state(f).unresolved, false);
  });
  test('definite rejection rolls back, manual new attempt succeeds', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    api(f).failure = const PostFailure(
      kind: PostFailureKind.rejected,
      statusCode: 429,
    );
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    expect(state(f).liked, false);
    expect(state(f).likes, 12);
    expect(state(f).error, isNotNull);
    api(f).failure = null;
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    expect(state(f).liked, true);
    expect(state(f).error, isNull);
  });
  test(
    'failed summaries remain unknown; atomic 404 refreshes feed once',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      api(f).summaryReadFails = true;
      await f.controller.loadTimeline();
      expect(state(f).likes, isNull);
      expect(state(f).canChange, false);
      expect(state(f).error, isNotNull);
      api(f).summaryReadFails = false;
      api(f).missingBatch = true;
      await f.controller.loadTimeline();
      expect(f.controller.timelineItems, isEmpty);
      expect(api(f).reads, 2);
    },
  );
  test(
    'switch account discards late mutation and errors; new account never waits',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      final wait = Completer<PostResponse<PostInteractions>>();
      api(f).mutationWait = wait;
      final write = f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      await Future<void>.delayed(Duration.zero);
      f.auth.sessionApi.account = feed.otherChannelId;
      await f.auth.sessions.acceptSession(
        AuthSession(
          accountId: feed.otherChannelId,
          sessionToken: identityTestOtherToken,
          expiresAt: identityTestExpiry,
        ),
      );
      api(f).mutationWait = null;
      await f.controller.loadTimeline();
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.favorite,
      );
      wait.complete(feed.reply(summary(liked: true)));
      await write;
      expect(state(f).value!.likedByMe, false);
      expect(state(f).value!.favoritedByMe, true);
      expect(api(f).changes.last, endsWith(identityTestOtherToken));
    },
  );
  test(
    '401 clears state; 503 retains session and unresolved recovery',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      api(f).failure = const PostFailure(
        kind: PostFailureKind.unavailable,
        statusCode: 503,
      );
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      expect(f.auth.store.current!.session, isNotNull);
      expect(f.controller.available, false);
      await f.auth.sessions.retry();
      await f.controller.loadTimeline();
      api(f).failure = const PostFailure(
        kind: PostFailureKind.unauthorized,
        statusCode: 401,
        code: 'session_replaced',
      );
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      expect(f.controller.available, false);
      expect(state(f).value, isNull);
    },
  );
  testWidgets(
    'list and detail share liked/favorite state without navigating on action',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('like:${feed.postId}')));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(state(f).value!.likedByMe, true);
      await tester.tap(find.byKey(const ValueKey('comment:${feed.postId}')));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-favorite:${feed.postId}')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(PostDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(
        find.byKey(const ValueKey('detail-favorite:${feed.postId}')),
      );
      await tester.pumpAndSettle();
      expect(state(f).value!.favoritedByMe, true);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state(f).favorited, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('render production interaction states', (tester) async {
    tester.view.physicalSize = const Size(402, 806);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in {
      'Roboto': [
        'HNUHOLE_UI_RENDER_LATIN_FONT',
        'HNUHOLE_UI_RENDER_LATIN_MEDIUM_FONT',
        'HNUHOLE_UI_RENDER_LATIN_BOLD_FONT',
      ],
      'Noto Sans CJK SC': ['HNUHOLE_UI_RENDER_FONT'],
      'MaterialIcons': ['HNUHOLE_UI_RENDER_ICON_FONT'],
    }.entries) {
      final loader = FontLoader(entry.key);
      var hasFont = false;
      for (final variable in entry.value) {
        if (Platform.environment[variable] case final path?) {
          loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
          hasFont = true;
        }
      }
      if (hasFont) await tester.runAsync(loader.load);
    }
    final out = Directory(
      Platform.environment['HNUHOLE_INTERACTIONS_RENDER_DIR'] ??
          'build/feed-interactions-render',
    );
    await tester.runAsync(() => out.create(recursive: true));
    final f = await fixture();
    addTearDown(f.dispose);
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 180));
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final bitmap = await render.toImage(pixelRatio: 2);
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        await File('${out.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    Widget mount(Brightness brightness, {double scale = 1}) => RepaintBoundary(
      key: boundary,
      child: feed.screen(f, brightness: brightness, scale: scale),
    );
    await tester.pumpWidget(mount(Brightness.light));
    await tester.pumpAndSettle();
    await capture('interactions-light');
    await tester.tap(find.byKey(const ValueKey('like:${feed.postId}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bookmark:${feed.postId}')));
    await tester.pumpAndSettle();
    await capture('interactions-selected');
    api(f).failure = const PostFailure(
      kind: PostFailureKind.transport,
      code: 'TIMEOUT',
    );
    await tester.tap(find.byKey(const ValueKey('like:${feed.postId}')));
    await tester.pumpAndSettle();
    await capture('interactions-retry');
    api(f).failure = null;
    await tester.tap(
      find.byKey(const ValueKey('interaction-retry:${feed.postId}')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(mount(Brightness.dark));
    await tester.pumpAndSettle();
    await capture('interactions-dark');
    await tester.tap(find.byKey(const ValueKey('comment:${feed.postId}')));
    await tester.pumpAndSettle();
    await capture('interactions-detail');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(mount(Brightness.light, scale: 2));
    await tester.pumpAndSettle();
    await capture('interactions-large-text');
  });
}
