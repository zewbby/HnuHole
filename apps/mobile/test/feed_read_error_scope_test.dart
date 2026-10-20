import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/feed_api.dart';
import 'package:hnuhole_mobile/src/posts/feed_screen.dart';

import 'feed_interactions_test.dart' as interactions;
import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';

const _uncertain = '暂时无法核对结果，原操作已保留，请稍后核对。';
const _entryId = 'read-error-command';

// A working account store substitute, not the deliberately failing store in
// FeedTestController. Only this error-routing test's read/result operations are
// implemented; no claim about SQLite or native secure storage is made.
class _Store implements PostStore {
  _Store(this.accountId);
  @override
  final String accountId;
  final entries = <String, StoredPostEntry>{};
  final firstRead = Completer<void>();
  @override
  Future<List<StoredPostEntry>> list() async {
    final snapshot = entries.values.toList();
    if (!firstRead.isCompleted) firstRead.complete();
    return snapshot;
  }

  @override
  Future<StoredPostEntry?> get(String id) async => entries[id];
  @override
  Future<StoredPostEntry> recordResult(
    String id,
    int revision,
    String state,
    Map<String, dynamic> data,
  ) async {
    final old = entries[id]!;
    if (old.revision != revision) throw const PostStorageConflict();
    return entries[id] = StoredPostEntry(
      id: id,
      revision: revision + 1,
      state: state,
      data: data,
      intents: old.intents,
    );
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected store operation ${invocation.memberName}');
}

class _Api extends interactions.InteractionTestApi {
  Object? preferencesFailure, saveFailure;
  bool commandLost = true;
  @override
  Future<PostResponse<FeedPreferences>> feedPreferences({
    required String sessionToken,
  }) async {
    final failure = preferencesFailure;
    preferencesFailure = null;
    if (failure != null) throw failure;
    return super.feedPreferences(sessionToken: sessionToken);
  }

  @override
  Future<PostResponse<FeedPreferences>> saveFeedPreferences({
    required String sessionToken,
    required Set<String> blockedChannelIds,
  }) async {
    final failure = saveFailure;
    saveFailure = null;
    if (failure != null) throw failure;
    return super.saveFeedPreferences(
      sessionToken: sessionToken,
      blockedChannelIds: blockedChannelIds,
    );
  }

  @override
  Future<PostResponse<PostCommandResult>> commandResult({
    required String sessionToken,
    required String commandId,
  }) async {
    if (commandLost) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return feed.reply(
      const PostCommandResult(
        state: PostCommandState.rejected,
        operation: PostOperation.create,
        errorCode: 'POST_CONTENT_REJECTED',
      ),
    );
  }
}

class _Fixture {
  _Fixture(this.auth) {
    controller = PostController(
      api: api,
      sessions: auth.sessions,
      authStore: auth.store,
      identities: auth.api,
      pollInterval: Duration.zero,
      openStore: (id) async => stores.putIfAbsent(id, () => _Store(id)),
    );
  }
  final IdentityTestFixture auth;
  final api = _Api();
  final stores = <String, _Store>{};
  late final PostController controller;
  static Future<_Fixture> create() async {
    final result = _Fixture(await IdentityTestFixture.create());
    await result.stores[identityTestAccount]!.firstRead.future;
    return result;
  }

  void seedCommand() {
    stores[identityTestAccount]!.entries[_entryId] = StoredPostEntry(
      id: _entryId,
      revision: 1,
      state: 'submitted',
      data: {
        'title': '原命令',
        'body': '保留原内容',
        'channelId': feed.channelId,
        'identityId': identityTestId,
        'editedAt': feed.at.toIso8601String(),
      },
      intents: [
        StoredPostIntent(
          commandId: AuthCrypto.encode(List.filled(16, 71)),
          operation: 'CREATE',
          digest: '0' * 64,
          payload: {},
        ),
      ],
    );
  }

  void dispose() {
    controller.dispose();
    auth.dispose();
  }
}

Widget _screen(_Fixture f) => MaterialApp(
  home: FeedScreen(
    controller: f.controller,
    channels: feed.channels,
    composeChannel: feed.channels.first,
    onManageIdentities: () async {},
    onAuthenticationRequired: () {},
  ),
);

void main() {
  for (final stage in ['preferences', 'timeline']) {
    testWidgets(
      '$stage failure retries locally without poisoning reopened detail',
      (tester) async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await tester.pumpWidget(_screen(f));
        await tester.pumpAndSettle();
        expect(f.controller.errorMessage, isNull);
        if (stage == 'preferences') {
          f.api.preferencesFailure = const PostFailure(
            kind: PostFailureKind.transport,
          );
        } else {
          f.api.timelineFailure = const PostFailure(
            kind: PostFailureKind.transport,
          );
        }
        await f.controller.loadTimeline();
        await tester.pumpAndSettle();
        expect(find.text('重新加载'), findsOneWidget);
        await tester.tap(find.text('重新加载'));
        await tester.pumpAndSettle();
        expect(f.controller.timelineError, isNull);
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.tap(find.text('今天的校园'));
          await tester.pumpAndSettle();
          expect(find.text(_uncertain), findsNothing);
          expect(find.byType(SelectableText), findsOneWidget);
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('detail-like:${feed.postId}')),
                )
                .onPressed,
            isNotNull,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'feed failures preserve command ownership until its own result confirms',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.seedCommand();
      await f.controller.reconcile(_entryId);
      expect(f.controller.errorMessage, _uncertain);
      f.api.timelineFailure = const PostFailure(
        kind: PostFailureKind.transport,
      );
      await f.controller.loadTimeline();
      expect(f.controller.timelineError, isNotNull);
      await f.controller.loadTimeline();
      expect(f.controller.errorMessage, _uncertain);
      f.api.commandLost = false;
      await f.controller.reconcile(_entryId);
      expect(
        f.stores[identityTestAccount]!.entries[_entryId]!.state,
        'REJECTED',
      );
      expect(f.controller.errorMessage, isNull);
    },
  );

  test(
    'successful pending feed read does not clear a later command failure',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final pending = Completer<PostResponse<PostsPage<FeedPost>>>();
      f.api.pageWait = pending;
      final read = f.controller.loadTimeline();
      await Future<void>.delayed(Duration.zero);
      f.seedCommand();
      await f.controller.reconcile(_entryId);
      expect(f.controller.errorMessage, _uncertain);
      pending.complete(
        feed.reply(PostsPage(items: [feed.post()], nextCursor: null)),
      );
      await read;
      expect(f.controller.errorMessage, _uncertain);
      f.api.commandLost = false;
      await f.controller.reconcile(_entryId);
      expect(f.controller.errorMessage, isNull);
    },
  );

  test(
    'lost preference writes and failed reconciliation stay in local errors',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      f.api.writeLost = true;
      await f.controller.saveBlockedChannels({feed.channelId});
      expect(f.controller.preferencesError, isNotNull);
      expect(f.controller.errorMessage, isNull);
      f.api.commitLost = true;
      await f.controller.saveBlockedChannels({feed.channelId});
      expect(f.controller.blockedChannelIds, {feed.channelId});
      expect(f.controller.preferencesError, isNull);
      expect(f.controller.errorMessage, isNull);
      f.api.readFails = true;
      await f.controller.saveBlockedChannels({});
      expect(f.controller.preferencesError, isNotNull);
      expect(f.controller.errorMessage, isNull);
      f.api.readFails = f.api.writeLost = false;
      await f.controller.loadTimeline();
      expect(f.controller.preferencesError, isNull);
      expect(f.controller.errorMessage, isNull);
    },
  );

  final sessionFailures = <Object>[
    const PostFailure(kind: PostFailureKind.unauthorized, statusCode: 401),
    const PostFailure(kind: PostFailureKind.unavailable, statusCode: 503),
    const AuthFailure(kind: AuthFailureKind.unauthorized, statusCode: 401),
    const AuthFailure(kind: AuthFailureKind.unavailable, statusCode: 503),
  ];
  for (var i = 0; i < sessionFailures.length; i++) {
    for (final stage in ['read', 'write', 'write-recheck']) {
      test(
        'session failure $i at $stage still closes original content',
        () async {
          final f = await _Fixture.create();
          addTearDown(f.dispose);
          await f.controller.loadTimeline();
          if (stage == 'read') {
            f.api.preferencesFailure = sessionFailures[i];
            await f.controller.loadTimeline();
          } else {
            if (stage == 'write') {
              f.api.saveFailure = sessionFailures[i];
            } else {
              f.api.writeLost = true;
              f.api.preferencesFailure = sessionFailures[i];
            }
            await f.controller.saveBlockedChannels({feed.channelId});
          }
          expect(f.controller.available, false);
          expect(f.controller.timelineItems, isEmpty);
          expect(
            f.auth.sessions.status,
            i.isEven ? AuthStatus.signedOut : AuthStatus.unavailable,
          );
          // Authority closes before the serialized durable token removal ends.
          await f.auth.store.read();
          expect(f.auth.store.current!.session, i.isEven ? isNull : isNotNull);
        },
      );
    }
  }

  for (final kind in [
    AuthFailureKind.timeout,
    AuthFailureKind.unknownOutcome,
    AuthFailureKind.rejected,
    AuthFailureKind.invalidResponse,
  ]) {
    test(
      'non-authority $kind stays local and preserves the original command',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        f.seedCommand();
        await f.controller.reconcile(_entryId);
        f.api.preferencesFailure = AuthFailure(kind: kind);
        await f.controller.loadTimeline();
        expect(f.controller.timelineError, isNotNull);
        expect(f.controller.available, true);
        expect(f.auth.sessions.status, AuthStatus.authenticated);
        expect(f.controller.errorMessage, _uncertain);
        await f.controller.loadTimeline();
        expect(f.controller.timelineError, isNull);
        expect(f.controller.errorMessage, _uncertain);
        f.api.commandLost = false;
        await f.controller.reconcile(_entryId);
        expect(f.controller.errorMessage, isNull);
      },
    );
  }

  for (final kind in [
    PostFailureKind.transport,
    PostFailureKind.unauthorized,
    PostFailureKind.unavailable,
  ]) {
    test('late old-account $kind cannot alter the new account', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final pending = Completer<PostResponse<PostsPage<FeedPost>>>();
      f.api.pageWait = pending;
      final old = f.controller.loadTimeline();
      await Future<void>.delayed(Duration.zero);
      f.auth.sessionApi.account = feed.otherChannelId;
      await f.auth.sessions.acceptSession(
        AuthSession(
          accountId: feed.otherChannelId,
          sessionToken: identityTestOtherToken,
          expiresAt: identityTestExpiry,
        ),
      );
      f.api.pageWait = null;
      await f.controller.loadTimeline();
      pending.completeError(PostFailure(kind: kind));
      await old;
      expect(f.controller.accountId, feed.otherChannelId);
      expect(f.controller.errorMessage, isNull);
      expect(f.controller.timelineError, isNull);
      expect(f.controller.available, true);
    });
  }

  test(
    'session metadata storage failure still closes the feed authority',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.loadTimeline();
      f.auth.vault.failContaining = '2031-01-31';
      await f.controller.loadTimeline();
      expect(f.auth.sessions.status, AuthStatus.storageFailure);
      expect(f.controller.available, false);
      expect(f.controller.timelineItems, isEmpty);
    },
  );
}
