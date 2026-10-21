import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/design_system/detail_components.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';
import 'package:hnuhole_mobile/src/comments/comment_api.dart';
import 'package:hnuhole_mobile/src/comments/comment_failure_view.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_controller.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/comments/comment_runtime.dart';
import 'package:hnuhole_mobile/src/comments/comment_views.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';
import 'feed_ui_test.dart' as feed;
import 'feed_interactions_test.dart' as interactions;

import 'package:hnuhole_mobile/src/comments/comment_editor.dart';
import 'package:hnuhole_mobile/src/comments/quick_reply_dialog.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';

const post = '11111111-1111-4111-8111-111111111111',
    identity = '22222222-2222-4222-8222-222222222222',
    root = '33333333-3333-4333-8333-333333333333',
    reply = '44444444-4444-4444-8444-444444444444',
    account = '55555555-5555-4555-8555-555555555555';

class _MemoryJournal extends NativeCommentJournal {
  _MemoryJournal()
    : super((_) => throw StateError('Widget fixture has no native store'));
  final values = <String, CommentJournalEntry>{};
  final writes = <CommentJournalEntry>[];
  bool failWrite = false;
  @override
  Future<List<CommentJournalEntry>> read(String account) async =>
      values.values.toList();
  @override
  Future<void> put(String account, CommentJournalEntry e) async {
    if (failWrite) throw StateError('Synthetic journal failure');
    writes.add(e);
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
  VoidCallback? onExecute;
  Object? executeFailure;
  @override
  Future<CommentTask> execute(CommentIntent i) async {
    sent = i;
    onExecute?.call();
    if (executeFailure case final failure?) throw failure;
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
  bool bound = true;
  bool hideIdentity = false;
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
    'boundIdentityId': bound ? identity : null,
    'ownCommentIds': ownIds,
    'totalCount': 2,
  };
  @override
  Future<IdentityDirectory> directory() async => IdentityDirectory(
    identities: [
      if (!hideIdentity)
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
  quickReplyTests();
  testWidgets(
    'real root and reply rows open report forms for their concrete comment',
    (tester) async {
      final auth = await IdentityTestFixture.create();
      final governance = GovernanceController(
        api: _ReportApi(),
        sessions: auth.sessions,
        authStore: auth.store,
        identitiesApi: auth.api,
        pendingStore: GovernancePendingStore(IdentityTestVault()),
      );
      addTearDown(() {
        governance.dispose();
        auth.dispose();
      });
      final runtime = _Runtime(_MemoryJournal());
      await runtime.core.activate(account);
      addTearDown(runtime.core.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: GovernanceScope(
            controller: governance,
            child: Scaffold(
              body: CommentPostPane(
                runtime: runtime,
                postId: post,
                postBody: '原帖',
                body: const Text('原帖'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论 2'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('举报').first);
      await tester.tap(find.text('举报').first);
      await tester.pumpAndSettle();
      var screen = tester.widget<ReportScreen>(find.byType(ReportScreen));
      expect(screen.postId, post);
      expect(screen.commentId, root);
      expect(find.text('举报主评论'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('举报').last);
      await tester.tap(find.text('举报').last);
      await tester.pumpAndSettle();
      screen = tester.widget<ReportScreen>(find.byType(ReportScreen));
      expect(screen.postId, post);
      expect(screen.commentId, reply);
      expect(find.text('举报回复'), findsOneWidget);
    },
  );
  testWidgets(
    'a comment media section activates after scrolling its image into the split viewport',
    (tester) async {
      final journal = _MemoryJournal();
      final r = _Runtime(journal);
      r.rootRows.single['image'] = {
        'contentVersionId': reply,
        'mimeType': 'image/gif',
        'pixelWidth': 5,
        'pixelHeight': 5,
      };
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
      await tester.ensureVisible(find.byType(CommentImageView));
      await tester.pumpAndSettle();
      expect(find.byType(PostImagesSection), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.core.dispose();
      r.dispose();
      await journal.close();
    },
  );
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
    await tester.ensureVisible(find.text('删除'));
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

class _RetiringRuntime extends _Runtime {
  _RetiringRuntime(super.journal);
  bool active = true;
  @override
  bool get available => active;
  @override
  bool current(int e) => active && e == 0;
  void retire() {
    active = false;
    notifyListeners();
  }
}

void quickReplyTests() {
  Future<_RetiringRuntime> runtime(
    WidgetTester tester, {
    bool bound = true,
  }) async {
    final r = _RetiringRuntime(_MemoryJournal())..bound = bound;
    await r.core.activate(account);
    addTearDown(() {
      r.core.dispose();
      r.dispose();
    });
    return r;
  }

  Future<void> launch(
    WidgetTester tester,
    _Runtime r,
    CommentEditor editor,
  ) async {
    final originals = <String, Uint8List>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: HhTelegramTheme.create(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('打开回复'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CommentComposer(
                  runtime: r,
                  editor: editor,
                  originals: originals,
                  contextText: '原帖',
                  quickReplyTo: '松间',
                  onOpenRejected: () {},
                  onSubmitted: editor.leave,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开回复'));
    await tester.pumpAndSettle();
  }

  Future<CommentIntent> reject(
    _Runtime r, {
    String? target,
    Object? failure,
  }) async {
    r.transportFake.executeFailure =
        failure ?? CommentCommandRejected('IDENTITY_UNAVAILABLE');
    await r.core.submit(
      taskId: commentUUID(),
      commandId: commentKey(),
      binding: CommentBinding(
        postId: post,
        identityId: identity,
        rootCommentId: target == null ? null : root,
        targetCommentId: target,
      ),
      content: CommentContent(body: '原评论完整内容'),
    );
    return r.transportFake.sent!;
  }

  testWidgets(
    'authoritative quick rejection restores input and explicitly resends with fresh keys',
    (tester) async {
      final r = await runtime(tester);
      final old = await reject(r);
      expect(r.core.entries.single.rejectionCode, 'IDENTITY_UNAVAILABLE');
      await launch(tester, r, CommentEditor(CommentTarget(postId: post)));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('reply-send')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('恢复未发送内容'));
      await tester.pumpAndSettle();
      expect(find.text('原评论完整内容'), findsOneWidget);
      expect(r.core.entries, isEmpty);
      expect(r.transportFake.sent, same(old));
      r.transportFake.executeFailure = null;
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      final sent = r.transportFake.sent!;
      expect(sent.taskId, isNot(old.taskId));
      expect(sent.commandId, isNot(old.commandId));
      expect(sent.binding.targetCommentId, isNull);
      expect(sent.content!.body, '原评论完整内容');
      expect(find.byType(QuickReplyDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rejected nested target is retained for original detail recovery',
    (tester) async {
      final r = await runtime(tester);
      final old = await reject(r, target: reply);
      await launch(tester, r, CommentEditor(CommentTarget(postId: post)));
      expect(find.text('前往原帖恢复'), findsOneWidget);
      expect(find.text('恢复未发送内容'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('reply-send')))
            .onPressed,
        isNull,
      );
      expect(r.core.entries.single.intent.binding.sameAs(old.binding), true);
      expect(r.core.entries.single.content!.body, '原评论完整内容');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'retirement during recovery confirmation closes child and preserves journal',
    (tester) async {
      final r = await runtime(tester);
      await reject(r);
      final editor = CommentEditor(CommentTarget(postId: post))
        ..body = '当前未发草稿';
      await launch(tester, r, editor);
      await tester.tap(find.text('恢复未发送内容'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('恢复之前的评论？'), findsOneWidget);
      r.retire();
      await tester.pumpAndSettle();
      expect(find.byType(QuickReplyDialog), findsNothing);
      expect(find.text('恢复之前的评论？'), findsNothing);
      expect(editor.hasInput, false);
      expect(
        (r.journal as _MemoryJournal).values.values.single.content!.body,
        '原评论完整内容',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('transport unknown is never offered as rejected input recovery', (
    tester,
  ) async {
    final r = await runtime(tester);
    await reject(r, failure: StateError('Synthetic lost response'));
    expect(r.core.entries.single.transport, CommentTransportState.unknown);
    await launch(tester, r, CommentEditor(CommentTarget(postId: post)));
    expect(find.text('恢复未发送内容'), findsNothing);
    expect(find.text('前往原帖恢复'), findsNothing);
    expect(r.core.entries.single.content!.body, '原评论完整内容');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real continuous detail registers a visible body once', (tester) async {
    final f = await interactions.fixture();
    addTearDown(f.dispose);
    final r = await runtime(tester);
    await tester.pumpWidget(CommentScope(runtime: r, child: feed.screen(f)));
    await tester.pumpAndSettle();
    expect(f.api.calls.where((c) => c.startsWith('view:')), isEmpty);
    await tester.tap(find.text(feed.post().title).first);
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(f.api.calls.where((c) => c == 'view:${feed.postId}'), hasLength(1));
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(f.api.calls.where((c) => c == 'view:${feed.postId}'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('short comment uses its natural one-line height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: DefaultTextStyle(
              style: TextStyle(fontSize: 16, height: 1.45),
              child: CommentBody(text: '短评论'),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(SelectableText)).height, lessThan(30));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('detail action semantics include count without visual labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailAction(
            action: FeedAction.like,
            label: '取消点赞',
            count: '12',
            selected: true,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('取消点赞，12'), findsOneWidget);
    expect(find.text('取消点赞'), findsNothing);
    expect(find.text('12'), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'continuous comments load immediately and reply entry stays fixed while scrolling',
    (tester) async {
      final r = await runtime(tester);
      var bodyScrolls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '原帖',
              continuous: true,
              onBodyScroll: () => bodyScrolls++,
              body: const SizedBox(height: 700, child: Text('原帖正文')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('发布你的回复'), findsOneWidget);
      expect(find.text('收起评论'), findsNothing);
      expect(find.text('甲的主评论'), findsOneWidget);
      final entryY = tester.getTopLeft(find.text('发布你的回复')).dy;
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('发布你的回复')).dy, entryY);
      expect(bodyScrolls, greaterThan(0));
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentComposer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'feed comment opens direct composer without detail or view registration; cancel retains draft',
    (tester) async {
      final f = await interactions.fixture();
      addTearDown(f.dispose);
      final r = await runtime(tester);
      await tester.pumpWidget(CommentScope(runtime: r, child: feed.screen(f)));
      await tester.pumpAndSettle();
      final before = List<String>.of(f.api.calls);
      await tester.tap(find.byKey(const ValueKey('comment:${feed.postId}')));
      await tester.pumpAndSettle();
      expect(find.byType(QuickReplyDialog), findsOneWidget);
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(
        tester
            .widget<QuickReplyDialog>(find.byType(QuickReplyDialog))
            .targetName,
        feed.author.nickname,
      );
      expect(f.api.calls, before);
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '列表中的未发送文字',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('收起回复'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment:${feed.postId}')));
      await tester.pumpAndSettle();
      expect(find.text('列表中的未发送文字'), findsOneWidget);
      expect(r.transportFake.sent, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'quick reply journals exact root target, returns to feed and refreshes published count',
    (tester) async {
      final f = await interactions.fixture();
      addTearDown(f.dispose);
      final r = await runtime(tester);
      r.transportFake.publishedId = root;
      r.transportFake.onExecute = () =>
          interactions.api(f).actual = interactions.summary(comments: 9);
      await tester.pumpWidget(CommentScope(runtime: r, child: feed.screen(f)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment:${feed.postId}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '直接从列表真实提交',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      expect(find.byType(QuickReplyDialog), findsNothing);
      final sent = r.transportFake.sent!;
      expect(sent.binding.postId, feed.postId);
      expect(sent.binding.identityId, identity);
      expect(sent.binding.rootCommentId, isNull);
      expect(sent.binding.targetCommentId, isNull);
      expect(
        (r.journal as _MemoryJournal).writes.first.content!.body,
        '直接从列表真实提交',
      );
      expect((await r.journal.read(account)), isEmpty);
      expect(f.controller.interaction(feed.postId).value!.commentCount, 9);
      expect(find.byType(PostDetailScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first quick reply selects identity without publishing on selection',
    (tester) async {
      final r = await runtime(tester, bound: false);
      final editor = CommentEditor(CommentTarget(postId: post));
      await launch(tester, r, editor);
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '选择身份后再明确回复',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      expect(find.text('选择发言身份'), findsOneWidget);
      await tester.tap(find.text('固定身份'));
      await tester.pumpAndSettle();
      expect(r.transportFake.sent, isNull);
      expect(find.text('以 固定身份 回复'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      expect(r.transportFake.sent!.binding.identityId, identity);
      expect(find.byType(QuickReplyDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing bound identity is explained and cannot silently switch identity or send',
    (tester) async {
      final r = await runtime(tester);
      r.hideIdentity = true;
      final editor = CommentEditor(CommentTarget(postId: post));
      await launch(tester, r, editor);
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '绑定身份已被删除',
      );
      await tester.pump();
      expect(find.text('帖内身份已不可用，无法继续回复。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('reply-send')))
            .onPressed,
        isNull,
      );
      expect(r.transportFake.sent, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account retirement closes both quick reply and identity picker and clears input',
    (tester) async {
      final r = await runtime(tester, bound: false);
      final editor = CommentEditor(CommentTarget(postId: post));
      await launch(tester, r, editor);
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '旧账号私有输入',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      r.retire();
      await tester.pumpAndSettle();
      expect(find.byType(QuickReplyDialog), findsNothing);
      expect(find.text('选择发言身份'), findsNothing);
      expect(editor.hasInput, false);
      expect(r.transportFake.sent, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'journal failure retains quick reply and cannot issue a network command',
    (tester) async {
      final r = await runtime(tester);
      (r.journal as _MemoryJournal).failWrite = true;
      final editor = CommentEditor(CommentTarget(postId: post));
      await launch(tester, r, editor);
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '存储失败仍保留',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      expect(find.text('存储失败仍保留'), findsOneWidget);
      expect(find.textContaining('尚未发送'), findsOneWidget);
      expect(r.transportFake.sent, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'quick reply fits small screen with keyboard and 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final controller = TextEditingController(text: '大字与键盘下仍能回复');
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: QuickReplyDialog(
              targetName: '很长的中文发帖人名字',
              controller: controller,
              onReply: () => pressed = true,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('reply-send')));
      await tester.tap(
        find.byKey(const ValueKey('reply-send')),
        warnIfMissed: true,
      );
      expect(pressed, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

class _ReportApi implements GovernanceApi {
  @override
  Future<GovernanceResponse> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async => GovernanceResponse({
    'items': <Object>[],
    'nextBefore': null,
  }, identityTestRenewed);
}
