import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'feed_ui_test.dart' as feed;
import 'feed_interactions_test.dart' as interactions;
import 'identity_test_support.dart';

const identity = '11111111-1111-4111-8111-111111111111';
const second = '22222222-2222-4222-8222-222222222222';

class RepostApi extends interactions.InteractionTestApi
    implements PostRepostsApi {
  int repostGeneration = 0, repostWrites = 0;
  final repostConditions = <String>[];
  final repostReads = <String>[];
  final marks = <String, PostRepostMark>{};
  bool loseAfterCommit = false, failBeforeCommit = false;
  Completer<void>? repostWriteWait;
  Completer<PostResponse<PostRepostSnapshot>>? repostReadWait;
  Completer<PostResponse<PostsPage<RepostedPost>>>? listWait;
  String get repostVersion =>
      '"${repostGeneration.toRadixString(16).padLeft(64, '0')}"';
  PostRepostSnapshot snapshot() =>
      PostRepostSnapshot(feed.postId, List.unmodifiable(marks.values));
  PostResponse<T> response<T>(T value, {String? tag}) => PostResponse(
    value: value,
    serverTime: feed.at,
    sessionExpiresAt: identityTestRenewed,
    requestId: AuthCrypto.encode(List.filled(16, 9)),
    statusCode: 200,
    interactionVersion: tag ?? repostVersion,
  );
  @override
  Future<PostResponse<PostRepostSnapshot>> postReposts({
    required String sessionToken,
    required String postId,
  }) async {
    repostReads.add(postId);
    return repostReadWait?.future ??
        response(PostRepostSnapshot(postId, List.unmodifiable(marks.values)));
  }

  @override
  Future<PostResponse<PostRepostSnapshot>> setPostRepost({
    required String sessionToken,
    required String postId,
    required String identityId,
    required bool reposted,
    required String version,
  }) async {
    repostWrites++;
    repostConditions.add(version);
    if (repostWriteWait != null) await repostWriteWait!.future;
    if (failBeforeCommit) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    if (version != repostVersion) {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        code: 'INTERACTION_VERSION_CONFLICT',
        statusCode: 412,
      );
    }
    if (reposted) {
      marks.putIfAbsent(identityId, () => PostRepostMark(identityId, feed.at));
    } else {
      marks.remove(identityId);
    }
    repostGeneration++;
    if (loseAfterCommit) {
      loseAfterCommit = false;
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return response(snapshot());
  }

  @override
  Future<PostResponse<PostsPage<RepostedPost>>> ownReposts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) async =>
      listWait?.future ??
      response(
        PostsPage(
          items: [
            for (final mark in marks.values)
              RepostedPost(
                postId: feed.postId,
                identityId: mark.identityId,
                repostedAt: mark.repostedAt,
                post: null,
              ),
          ],
          nextCursor: null,
        ),
      );
}

Future<feed.FeedFixture> fixture() async =>
    feed.FeedFixture(await IdentityTestFixture.create(), RepostApi());
void main() {
  testWidgets(
    'selected mark confirms removal and stale confirmation cannot write',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      final api = f.api as RepostApi;
      f.auth.api.items = [identityTestItem(id: identity, name: '转帖身份')];
      api.marks[identity] = PostRepostMark(identity, feed.at);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostRepostButton(
              controller: f.controller,
              postId: feed.postId,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repost:${feed.postId}')));
      await tester.pumpAndSettle();
      expect(find.text('已转帖'), findsNothing);
      await tester.tap(find.text('转帖身份'));
      await tester.pumpAndSettle();
      expect(find.text('确认移除？'), findsOneWidget);
      expect(api.repostWrites, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.marks.containsKey(identity), isTrue);
      await tester.tap(find.text('转帖身份'));
      await tester.pumpAndSettle();
      final oldConfirm = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '确认'))
          .onPressed!;
      await f.auth.store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            token: AuthCrypto.encode(List.filled(32, 22)),
            accountId: second,
            expiresAt: identityTestExpiry,
          ),
        ),
      );
      await tester.pumpAndSettle();
      oldConfirm();
      await tester.pumpAndSettle();
      expect(api.repostWrites, 0);
      expect(api.marks.containsKey(identity), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reused entry reloads its new post and hides stale account state',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      final api = f.api as RepostApi;
      Widget button(String id) => MaterialApp(
        home: Scaffold(
          body: PostRepostButton(controller: f.controller, postId: id),
        ),
      );
      await tester.pumpWidget(button(feed.postId));
      await tester.pumpAndSettle();
      expect(api.repostReads, [feed.postId]);
      await tester.pumpWidget(button(second));
      await tester.pumpAndSettle();
      expect(api.repostReads, [feed.postId, second]);
      await f.auth.store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            token: AuthCrypto.encode(List.filled(32, 22)),
            accountId: second,
            expiresAt: identityTestExpiry,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsNothing);
      expect(api.repostWrites, 0);
    },
  );
  testWidgets(
    'explicit identity selection and shared detail state on narrow screen',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      f.auth.api.items = [
        ManagedIdentity(
          id: identity,
          nickname: '转帖身份',
          avatar: 'default-v1',
          isOriginal: true,
          createdAt: feed.at,
        ),
      ];
      await tester.pumpWidget(feed.screen(f));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repost:${feed.postId}')));
      await tester.pumpAndSettle();
      expect((f.api as RepostApi).repostWrites, 0);
      await tester.tap(find.text('转帖身份'));
      await tester.pumpAndSettle();
      expect((f.api as RepostApi).marks.containsKey(identity), isTrue);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天的校园'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(find.text('已转帖'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('repost:${feed.postId}')),
            )
            .color,
        const Color(0xFF229ED9),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'entering archive during unknown create exposes reconciliation not empty success',
    (tester) async {
      final f = await fixture();
      addTearDown(f.dispose);
      final a = f.api as RepostApi, c = f.controller, e = c.authorityVersion;
      a.failBeforeCommit = true;
      await c.setRepost(feed.postId, identity, true, authorityVersion: e);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonalRepostsList(controller: c, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无转帖'), findsNothing);
      expect(find.text('转帖结果尚未确认'), findsOneWidget);
      a.failBeforeCommit = false;
      await tester.tap(find.text('重试核对'));
      await tester.pumpAndSettle();
      expect(c.repostItems, hasLength(1));
    },
  );
  test('private DTO rejects account identifier and mismatched original', () {
    expect(
      () => PostRepostSnapshot.fromJson({
        'postId': feed.postId,
        'items': [],
        'accountId': identity,
      }),
      throwsFormatException,
    );
    expect(
      () => PostRepostSnapshot.fromJson({
        'postId': feed.postId,
        'items': [
          {'identityId': identity, 'repostedAt': feed.at.toIso8601String()},
          {'identityId': identity, 'repostedAt': feed.at.toIso8601String()},
        ],
      }),
      throwsFormatException,
    );
  });
  test('confirmed state shared, duplicate click bounded, identity cancellation precise', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    final c = f.controller, a = f.api as RepostApi, e = c.authorityVersion;
    a.repostWriteWait = Completer();
    final write = c.setRepost(feed.postId, identity, true, authorityVersion: e);
    await Future<void>.delayed(Duration.zero);
    expect(c.repostState(feed.postId).reposted, isFalse);
    await c.setRepost(feed.postId, identity, true, authorityVersion: e);
    expect(a.repostWrites, 1);
    a.repostWriteWait!.complete();
    await write;
    expect(c.repostState(feed.postId).reposted, isTrue);
    a.repostWriteWait = null;
    await c.setRepost(feed.postId, second, true, authorityVersion: e);
    await c.loadReposts(authorityVersion: e);
    expect(c.repostItems, hasLength(2));
    await c.setRepost(feed.postId, identity, false, authorityVersion: e);
    expect(c.repostItems.single.identityId, second);
    expect(c.repostState(feed.postId).value!.contains(identity), isFalse);
  });
  test(
    'lost committed response reconciles current state without duplicate',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      final c = f.controller, a = f.api as RepostApi, e = c.authorityVersion;
      a.loseAfterCommit = true;
      await c.setRepost(feed.postId, identity, true, authorityVersion: e);
      expect(c.repostState(feed.postId).reposted, isTrue);
      expect(c.repostState(feed.postId).unresolved, isFalse);
      expect(a.repostWrites, 1);
      await c.setRepost(feed.postId, identity, false, authorityVersion: e);
      expect(a.marks, isEmpty);
    },
  );
  test(
    'unknown uncommitted retry retains original CAS and never claims success',
    () async {
      final f = await fixture();
      addTearDown(f.dispose);
      final c = f.controller, a = f.api as RepostApi, e = c.authorityVersion;
      a.failBeforeCommit = true;
      await c.setRepost(feed.postId, identity, true, authorityVersion: e);
      expect(c.repostState(feed.postId).uncertain, isTrue);
      expect(c.repostState(feed.postId).reposted, isFalse);
      a.failBeforeCommit = false;
      await c.retryRepost(feed.postId, authorityVersion: e);
      expect(a.repostConditions.toSet(), hasLength(1));
      expect(c.repostState(feed.postId).unresolved, isFalse);
      expect(a.marks, hasLength(1));
    },
  );
  test('late read cannot overwrite cancellation', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    final c = f.controller, a = f.api as RepostApi, e = c.authorityVersion;
    await c.setRepost(feed.postId, identity, true, authorityVersion: e);
    final old = a.response(a.snapshot());
    a.repostReadWait = Completer();
    final read = c.loadRepostState(feed.postId, authorityVersion: e);
    await Future<void>.delayed(Duration.zero);
    final wait = a.repostReadWait!;
    a.repostReadWait = null;
    await c.setRepost(feed.postId, identity, false, authorityVersion: e);
    wait.complete(old);
    await read;
    expect(c.repostState(feed.postId).reposted, isFalse);
  });
  test('late archive read cannot restore cancelled row', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    final c = f.controller, a = f.api as RepostApi, e = c.authorityVersion;
    await c.setRepost(feed.postId, identity, true, authorityVersion: e);
    final old = await a.ownReposts(sessionToken: identityTestToken);
    a.listWait = Completer();
    final read = c.loadReposts(authorityVersion: e);
    await Future<void>.delayed(Duration.zero);
    final wait = a.listWait!;
    a.listWait = null;
    await c.setRepost(feed.postId, identity, false, authorityVersion: e);
    wait.complete(old);
    await read;
    expect(c.repostItems, isEmpty);
  });
  test('account switch rejects old page and delayed response', () async {
    final f = await fixture();
    addTearDown(f.dispose);
    final c = f.controller, a = f.api as RepostApi, e = c.authorityVersion;
    a.repostWriteWait = Completer();
    final write = c.setRepost(feed.postId, identity, true, authorityVersion: e);
    await Future<void>.delayed(Duration.zero);
    await f.auth.store.update(
      (s) => s.copyWith(
        session: SessionRecord(
          token: AuthCrypto.encode(List.filled(32, 22)),
          accountId: second,
          expiresAt: identityTestExpiry,
        ),
      ),
    );
    a.repostWriteWait!.complete();
    await write;
    expect(c.repostState(feed.postId).value, isNull);
    final count = a.repostWrites;
    await c.setRepost(feed.postId, identity, true, authorityVersion: e);
    expect(a.repostWrites, count);
    expect(c.repostItems, isEmpty);
  });
  testWidgets('feed entry and private unavailable archive cancellation', (
    tester,
  ) async {
    final f = await fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(feed.screen(f));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repost:${feed.postId}')), findsOneWidget);
    final c = f.controller;
    await c.setRepost(
      feed.postId,
      identity,
      true,
      authorityVersion: c.authorityVersion,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalRepostsList(
            controller: c,
            onOpen: (_) => fail('unavailable original opened'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('原帖已不可用'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('cancel-repost:$identity/${feed.postId}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认移除？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('暂无转帖'), findsOneWidget);
  });
}
