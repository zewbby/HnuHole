import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/comments/comment_api.dart';
import 'package:hnuhole_mobile/src/comments/comment_failure_view.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_controller.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/comments/comment_runtime.dart';
import 'package:hnuhole_mobile/src/comments/comment_views.dart';
import 'package:hnuhole_mobile/src/identity/identity_api.dart';

const post = '11111111-1111-4111-8111-111111111111',
    identity = '22222222-2222-4222-8222-222222222222',
    root = '33333333-3333-4333-8333-333333333333',
    reply = '44444444-4444-4444-8444-444444444444',
    account = '55555555-5555-4555-8555-555555555555';

class _MemoryJournal extends NativeCommentJournal {
  _MemoryJournal()
    : super((_) => throw StateError('Widget fixture has no native store'));
  final values = <String, CommentJournalEntry>{};
  @override
  Future<List<CommentJournalEntry>> read(String account) async =>
      values.values.toList();
  @override
  Future<void> put(String account, CommentJournalEntry e) async {
    values[e.localId] = e;
  }

  @override
  Future<void> remove(String account, String id) async {
    values.remove(id);
  }

  @override
  Future<void> close() async {
    values.clear();
  }
}

class _Api implements CommentApi {
  CommentIntent? sent;
  Completer<CommentTask>? pending;
  String? publishedId;
  @override
  Future<CommentTask> execute(CommentIntent i) async {
    sent = i;
    if (pending != null) return pending!.future;
    return CommentTask(
      taskId: i.taskId,
      binding: i.binding,
      attemptVersion: 1,
      state: publishedId == null
          ? CommentTaskState.accepted
          : CommentTaskState.published,
      commentId: publishedId,
      contentAvailable: publishedId == null,
      canRetry: false,
      canAbandon: false,
    );
  }

  @override
  Future<CommentTask?> query(CommentIntent i) async => null;
  @override
  Future<CommentTask?> queryTask({
    required String taskId,
    required CommentBinding binding,
  }) async => null;
}

Map<String, dynamic> row(
  String id,
  String body, {
  String? floor,
  String? target,
}) => {
  'id': id,
  'postId': post,
  'rootCommentId': floor,
  'targetCommentId': target,
  'body': body,
  'image': null,
  'author': {
    'ref': 'P0001',
    'nickname': '合成作者',
    'avatar': 'default-v1',
    'state': 'ACTIVE',
  },
  'replyTo': target == null
      ? null
      : {
          'commentId': target,
          'author': {
            'ref': 'P0001',
            'nickname': '合成作者',
            'avatar': 'default-v1',
            'state': 'ACTIVE',
          },
        },
  'isPostAuthor': false,
  'publishedAt': '2026-10-19T01:00:00Z',
  'likeCount': 0,
  'likedByMe': false,
  'replyCount': floor == null ? 1 : 0,
};

class _Runtime extends ChangeNotifier implements CommentRuntime {
  _Runtime(this.journal) {
    transportFake = _Api();
    core = CommentController(api: transportFake, journal: journal);
    core.addListener(notifyListeners);
  }
  @override
  final NativeCommentJournal journal;
  late final _Api transportFake;
  @override
  late final CommentController core;
  @override
  int get authorityVersion => 0;
  @override
  bool get available => true;
  @override
  String get accountId => account;
  @override
  bool current(int e) => e == 0;
  @override
  final deleted = <String>{};
  @override
  final mutations = <String, Map<String, dynamic>>{};
  @override
  String? error;
  final ownIds = <String>[];
  String? removed;
  Object? loadFailure;
  Object? replyFailure;
  bool moreReplies = false;
  Completer<void>? pageGate;
  List<Map<String, dynamic>> rootRows = [row(root, '甲的主评论')];
  @override
  Future<void> mutate(String id, {bool? liked}) async {
    if (liked == null) {
      removed = id;
      deleted.add(id);
      notifyListeners();
    }
  }

  @override
  Future<Map<String, dynamic>> contextFor(String _) async => {
    'boundIdentityId': identity,
    'ownCommentIds': ownIds,
    'totalCount': 2,
  };
  @override
  Future<IdentityDirectory> directory() async => IdentityDirectory(
    identities: [
      ManagedIdentity(
        id: identity,
        nickname: '固定身份',
        avatar: 'default-v1',
        isOriginal: false,
        createdAt: DateTime.utc(2026),
      ),
    ],
    createdCount: 1,
    serverTime: DateTime.utc(2026),
    sessionExpiresAt: DateTime.utc(2027),
  );
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    dynamic bytes,
    String? mime,
  }) async {
    if (path.endsWith('/comments') && pageGate != null) await pageGate!.future;
    if (loadFailure != null) throw loadFailure!;
    if (path.endsWith('/replies') && replyFailure != null) throw replyFailure!;
    if (path.endsWith('/location')) return {'cursor': 'location'};
    final single = rootRows
        .where((r) => path.endsWith('/${r['id']}'))
        .firstOrNull;
    if (single != null) return single;
    return path.endsWith('/replies')
        ? {
            'snapshotId': 'snapshot',
            'rootCommentId': root,
            'comments': [row(reply, '乙回复甲的具体内容', floor: root, target: root)],
            'nextCursor': moreReplies ? 'reply-cursor' : null,
            'remainingCount': moreReplies ? 5 : 0,
          }
        : {
            'snapshotId': 'snapshot',
            'comments': rootRows,
            'nextCursor': null,
            'totalCount': rootRows.length,
          };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'known deleted floor is removed when loading its remaining replies fails',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal)..moreReplies = true;
      r.rootRows.single['replyCount'] = 6;
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const Text('原帖正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论 2'));
      await tester.pumpAndSettle();
      r.replyFailure = const CommentHttpFailure(404, 'COMMENT_NOT_FOUND');
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开其余 1 条回复'));
      await tester.pumpAndSettle();
      expect(find.text('甲的主评论'), findsNothing);
      expect(find.text('乙回复甲的具体内容'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets(
    'publication during a pending page waits and still locates the owner content',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      r.rootRows = [
        for (var i = 1; i <= 60; i++)
          row(
            '${i.toRadixString(16).padLeft(8, '0')}-8888-4888-8888-888888888888',
            '等待期间评论$i',
          ),
      ];
      for (final value in r.rootRows) {
        value['replyCount'] = 0;
      }
      final target = r.rootRows.last['id'] as String;
      r.ownIds.add(target);
      r.transportFake.publishedId = target;
      r.pageGate = Completer<void>();
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const Text('原帖正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论 2'));
      await tester.pump();
      await r.core.submit(
        taskId: root,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '成功定位'),
      );
      r.pageGate!.complete();
      await tester.pumpAndSettle();
      final position = tester.getCenter(find.text('等待期间评论60'));
      expect(position.dy, greaterThan(0));
      expect(position.dy, lessThan(600));
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets(
    'offscreen media stays unmounted while concrete row layout remains positionable',
    (tester) async {
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  for (var i = 0; i < 70; i++)
                    CommentViewportMedia(builder: (_) => Text('media-$i')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('media-0'), findsOneWidget);
      expect(find.text('media-69'), findsNothing);
      expect(find.textContaining('media-'), findsNWidgets(4));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('media-0'), findsNothing);
      expect(find.text('media-69'), findsOneWidget);
      expect(
        find.textContaining('media-').evaluate().length,
        lessThanOrEqualTo(4),
      );
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets(
    'body reply closes after durable submission while transport is still pending',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      r.transportFake.pending = Completer<CommentTask>();
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const Text('原帖正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('甲的主评论'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '已提交后台发送');
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect((await journal.read(account)).single.content!.body, '已提交后台发送');
      final sent = r.transportFake.sent!;
      expect(sent.binding.targetCommentId, root);
      r.transportFake.pending!.complete(
        CommentTask(
          taskId: sent.taskId,
          binding: sent.binding,
          attemptVersion: 1,
          state: CommentTaskState.accepted,
          contentAvailable: true,
          canRetry: false,
          canAbandon: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets(
    'local unknown task appears only under its original identity notifications',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      await r.core.activate(account);
      await r.core.submit(
        taskId: root,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '原面具私有内容'),
      );
      for (final selected in [null, reply, identity]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CommentPendingView(runtime: r, identityId: selected),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('原面具私有内容'),
          selected == identity ? findsOneWidget : findsNothing,
        );
      }
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets(
    'authoritative read denial removes cached comments and first failure has no empty state',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const Text('原帖正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论 2'));
      await tester.pumpAndSettle();
      expect(find.text('甲的主评论'), findsOneWidget);
      await tester.tap(find.text('收起评论'));
      await tester.pumpAndSettle();
      r.loadFailure = const CommentHttpFailure(404, 'POST_NOT_FOUND');
      await tester.tap(find.text('评论 1'));
      await tester.pumpAndSettle();
      expect(find.text('甲的主评论'), findsNothing);
      expect(find.text('暂无评论'), findsNothing);
      expect(find.text('评论暂时无法读取，请重新核对。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets(
    'deep location scrolls to a comment initially outside the viewport',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      r.rootRows = [
        for (var i = 1; i <= 70; i++)
          row(
            '${i.toRadixString(16).padLeft(8, '0')}-7777-4777-8777-777777777777',
            '屏外评论$i',
          ),
      ];
      for (final value in r.rootRows) {
        value['replyCount'] = 0;
      }
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const Text('原帖正文'),
              initialCommentId: r.rootRows.last['id'] as String,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final position = tester.getCenter(find.text('屏外评论70'));
      expect(position.dy, greaterThan(0));
      expect(position.dy, lessThan(600));
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets('owner delete acts directly without an extra confirmation', (
    tester,
  ) async {
    final journal = _MemoryJournal();
    final r = _Runtime(journal)..ownIds.add(root);
    await r.core.activate(account);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentPostPane(
            runtime: r,
            postId: post,
            postBody: '原帖正文',
            body: const Text('原帖正文'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('评论 2'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(r.removed, root);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('甲的主评论'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    r.core.dispose();
    r.dispose();
    await journal.close();
  });
  testWidgets(
    'retargeted failed content stays temporary until explicit target confirmation and publish',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const Text('原帖正文'),
              initialInput: CommentRejectedInput(
                binding: CommentBinding(
                  postId: post,
                  identityId: identity,
                  rootCommentId: root,
                  targetCommentId: '66666666-6666-4666-8666-666666666666',
                ),
                content: CommentContent(body: '失败后保留的内容'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(await journal.read(account), isEmpty);
      expect(r.transportFake.sent, isNull);
      await tester.tap(find.text('继续输入'));
      await tester.pumpAndSettle();
      expect(find.text('更换回复对象？'), findsOneWidget);
      await tester.tap(find.text('更换'));
      await tester.pumpAndSettle();
      expect(find.text('失败后保留的内容'), findsOneWidget);
      expect(r.transportFake.sent, isNull);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(r.transportFake.sent!.binding.targetCommentId, isNull);
      expect(r.transportFake.sent!.binding.identityId, identity);
      expect((await journal.read(account)).single.content!.body, '失败后保留的内容');
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
  testWidgets(
    'temporary input survives collapse and exact reply binds the submitted task',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      await r.core.activate(account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖正文',
              body: const SingleChildScrollView(child: Text('原帖正文')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论 2'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('回复').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('乙回复甲的具体内容'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '临时输入原文');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(await journal.read(account), isEmpty);
      await tester.tap(find.text('继续输入'));
      await tester.pumpAndSettle();
      expect(find.text('临时输入原文'), findsOneWidget);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(r.transportFake.sent!.binding.identityId, identity);
      expect(r.transportFake.sent!.binding.targetCommentId, reply);
      expect(r.transportFake.sent!.binding.rootCommentId, root);
      expect((await journal.read(account)).single.content!.body, '临时输入原文');
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
}
