import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  Completer<void>? identityGate;
  final contextReads = <Completer<Map<String, dynamic>>>[];
  List<ManagedIdentity> extraIdentities = [];
  String? removed;
  Object? loadFailure;
  Object? replyFailure;
  Object? locationFailure;
  Completer<void>? locationGate;
  final replyRequests = <String>[];
  Object? singleFailure;
  int locationRequests = 0;
  final commentQueries = <Map<String, String>?>[];
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
  Future<Map<String, dynamic>> contextFor(String _) async {
    if (contextReads.isNotEmpty) return contextReads.removeAt(0).future;
    return {
      'boundIdentityId': bound ? identity : null,
      'ownCommentIds': ownIds,
      'totalCount': 2,
    };
  }

  @override
  Future<IdentityDirectory> directory() async {
    await identityGate?.future;
    return IdentityDirectory(
      identities: [
        ...extraIdentities,
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
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    dynamic bytes,
    String? mime,
  }) async {
    if (path.endsWith('/comments')) commentQueries.add(query);
    if (path.endsWith('/comments') && pageGate != null) await pageGate!.future;
    if (loadFailure != null) throw loadFailure!;
    if (path.endsWith('/replies')) replyRequests.add(path);
    if (path.endsWith('/replies') && replyFailure != null) throw replyFailure!;
    if (path.endsWith('/location')) {
      locationRequests++;
      await locationGate?.future;
      if (locationFailure != null) throw locationFailure!;
      return {'cursor': 'location'};
    }
    final single = rootRows
        .where((r) => path.endsWith('/${r['id']}'))
        .firstOrNull;
    if (single != null) {
      if (singleFailure != null) throw singleFailure!;
      return single;
    }
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
  detailReferenceTests();
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

  testWidgets('real continuous detail registers a visible body once', (
    tester,
  ) async {
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
    await tester.drag(
      find
          .descendant(
            of: find.byType(CommentPostPane),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -300),
    );
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
      expect(r.commentQueries, isNotEmpty);
      final entryY = tester.getTopLeft(find.text('发布你的回复')).dy;
      await tester.drag(
        find
            .descendant(
              of: find.byType(CommentPostPane),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('发布你的回复')).dy, entryY);
      expect(bodyScrolls, greaterThan(0));
      expect(find.text('甲的主评论'), findsOneWidget);
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

class _GifPicker implements PostPhotoPicker {
  _GifPicker(this.bytes);
  final Uint8List bytes;
  int calls = 0;
  @override
  Future<List<PostPickedFile>> pick(int limit) async {
    calls++;
    return [
      PostPickedFile(
        length: () async => bytes.length,
        openRead: () => Stream.value(bytes),
      ),
    ];
  }

  @override
  Future<void> discardUnboundLostSelection() async {}
}

class _CancelPicker implements PostPhotoPicker {
  final result = Completer<List<PostPickedFile>>();
  @override
  Future<List<PostPickedFile>> pick(int limit) => result.future;
  @override
  Future<void> discardUnboundLostSelection() async {}
}

void detailReferenceTests() {
  Future<_Runtime> runtime(WidgetTester tester) async {
    final r = _Runtime(_MemoryJournal());
    await r.core.activate(account);
    addTearDown(() {
      r.core.dispose();
      r.dispose();
    });
    return r;
  }

  Future<void> openOptimistic(
    WidgetTester tester,
    _Runtime r, {
    ValueChanged<int>? onTotal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentPostPane(
            runtime: r,
            postId: post,
            postBody: '正文',
            continuous: true,
            body: const Text('正文'),
            onTotalChanged: onTotal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'submission is first before any network result with no sending label',
    (tester) async {
      final r = await runtime(tester);
      final counts = <int>[];
      await openOptimistic(tester, r, onTotal: counts.add);
      r.transportFake.pending = Completer<CommentTask>();
      final send = r.core.submit(
        taskId: reply,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '立即出现在第一条'),
      );
      await tester.pumpAndSettle();
      expect(find.text('立即出现在第一条'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('立即出现在第一条')).dy,
        lessThan(tester.getTopLeft(find.text('甲的主评论')).dy),
      );
      expect(find.textContaining('发送中'), findsNothing);
      expect(find.text('正在发送评论…'), findsNothing);
      expect(counts.last, 3);
      r.transportFake.pending!.complete(
        CommentTask(
          taskId: reply,
          binding: r.transportFake.sent!.binding,
          attemptVersion: 1,
          state: CommentTaskState.accepted,
          contentAvailable: true,
          canRetry: false,
          canAbandon: false,
        ),
      );
      await send;
      await tester.pumpAndSettle();
      expect(find.text('立即出现在第一条'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'published result replaces first row once without success action',
    (tester) async {
      final r = await runtime(tester);
      final counts = <int>[];
      await openOptimistic(tester, r, onTotal: counts.add);
      r.transportFake.pending = Completer<CommentTask>();
      final send = r.core.submit(
        taskId: reply,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '保持第一条'),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('保持第一条')).dy;
      r.rootRows.add(row(reply, '保持第一条')..['replyCount'] = 0);
      r.ownIds.add(reply);
      r.transportFake.pending!.complete(
        CommentTask(
          taskId: reply,
          binding: r.transportFake.sent!.binding,
          attemptVersion: 1,
          state: CommentTaskState.published,
          commentId: reply,
          contentAvailable: false,
          canRetry: false,
          canAbandon: false,
        ),
      );
      await send;
      await tester.pumpAndSettle();
      expect(find.text('保持第一条'), findsOneWidget);
      expect(tester.getTopLeft(find.text('保持第一条')).dy, closeTo(before, 2));
      expect(
        tester.getTopLeft(find.text('保持第一条')).dy,
        lessThan(tester.getTopLeft(find.text('甲的主评论')).dy),
      );
      expect(find.text('评论已发送，点击刷新查看'), findsNothing);
      expect(find.text('正在发送评论…'), findsNothing);
      expect(counts.last, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmed failure removes local row and reminds with original material retained',
    (tester) async {
      final r = await runtime(tester);
      await openOptimistic(tester, r);
      r.transportFake.pending = Completer<CommentTask>();
      final send = r.core.submit(
        taskId: reply,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '失败保留的原文'),
      );
      await tester.pumpAndSettle();
      expect(find.text('失败保留的原文'), findsOneWidget);
      r.transportFake.pending!.complete(
        CommentTask(
          taskId: reply,
          binding: r.transportFake.sent!.binding,
          attemptVersion: 1,
          state: CommentTaskState.failed,
          failureCode: 'PUBLICATION_FAILED',
          contentAvailable: true,
          canRetry: true,
          canAbandon: true,
        ),
      );
      await send;
      await tester.pumpAndSettle();
      expect(find.text('失败保留的原文'), findsNothing);
      expect(find.text('评论发送失败，可在系统消息中重试。'), findsOneWidget);
      expect(r.core.failures.single.content!.body, '失败保留的原文');
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unknown transport keeps one local row without inventing failure',
    (tester) async {
      final r = await runtime(tester);
      await openOptimistic(tester, r);
      r.transportFake.executeFailure = const CommentHttpFailure(
        null,
        'TIMEOUT',
      );
      await r.core.submit(
        taskId: reply,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '等待原任务核对'),
      );
      await tester.pumpAndSettle();
      expect(find.text('等待原任务核对'), findsOneWidget);
      expect(find.byKey(const ValueKey('comment-notice')), findsNothing);
      expect(find.textContaining('发送中'), findsNothing);
      expect(r.core.entries.single.transport, CommentTransportState.unknown);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed local persistence neither inserts a row nor calls network',
    (tester) async {
      final r = await runtime(tester);
      await openOptimistic(tester, r);
      (r.journal as _MemoryJournal).failWrite = true;
      await expectLater(
        r.core.submit(
          taskId: reply,
          commandId: commentKey(),
          binding: CommentBinding(postId: post, identityId: identity),
          content: CommentContent(body: '存储失败不冒充已提交'),
        ),
        throwsStateError,
      );
      await tester.pumpAndSettle();
      expect(find.text('存储失败不冒充已提交'), findsNothing);
      expect(r.transportFake.sent, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inline identity stays visible while revalidating and survives collapse',
    (tester) async {
      final r = await runtime(tester);
      r.bound = false;
      r.extraIdentities = [
        ManagedIdentity(
          id: reply,
          nickname: '原始身份',
          avatar: 'default-v1',
          isOriginal: true,
          createdAt: DateTime.utc(2026),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      r.identityGate = Completer<void>();
      await tester.tap(find.text('发布你的回复'));
      await tester.pump();
      DetailAvatar avatar() => tester.widget<DetailAvatar>(
        find.descendant(
          of: find.byTooltip('发言身份'),
          matching: find.byType(DetailAvatar),
        ),
      );
      expect(avatar().name, '原始身份');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '回复'))
            .onPressed,
        isNull,
      );
      r.identityGate!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发言身份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('固定身份'));
      await tester.pumpAndSettle();
      expect(avatar().name, '固定身份');
      await tester.tap(find.byTooltip('展开回复输入'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('收起回复'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      expect(avatar().name, '固定身份');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final withDraft in [false, true]) {
    testWidgets('cancel gallery restores collapsed dock withDraft=$withDraft', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      final r = await runtime(tester);
      final picker = _CancelPicker();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              photoPicker: picker,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (withDraft) {
        await tester.tap(find.text('发布你的回复'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('inline-comment-input')),
          '保留草稿',
        );
        await tester.pumpAndSettle();
        final avatar = tester.getRect(find.byTooltip('发言身份'));
        final toolbar = tester.getRect(find.byTooltip('选择一张图片'));
        expect(avatar.bottom, lessThanOrEqualTo(toolbar.top));
      }
      await tester.tap(find.byTooltip('选择一张图片'));
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.pump();
      picker.result.complete([]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inline-comment-input')), findsNothing);
      expect(find.text(withDraft ? '继续输入' : '发布你的回复'), findsOneWidget);
      expect(find.byTooltip('选择 GIF'), findsNothing);
      if (withDraft) {
        await tester.tap(find.text('继续输入'));
        await tester.pumpAndSettle();
        expect(find.text('保留草稿'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'reopening a post does not replay historical publication or toast over input',
    (tester) async {
      final r = await runtime(tester);
      r.transportFake.publishedId = root;
      await r.core.submit(
        taskId: root,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '历史评论'),
      );
      r.locationFailure = const CommentHttpFailure(404, 'NOT_FOUND');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      r.notifyListeners();
      await tester.pumpAndSettle();
      expect(r.locationRequests, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.byKey(const ValueKey('inline-comment-input')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final status in [403, 404]) {
    testWidgets(
      'explicit unavailable location $status does not claim deletion',
      (tester) async {
        final r = await runtime(tester);
        r.locationFailure = CommentHttpFailure(status, 'NOT_FOUND');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CommentPostPane(
                runtime: r,
                postId: post,
                postBody: '正文',
                continuous: true,
                initialCommentId: root,
                body: const Text('正文'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('评论已经删除'), findsNothing);
        expect(find.text('这条评论暂时无法查看。'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('failed location never covers composer at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final r = await runtime(tester);
      r.locationGate = Completer<void>();
      r.locationFailure = const CommentHttpFailure(500, 'TEMPORARY_FAILURE');
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              initialCommentId: root,
              overlayComposer: true,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('inline-comment-input')),
        '保留草稿',
      );
      r.locationGate!.complete();
      await tester.pumpAndSettle();
      for (final keyboard in [0.0, 280.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();
        expect(find.text('暂时无法定位，请重试。'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        final notice = tester.getRect(
          find.byKey(const ValueKey('comment-notice')),
        );
        for (final action in [
          find.byTooltip('选择一张图片'),
          find.widgetWithText(FilledButton, '回复'),
        ]) {
          expect(action.hitTestable(), findsOneWidget);
          expect(notice.overlaps(tester.getRect(action)), isFalse);
          expect(
            tester.getRect(action).bottom,
            lessThanOrEqualTo(800 - keyboard),
          );
        }
        expect(find.text('保留草稿'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('展开回复输入'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('选择一张图片').hitTestable(), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, '回复').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comment-notice')), findsNothing);
      expect(find.text('保留草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'keyboard moves the composer without resizing or scrolling the reading viewport',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final r = await runtime(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              overlayComposer: true,
              body: const SizedBox(
                key: ValueKey('measured-body'),
                height: 900,
                child: Text('正文'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getSize(find.byType(ListView));
      final bodyY = tester
          .getTopLeft(find.byKey(const ValueKey('measured-body')))
          .dy;
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      for (final inset in [120.0, 200.0, 280.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        expect(tester.getSize(find.byType(ListView)), viewport);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('measured-body'))).dy,
          bodyY,
        );
        expect(
          tester.getBottomLeft(find.byType(CommentComposer)).dy,
          closeTo(800 - inset, .1),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('选择一张图片').hitTestable(), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, '回复').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offscreen reply previews do not block the page or issue one request per row',
    (tester) async {
      final r = await runtime(tester);
      r.replyFailure = const CommentHttpFailure(500, 'TEMPORARY_FAILURE');
      r.rootRows = [
        for (var i = 1; i <= 40; i++)
          row(
            '77777777-7777-4777-8777-${i.toString().padLeft(12, '0')}',
            '评论$i',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const SizedBox(height: 1600, child: Text('正文')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(r.replyRequests, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(r.replyRequests.length, inInclusiveRange(1, 15));
      expect(find.text('回复暂时无法读取，请重试。'), findsOneWidget);
      expect(find.byTooltip('选择一张图片').hitTestable(), findsOneWidget);
      expect(find.text('重试回复'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'long continuous thread lays out only nearby rows and locates a distant row',
    (tester) async {
      final r = await runtime(tester);
      r.rootRows = [
        for (var i = 1; i <= 100; i++)
          row(
            '77777777-7777-4777-8777-${i.toString().padLeft(12, '0')}',
            '评论$i',
          )..['replyCount'] = 0,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommentBody).evaluate().length, lessThan(20));
      expect(find.text('评论100'), findsNothing);
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentBody).evaluate().length, lessThan(20));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              initialCommentId: r.rootRows[79]['id'] as String,
              body: const SizedBox(height: 900, child: Text('正文')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('评论80').hitTestable(), findsOneWidget);
      expect(find.byType(CommentBody).evaluate().length, lessThan(25));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'comment reads start while detail is pending without enabling premature input',
    (tester) async {
      final f = await interactions.fixture();
      addTearDown(f.dispose);
      final r = await runtime(tester);
      await tester.pumpWidget(CommentScope(runtime: r, child: feed.screen(f)));
      await tester.pumpAndSettle();
      f.api.detailWait = Completer<PostResponse<PostDetail>>();
      await tester.tap(find.text(feed.post().title).first);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(r.commentQueries, hasLength(1));
      await tester.tap(find.text('发布你的回复'));
      await tester.pump();
      expect(find.byType(CommentComposer), findsNothing);
      final p = feed.post();
      f.api.detailWait!.complete(
        feed.reply(
          PostDetail(
            postId: p.postId,
            channelId: p.channelId,
            title: p.title,
            body: p.body,
            author: p.author,
            publishedAt: p.publishedAt,
            imageCount: p.imageCount,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(r.commentQueries, hasLength(1));
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentComposer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'background publication location failure never interrupts input',
    (tester) async {
      final r = await runtime(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('inline-comment-input')),
        '继续输入',
      );
      r.singleFailure = const CommentHttpFailure(404, 'NOT_FOUND');
      r.transportFake.publishedId = root;
      await r.core.submit(
        taskId: root,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '此前提交'),
      );
      await tester.pumpAndSettle();
      expect(r.locationRequests, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('继续输入'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'published comment appears in the open list without location lookup',
    (tester) async {
      final r = await runtime(tester);
      r.rootRows = [];
      final counts = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
              onTotalChanged: counts.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      r.transportFake.pending = Completer<CommentTask>();
      final sent = r.core.submit(
        taskId: root,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '新发评论'),
      );
      await tester.pumpAndSettle();
      expect(find.text('正在发送评论…'), findsNothing);
      expect(find.text('新发评论'), findsOneWidget);
      expect(find.text('暂无评论'), findsNothing);
      r.rootRows = [row(root, '新发评论')..['replyCount'] = 0];
      r.locationFailure = const CommentHttpFailure(404, 'NOT_FOUND');
      r.transportFake.pending!.complete(
        CommentTask(
          taskId: root,
          binding: CommentBinding(postId: post, identityId: identity),
          attemptVersion: 1,
          state: CommentTaskState.published,
          commentId: root,
          contentAvailable: false,
          canRetry: false,
          canAbandon: false,
        ),
      );
      await sent;
      await tester.pumpAndSettle();
      expect(find.text('新发评论'), findsOneWidget);
      expect(counts.last, 2);
      expect(find.text('正在发送评论…'), findsNothing);
      expect(r.locationRequests, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late context from before publication cannot regress count or ownership',
    (tester) async {
      final r = await runtime(tester);
      final oldContext = Completer<Map<String, dynamic>>();
      r.contextReads.add(oldContext);
      r.rootRows = [row(root, '新发评论')..['replyCount'] = 0];
      final counts = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
              onTotalChanged: counts.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      r.ownIds.add(root);
      r.transportFake.publishedId = root;
      await r.core.submit(
        taskId: root,
        commandId: commentKey(),
        binding: CommentBinding(postId: post, identityId: identity),
        content: CommentContent(body: '新发评论'),
      );
      await tester.pumpAndSettle();
      expect(counts.last, 2);
      oldContext.complete({
        'boundIdentityId': null,
        'ownCommentIds': <String>[],
        'totalCount': 0,
      });
      await tester.pumpAndSettle();
      expect(counts.last, 2);
      await tester.tap(find.byTooltip('评论操作'));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reference composer and sort fit a small screen with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final r = await runtime(tester);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('相关'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('最近'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('inline-comment-input')),
        '大字号输入不会溢出',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('展开回复输入').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('展开回复输入'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('缩小回复输入'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reference sort sheet requests fresh server ordering and keeps input draft',
    (tester) async {
      final r = await runtime(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('正文与操作栏'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('相关'), findsOneWidget);
      expect(find.byTooltip('选择 GIF'), findsNothing);
      await tester.tap(find.text('相关'));
      await tester.pumpAndSettle();
      expect(find.text('对回复排序'), findsOneWidget);
      for (final label in ['最近', '最相关', '最多点赞']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('最近'));
      await tester.pumpAndSettle();
      expect(r.commentQueries.last, {'sort': 'recent'});
      await tester.tap(find.text('最近'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最多点赞'));
      await tester.pumpAndSettle();
      expect(r.commentQueries.last, {'sort': 'likes'});
      await tester.tap(find.text('发布你的回复'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('inline-comment-input'));
      await tester.enterText(input, '保留这条草稿');
      await tester.tap(find.byTooltip('展开回复输入'));
      await tester.pumpAndSettle();
      expect(find.text('保留这条草稿'), findsOneWidget);
      await tester.tap(find.byTooltip('收起回复'));
      await tester.pumpAndSettle();
      expect(find.text('继续输入'), findsOneWidget);
      await tester.tap(find.text('继续输入'));
      await tester.pumpAndSettle();
      expect(find.text('保留这条草稿'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('继续输入'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inline reply keeps concrete target and journals without popping the post',
    (tester) async {
      final r = await runtime(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentPostPane(
              runtime: r,
              postId: post,
              postBody: '正文',
              continuous: true,
              body: const Text('原帖仍在'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('乙回复甲的具体内容'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('inline-comment-input')),
        '对具体回复继续回复',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '回复'));
      await tester.pumpAndSettle();
      expect(r.transportFake.sent!.binding.targetCommentId, reply);
      expect(r.transportFake.sent!.binding.rootCommentId, root);
      expect(find.text('原帖仍在'), findsOneWidget);
      expect(find.byKey(const ValueKey('inline-comment-input')), findsNothing);
      expect(find.text('发布你的回复'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'image button selects previews removes and submits original GIF',
    (tester) async {
      final r = await runtime(tester);
      final data = jsonDecode(
        File('test/fixtures/post-media-v1.json').readAsStringSync(),
      ) as Map;
      final bytes = base64Decode(data['originalBase64']);
      final picker = _GifPicker(bytes);
      final originals = <String, Uint8List>{};
      final editor = CommentEditor(CommentTarget(postId: post));
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 260,
              child: CommentComposer(
                runtime: r,
                editor: editor,
                originals: originals,
                contextText: '正文',
                docked: true,
                photoPicker: picker,
                onSubmitted: () => submitted = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('选择一张图片'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(picker.calls, 1);
      expect(editor.image!.selection.mimeType, 'image/gif');
      expect(find.byTooltip('移除图片'), findsOneWidget);
      await tester.tap(find.byTooltip('移除图片'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(editor.image, isNull);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('选择一张图片'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '回复'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(submitted, isTrue);
      expect(
        r.transportFake.sent!.content!.image!.selection.mimeType,
        'image/gif',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
