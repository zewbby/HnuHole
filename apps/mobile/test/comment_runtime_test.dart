import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_runtime.dart';
import 'package:hnuhole_mobile/src/comments/comment_views.dart';

import 'identity_test_support.dart';

const _post = '11111111-1111-4111-8111-111111111111';
const _root = '22222222-2222-4222-8222-222222222222';
const _otherAccount = '00000000-0000-0000-0000-000000000002';
typedef _Reply = ({Map<String, dynamic> value, DateTime expires});

// Only HTTP and storage are substitutes. AuthSessionController, CommentRuntime,
// its authority fences and the production detail/comment pane are real.
class _Store implements PostStore {
  _Store(this.accountId);
  @override
  final String accountId;
  @override
  Future<List<StoredPostEntry>> list() async => [];
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RenewingSessionApi extends IdentityTestSessionApi {
  int renewals = 0;
  @override
  Future<DateTime> renewSession(String token) async {
    renewals++;
    return identityTestRenewed;
  }
}

class _Http extends CommentHttp {
  _Http() : super(Uri.parse('https://unused.invalid'));
  Completer<_Reply>? pending;
  @override
  Future<_Reply> send(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
  }) async {
    if (path == '/late') return pending!.future;
    return (
      expires: identityTestRenewed,
      value: path.endsWith('/comment-context')
          ? {
              'boundIdentityId': identityTestId,
              'ownCommentIds': <String>[],
              'totalCount': 1,
            }
          : {
              'snapshotId': 'snapshot',
              'comments': [
                {
                  'id': _root,
                  'postId': _post,
                  'rootCommentId': null,
                  'targetCommentId': null,
                  'body': '续期前已加载评论',
                  'image': null,
                  'author': {
                    'ref': 'P0001',
                    'nickname': '合成作者',
                    'avatar': 'default-v1',
                    'state': 'ACTIVE',
                  },
                  'replyTo': null,
                  'isPostAuthor': false,
                  'publishedAt': '2026-10-20T01:00:00Z',
                  'likeCount': 0,
                  'likedByMe': false,
                  'replyCount': 0,
                },
              ],
              'nextCursor': null,
              'totalCount': 1,
            },
    );
  }
}

Future<
  ({
    IdentityTestFixture auth,
    _RenewingSessionApi sessionsApi,
    _Http http,
    CommentRuntime runtime,
    NativeCommentJournal journal,
  })
>
_fixture() async {
  final vault = IdentityTestVault();
  final store = AuthStore(vault);
  await store.update(
    (state) => state.copyWith(
      session: SessionRecord(
        token: identityTestToken,
        accountId: identityTestAccount,
        expiresAt: identityTestExpiry,
      ),
    ),
  );
  final sessionsApi = _RenewingSessionApi();
  final directory = ChannelDirectoryController(
    repository: IdentityTestChannels(),
  );
  final sessions = AuthSessionController(
    api: sessionsApi,
    store: store,
    directory: directory,
  );
  await sessions.start();
  final identities = IdentityTestApi()..items = [identityTestItem()];
  final management = IdentityManagementController(
    api: identities,
    store: store,
    sessions: sessions,
  );
  final auth = IdentityTestFixture(
    vault,
    store,
    sessionsApi,
    sessions,
    directory,
    identities,
    management,
  );
  final http = _Http();
  final journal = NativeCommentJournal((account) async => _Store(account));
  final runtime = CommentRuntime(
    http: http,
    sessions: sessions,
    authStore: store,
    identities: identities,
    identityManagement: management,
    journal: journal,
  );
  return (
    auth: auth,
    sessionsApi: sessionsApi,
    http: http,
    runtime: runtime,
    journal: journal,
  );
}

Future<void> _open(WidgetTester tester, CommentRuntime runtime) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CommentPostPane(
          runtime: runtime,
          postId: _post,
          postBody: '已授权原帖正文',
          body: const Text('已授权原帖正文'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('评论 1'));
  await tester.pumpAndSettle();
  expect(find.text('续期前已加载评论'), findsOneWidget);
  await tester.tap(find.text('写评论'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '尚未提交的评论草稿');
  await tester.tap(find.byType(CloseButton));
  await tester.pumpAndSettle();
  expect(find.text('继续输入'), findsOneWidget);
}

void main() {
  testWidgets(
    'same-token activity renewal preserves real comment pane, draft and pending read',
    (tester) async {
      final f = await _fixture();
      try {
        await _open(tester, f.runtime);
        final epoch = f.runtime.authorityVersion;
        f.journal.staged['draft-image'] = Uint8List.fromList([1, 2, 3]);
        f.http.pending = Completer<_Reply>();
        final pending = f.runtime
            .request('GET', '/late')
            .then<Object>((value) => value, onError: (Object error) => error);
        await f.auth.store.update(
          (state) => state.copyWith(
            session: SessionRecord(
              token: identityTestToken,
              accountId: identityTestAccount,
              expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
            ),
          ),
        );
        await f.auth.sessions.onActivity();
        f.http.pending!.complete((
          value: {'marker': 'same-authority'},
          expires: identityTestRenewed,
        ));
        final result = await pending;
        await tester.pumpAndSettle();
        expect(f.sessionsApi.renewals, 1);
        expect(f.runtime.authorityVersion, epoch);
        expect(result, {'marker': 'same-authority'});
        expect(f.runtime.current(epoch), isTrue);
        expect(f.journal.staged['draft-image'], [1, 2, 3]);
        expect(find.text('已授权原帖正文'), findsOneWidget);
        expect(find.text('续期前已加载评论'), findsOneWidget);
        expect(find.textContaining('会话已变化'), findsNothing);
        await tester.tap(find.text('继续输入'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '尚未提交的评论草稿',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        f.runtime.dispose();
        f.auth.dispose();
      }
    },
  );

  for (final loss in ['401', '503', 'logout', 'account']) {
    testWidgets(
      'comment pane closes on $loss and rejects previous authority late response',
      (tester) async {
        final f = await _fixture();
        try {
          await _open(tester, f.runtime);
          final epoch = f.runtime.authorityVersion;
          f.journal.staged['draft-image'] = Uint8List.fromList([1]);
          f.http.pending = Completer<_Reply>();
          final pending = f.runtime
              .request('GET', '/late')
              .then<Object>((value) => value, onError: (Object error) => error);
          switch (loss) {
            case '401':
              f.auth.sessions.sessionUnauthorized(
                identityTestToken,
                'SESSION_INVALID',
              );
            case '503':
              f.auth.sessions.sessionUnavailable(identityTestToken);
            case 'logout':
              await f.auth.sessions.logout();
            case 'account':
              f.sessionsApi.account = _otherAccount;
              await f.auth.sessions.login('synthetic-b', 'synthetic-password');
          }
          await tester.pumpAndSettle();
          final expiry = f.auth.store.current?.session?.expiresAt;
          f.http.pending!.complete((
            value: {'marker': 'old-account'},
            expires: DateTime.utc(2032),
          ));
          expect(
            await pending,
            isA<CommentHttpFailure>().having(
              (e) => e.code,
              'code',
              'SESSION_CHANGED',
            ),
          );
          await tester.pumpAndSettle();
          expect(f.runtime.current(epoch), isFalse);
          expect(f.runtime.authorityVersion, greaterThan(epoch));
          expect(f.journal.staged, isEmpty);
          expect(find.text('已授权原帖正文'), findsNothing);
          expect(find.text('续期前已加载评论'), findsNothing);
          expect(find.textContaining('会话已变化'), findsOneWidget);
          expect(f.auth.store.current?.session?.expiresAt, expiry);
        } finally {
          await tester.pumpWidget(const SizedBox());
          f.runtime.dispose();
          f.auth.dispose();
        }
      },
    );
  }
}
