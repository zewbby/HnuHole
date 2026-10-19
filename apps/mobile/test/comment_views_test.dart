import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/comments/comment_api.dart';
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
  @override
  Future<CommentTask> execute(CommentIntent i) async {
    sent = i;
    return CommentTask(
      taskId: i.taskId,
      binding: i.binding,
      attemptVersion: 1,
      state: CommentTaskState.accepted,
      contentAvailable: true,
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
  @override
  Future<Map<String, dynamic>> contextFor(String _) async => {
    'boundIdentityId': identity,
    'ownCommentIds': <String>[],
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
  }) async => path.endsWith('/replies')
      ? {
          'snapshotId': 'snapshot',
          'rootCommentId': root,
          'comments': [row(reply, '乙回复甲的具体内容', floor: root, target: root)],
          'nextCursor': null,
          'remainingCount': 0,
        }
      : {
          'snapshotId': 'snapshot',
          'comments': [row(root, '甲的主评论')],
          'nextCursor': null,
          'totalCount': 2,
        };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
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
