import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/post_interactions_api.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';

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
  int generation = 0;
  String get version => '"${generation.toRadixString(16).padLeft(64, '0')}"';
  final conditions = <String>[];
  Completer<void>? beforeCas;
  PostResponse<PostInteractions> versionReply(
    PostInteractions value, [
    String? tag,
  ]) => PostResponse(
    value: value,
    serverTime: feed.at,
    sessionExpiresAt: identityTestRenewed,
    requestId: AuthCrypto.encode(List.filled(16, 9)),
    statusCode: 200,
    interactionVersion: tag ?? version,
  );
  PostFailure? failure;
  bool mutationCommitLost = false,
      summaryReadFails = false,
      missingBatch = false;
  Completer<PostResponse<List<PostInteractions>>>? batchWait;
  Completer<PostResponse<PostInteractions>>? mutationWait, readWait;
  bool failNextRead = false;
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
    if (failNextRead) {
      failNextRead = false;
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    if (summaryReadFails) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    final tag = version;
    return readWait == null
        ? versionReply(actual)
        : versionReply((await readWait!.future).value, tag);
  }

  Future<PostResponse<PostInteractions>> write(
    String token,
    bool desired,
    bool like,
    String expected,
  ) async {
    changes.add('${like ? 'like' : 'favorite'}:$desired:$token');
    conditions.add(expected);
    final gate = beforeCas;
    if (gate != null) await gate.future;
    if (expected != version) {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 412,
        code: 'INTERACTION_VERSION_CONFLICT',
      );
    }
    if (mutationWait != null) {
      final result = await mutationWait!.future;
      generation++;
      return versionReply(result.value);
    }
    if (failure == null || mutationCommitLost) {
      actual = summary(
        liked: like ? desired : actual.likedByMe,
        favorite: like ? actual.favoritedByMe : desired,
      );
      generation++;
    }
    if (failure case final error?) throw error;
    return versionReply(actual);
  }

  @override
  Future<PostResponse<PostInteractions>> setPostLike({
    required String sessionToken,
    required String postId,
    required bool liked,
    required String version,
  }) => write(sessionToken, liked, true, version);
  @override
  Future<PostResponse<PostInteractions>> setPostFavorite({
    required String sessionToken,
    required String postId,
    required bool favorited,
    required String version,
  }) => write(sessionToken, favorited, false, version);
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
  for (final enabledAtDown in [true, false]) {
    testWidgets(
      'FA-D02 action changes enabled state during pointer gesture ($enabledAtDown)',
      (tester) async {
        final f = await fixture();
        addTearDown(f.dispose);
        await tester.pumpWidget(feed.screen(f));
        await tester.pumpAndSettle();
        final wait = Completer<PostResponse<PostInteractions>>();
        api(f).mutationWait = wait;
        Future<void>? write;
        if (!enabledAtDown) {
          write = f.controller.changeInteraction(
            feed.postId,
            PostInteractionAction.like,
          );
          await tester.pump();
        }
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('like:${feed.postId}'))),
        );
        await tester.pump();
        if (enabledAtDown) {
          write = f.controller.changeInteraction(
            feed.postId,
            PostInteractionAction.like,
          );
          await tester.pump();
        } else {
          api(f).actual = summary(liked: true);
          api(f).mutationWait = null;
          wait.complete(feed.reply(summary(liked: true)));
          await write;
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
        expect(find.byType(PostDetailScreen), findsNothing);
        expect(api(f).changes.length, enabledAtDown ? 1 : 2);
        if (enabledAtDown) {
          api(f).actual = summary(liked: true);
          api(f).mutationWait = null;
          wait.complete(feed.reply(summary(liked: true)));
          await write;
        }
        await tester.pumpAndSettle();
        expect(find.byType(PostDetailScreen), findsNothing);
        expect(api(f).changes.length, 2);
        expect(state(f).liked, false);
      },
    );
  }
  testWidgets(
    'pending actions stay responsive and disabled share never opens the post',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      final wait = Completer<PostResponse<PostInteractions>>();
      api(f).mutationWait = wait;
      await tester.tap(find.byKey(const ValueKey('like:${feed.postId}')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('like:${feed.postId}')),
            )
            .onPressed,
        isNotNull,
      );
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const ValueKey('like:${feed.postId}')));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(PostDetailScreen), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('bookmark:${feed.postId}')));
      await tester.tap(find.byKey(const ValueKey('share:${feed.postId}')));
      await tester.pump();
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(api(f).changes.length, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('like:${feed.postId}')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      api(f).actual = summary(liked: true);
      api(f).mutationWait = null;
      wait.complete(feed.reply(summary(liked: true)));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(state(f).value!.likedByMe, true);
      expect(state(f).value!.favoritedByMe, true);
    },
  );
  testWidgets(
    'old account feed action and both retry callbacks cannot issue B requests',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      final oldAction = tester
          .widget<HhXPostItem>(find.byType(HhXPostItem))
          .onAction;
      api(f).failure = const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 429,
      );
      oldAction(FeedAction.like);
      await tester.pumpAndSettle();
      api(f).summaryReadFails = true;
      await f.controller.loadInteractions([feed.postId], single: true);
      await tester.pumpAndSettle();
      final oldWriteRetry = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('interaction-retry:${feed.postId}')),
          )
          .onPressed!;
      final oldReadRetry = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('interaction-read-retry:${feed.postId}')),
          )
          .onPressed!;
      f.auth.sessionApi.account = feed.otherChannelId;
      await f.auth.sessions.acceptSession(
        AuthSession(
          accountId: feed.otherChannelId,
          sessionToken: identityTestOtherToken,
          expiresAt: identityTestExpiry,
        ),
      );
      api(f).summaryReadFails = false;
      api(f).failure = null;
      await f.controller.loadTimeline();
      final reads = api(f).reads, writes = api(f).changes.length;
      oldAction(FeedAction.like);
      oldAction(FeedAction.bookmark);
      oldWriteRetry();
      oldReadRetry();
      await tester.pumpAndSettle();
      expect(api(f).reads, reads);
      expect(api(f).changes.length, writes);
      expect(state(f).liked, false);
      expect(state(f).favorited, false);
    },
  );
  testWidgets('old account detail callbacks cannot issue B requests', (
    tester,
  ) async {
    final f = await fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(feed.screen(f));
    await tester.pumpAndSettle();
    await tester.tap(find.text(feed.post().title).first);
    await tester.pumpAndSettle();
    final oldLike = tester
        .widget<TextButton>(
          find.byKey(const ValueKey('detail-like:${feed.postId}')),
        )
        .onPressed!;
    final oldFavorite = tester
        .widget<TextButton>(
          find.byKey(const ValueKey('detail-favorite:${feed.postId}')),
        )
        .onPressed!;
    api(f).failure = const PostFailure(
      kind: PostFailureKind.rejected,
      statusCode: 429,
    );
    oldLike();
    await tester.pumpAndSettle();
    final oldRetry = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '重试'))
        .onPressed!;
    f.auth.sessionApi.account = feed.otherChannelId;
    await f.auth.sessions.acceptSession(
      AuthSession(
        accountId: feed.otherChannelId,
        sessionToken: identityTestOtherToken,
        expiresAt: identityTestExpiry,
      ),
    );
    api(f).failure = null;
    await f.controller.loadTimeline();
    final reads = api(f).reads, writes = api(f).changes.length;
    oldLike();
    oldFavorite();
    oldRetry();
    await tester.pumpAndSettle();
    expect(api(f).reads, reads);
    expect(api(f).changes.length, writes);
  });
  test('preflight failure replays invalidated comment read instead of swallowing refresh', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    await f.controller.loadTimeline();
    final delayed = Completer<PostResponse<List<PostInteractions>>>();
    api(f).batchWait = delayed;
    final read = f.controller.loadInteractions([feed.postId]);
    await Future<void>.delayed(Duration.zero);
    api(f).actual = summary(comments: 9);
    api(f).failNextRead = true;
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    delayed.complete(feed.reply([summary(comments: 9)]));
    await read;
    expect(api(f).changes, isEmpty);
    expect(state(f).value!.commentCount, 9);
    expect(state(f).writeError, isNotNull);
    expect(state(f).readError, isNull);
  });
  test(
    'restart before old CAS resumes cannot resurrect a cancelled like',
    () async {
      final auth = await IdentityTestFixture.create();
      addTearDown(auth.dispose);
      final server = InteractionTestApi();
      final first = feed.FeedTestController(auth, server);
      await first.loadTimeline();
      final gate = Completer<void>();
      server.beforeCas = gate;
      final delayed = first.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.changes.length, 1);
      first.dispose();
      server.beforeCas = null;
      final reopened = feed.FeedTestController(auth, server);
      addTearDown(reopened.dispose);
      await reopened.loadTimeline();
      await reopened.changeInteraction(feed.postId, PostInteractionAction.like);
      await reopened.changeInteraction(feed.postId, PostInteractionAction.like);
      expect(server.actual.likedByMe, false);
      gate.complete();
      await delayed;
      expect(server.actual.likedByMe, false);
      expect(reopened.interaction(feed.postId).value!.likedByMe, false);
      expect(auth.sessions.isAuthenticated, true);
    },
  );
  testWidgets(
    'dirty read preserves failed write; read retry never resends failed mutation',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      api(f).failure = const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 429,
      );
      await tester.tap(find.byKey(const ValueKey('like:${feed.postId}')));
      await tester.pumpAndSettle();
      final failed = state(f).writeError;
      await f.controller.loadInteractions([feed.postId], single: true);
      expect(state(f).writeError, failed);
      api(f).summaryReadFails = true;
      await f.controller.loadInteractions([feed.postId], single: true);
      await tester.pumpAndSettle();
      expect(state(f).readError, isNotNull);
      final before = api(f).changes.length;
      api(f).summaryReadFails = false;
      await tester.tap(
        find.byKey(const ValueKey('interaction-read-retry:${feed.postId}')),
      );
      await tester.pumpAndSettle();
      expect(api(f).changes.length, before);
      expect(state(f).writeError, failed);
      expect(state(f).readError, isNull);
    },
  );
  test('dirty refresh after conflicting CAS keeps explicit write failure and retry intent', () async {
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
    await f.controller.loadInteractions([feed.postId], single: true);
    api(f).generation++;
    await f.controller.retryInteraction(feed.postId);
    expect(state(f).unresolved, false);
    expect(state(f).value!.likedByMe, false);
    expect(state(f).writeError, isNotNull);
    expect(state(f).retryAction, PostInteractionAction.like);
  });
  test('same boolean without rotated fence stays locked, including later explicit rejection', () async {
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
    api(f).actual = summary(liked: true);
    await f.controller.retryInteraction(feed.postId);
    expect(state(f).unresolved, true);
    api(f).failure = const PostFailure(
      kind: PostFailureKind.rejected,
      statusCode: 429,
    );
    await f.controller.retryInteraction(feed.postId);
    expect(state(f).unresolved, true);
    expect(api(f).conditions.toSet().length, 1);
  });
  test('rotated fence resolves conflict; explicit retry gets new condition and seals late old write', () async {
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
    final original = api(f).conditions.single;
    api(f).generation++;
    api(f).failure = null;
    await f.controller.retryInteraction(feed.postId);
    expect(state(f).unresolved, false);
    expect(state(f).liked, false);
    expect(state(f).error, isNotNull);
    await f.controller.retryInteraction(feed.postId);
    expect(state(f).liked, true);
    await f.controller.changeInteraction(
      feed.postId,
      PostInteractionAction.like,
    );
    expect(state(f).liked, false);
    await expectLater(
      api(f).setPostLike(
        sessionToken: identityTestToken,
        postId: feed.postId,
        liked: true,
        version: original,
      ),
      throwsA(isA<PostFailure>().having((e) => e.statusCode, 'status', 412)),
    );
    expect(api(f).actual.likedByMe, false);
  });
  testWidgets(
    '360dp normal text keeps all interactions on one row; large text wraps',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      final tops = [
        for (final key in ['comment', 'like', 'bookmark', 'share'])
          tester.getTopLeft(find.byKey(ValueKey('$key:${feed.postId}'))).dy,
      ];
      expect(tops.toSet().length, 1);
      final viewTop = tester
          .getTopLeft(find.byKey(const ValueKey('views:${feed.postId}')))
          .dy;
      expect(viewTop, tops.first);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(feed.screen(f, scale: 2));
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('bookmark:${feed.postId}')))
            .dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('like:${feed.postId}')))
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
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
  test('rapid taps coalesce synchronously across both operations; response replaces count', () async {
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
  testWidgets(
    'like and unlike update on next frame with serial final-intent writes and no spinner',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      final wait = Completer<PostResponse<PostInteractions>>();
      api(f).mutationWait = wait;
      final button = find.byKey(const ValueKey('like:${feed.postId}'));
      await tester.tap(button);
      await tester.pump();
      var item = tester.widget<HhXPostItem>(find.byType(HhXPostItem));
      expect(item.post.liked, true);
      expect(item.post.likes, 13);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      await tester.tap(button);
      await tester.pump();
      item = tester.widget<HhXPostItem>(find.byType(HhXPostItem));
      expect(item.post.liked, false);
      expect(item.post.likes, 12);
      expect(api(f).changes.length, 1);
      expect(find.byType(PostDetailScreen), findsNothing);
      api(f).actual = summary(liked: true);
      api(f).mutationWait = null;
      wait.complete(feed.reply(summary(liked: true)));
      await tester.pumpAndSettle();
      expect(
        api(f).changes.map((s) => s.split(':').take(2).join(':')).toList(),
        ['like:true', 'like:false'],
      );
      expect(state(f).liked, false);
      expect(state(f).likes, 12);
      expect(api(f).conditions[0], isNot(api(f).conditions[1]));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'queued unlike waits for unknown original CAS and retains its final intent',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      final gate = Completer<void>();
      api(f).beforeCas = gate;
      api(f).failure = const PostFailure(kind: PostFailureKind.transport);
      final first = f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      await Future<void>.delayed(Duration.zero);
      await f.controller.changeInteraction(
        feed.postId,
        PostInteractionAction.like,
      );
      expect(state(f).liked, false);
      gate.complete();
      await first;
      expect(state(f).uncertain, true);
      expect(state(f).canChange, false);
      expect(api(f).changes.length, 1);
      api(f).beforeCas = null;
      api(f).failure = null;
      await f.controller.retryInteraction(feed.postId);
      expect(api(f).conditions[0], api(f).conditions[1]);
      expect(api(f).conditions[2], isNot(api(f).conditions[1]));
      expect(
        api(f).changes.map((s) => s.split(':').take(2).join(':')).toList(),
        ['like:true', 'like:true', 'like:false'],
      );
      expect(state(f).liked, false);
      expect(api(f).actual.likedByMe, false);
      expect(state(f).writeError, isNull);
    },
  );

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
      await tester.tap(find.text(feed.post().title).first);
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
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
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
        'HhNotoSansSC': ['HNUHOLE_UI_RENDER_FONT'],
        'MaterialIcons': ['HNUHOLE_UI_RENDER_ICON_FONT'],
      }.entries) {
        await tester.runAsync(() async {
          final loader = FontLoader(entry.key);
          var hasFont = false;
          for (final variable in entry.value) {
            if (Platform.environment[variable] case final path?) {
              loader.addFont(
                File(path).readAsBytes().then(ByteData.sublistView),
              );
              hasFont = true;
            }
          }
          if (hasFont) await loader.load();
        });
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
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final bitmap = await render.toImage(pixelRatio: 2);
          final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          await File('${out.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
        expect(tester.takeException(), isNull);
      }

      Widget mount(Brightness brightness, {double scale = 1}) =>
          RepaintBoundary(
            key: boundary,
            child: feed.screen(f, brightness: brightness, scale: scale),
          );
      await tester.pumpWidget(mount(Brightness.light));
      await tester.pumpAndSettle();
      f.controller.errorMessage = null;
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
      await tester.tap(find.text(feed.post().title).first);
      await tester.pumpAndSettle();
      await capture('interactions-detail');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(mount(Brightness.light, scale: 2));
      await tester.pumpAndSettle();
      await capture('interactions-large-text');
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(mount(Brightness.light));
      await tester.pumpAndSettle();
      await capture('interactions-360dp');
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
}
