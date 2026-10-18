import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/comments/comment_api.dart';
import 'package:hnuhole_mobile/src/comments/comment_controller.dart';
import 'package:hnuhole_mobile/src/comments/comment_editor.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/comments/comment_order.dart';
import 'package:hnuhole_mobile/src/posts/post_upload_models.dart';

String _id(int value) =>
    '11111111-1111-4111-8111-${value.toRadixString(16).padLeft(12, '0')}';
const _command = 'AQEBAQEBAQEBAQEBAQEBAQ';
const _retryCommand = 'AgICAgICAgICAgICAgICAg';
const _abandonCommand = 'AwMDAwMDAwMDAwMDAwMDAw';
final _account = _id(1), _post = _id(2), _identity = _id(3), _task = _id(4);
CommentBinding _binding({bool reply = true}) => CommentBinding(
  postId: _post,
  identityId: _identity,
  rootCommentId: reply ? _id(5) : null,
  targetCommentId: reply ? _id(6) : null,
);
CommentContent _content([String body = '原文']) => CommentContent(body: body);
CommentTask _snapshot(
  CommentIntent intent, {
  CommentTaskState state = CommentTaskState.accepted,
  int? version,
  CommentBinding? binding,
}) => CommentTask(
  taskId: intent.taskId,
  binding: binding ?? intent.binding,
  attemptVersion:
      version ??
      (intent.operation == CommentOperation.retry
          ? intent.expectedAttemptVersion! + 1
          : intent.expectedAttemptVersion ?? 1),
  state: state,
  contentAvailable: state != CommentTaskState.abandoned,
  canRetry: state == CommentTaskState.failed,
  canAbandon: state == CommentTaskState.failed,
  commentId: state == CommentTaskState.published ? _id(7) : null,
  failureCode: state == CommentTaskState.failed ? 'PUBLICATION_FAILED' : null,
);
CommentImage _image() => CommentImage(
  blobId: _id(30),
  selection: PostImageSelection.fromJson({
    'mediaId': _id(31),
    'sha256': 'a' * 64,
    'byteLength': 10,
    'mimeType': 'image/png',
    'width': 1,
    'height': 1,
  }),
);

/// Explicit in-memory test adapter; this does not prove native persistence,
/// encrypted blob durability or app-process recovery on a device.
class MemoryCommentJournalTestAdapter implements CommentJournal {
  final data = <String, Map<String, CommentJournalEntry>>{};
  final events = <String>[];
  bool failWrites = false;
  bool failRemoves = false;
  Completer<void>? blockWrite;
  Completer<void>? blockRead;
  Completer<void>? blockRemove;
  @override
  Future<void> put(String accountId, CommentJournalEntry entry) async {
    events.add('put:start');
    if (failWrites) throw StateError('Synthetic storage failure');
    await blockWrite?.future;
    (data[accountId] ??= {})[entry.localId] = entry;
    events.add('put:done');
  }

  @override
  Future<List<CommentJournalEntry>> read(String accountId) async {
    await blockRead?.future;
    return data[accountId]?.values.toList() ?? [];
  }

  @override
  Future<void> remove(String accountId, String localId) async {
    if (failRemoves) throw StateError('Synthetic deletion failure');
    await blockRemove?.future;
    data[accountId]?.remove(localId);
    events.add('remove');
  }
}

class _Api implements CommentApi {
  final sent = <CommentIntent>[];
  final queried = <CommentIntent>[];
  Future<CommentTask> Function(CommentIntent)? onExecute;
  Future<CommentTask?> Function(CommentIntent)? onQuery;
  Future<CommentTask?> Function(String, CommentBinding)? onQueryTask;
  int taskQueries = 0;
  @override
  Future<CommentTask> execute(CommentIntent intent) async {
    sent.add(intent);
    return onExecute == null ? _snapshot(intent) : await onExecute!(intent);
  }

  @override
  Future<CommentTask?> query(CommentIntent intent) async {
    queried.add(intent);
    return onQuery == null ? null : await onQuery!(intent);
  }

  @override
  Future<CommentTask?> queryTask({
    required String taskId,
    required CommentBinding binding,
  }) async {
    taskQueries++;
    return await onQueryTask?.call(taskId, binding);
  }
}

void main() {
  group('temporary input and single image', () {
    test('collapse preserves, leaving clears and closes input', () {
      final editor = CommentEditor(CommentTarget(postId: _post))
        ..body = '未提交'
        ..setImage(_image());
      editor.collapse();
      expect(editor.body, '未提交');
      expect(editor.image, isNotNull);
      editor.expand();
      editor.leave();
      expect(editor.body, isEmpty);
      expect(editor.image, isNull);
      expect(editor.target.commentId, isNull);
      expect(editor.open, isFalse);
      expect(() => editor.content(), throwsStateError);
    });

    test(
      'switch with content requires explicit confirmation and keeps input',
      () async {
        final original = CommentTarget(
          postId: _post,
          rootCommentId: _id(5),
          commentId: _id(6),
        );
        final next = CommentTarget(
          postId: _post,
          rootCommentId: _id(5),
          commentId: _id(8),
        );
        final editor = CommentEditor(original)..body = '保留文字';
        expect(
          await editor.switchTarget(next, confirm: (_) async => false),
          isFalse,
        );
        expect(editor.target, same(original));
        expect(
          await editor.switchTarget(next, confirm: (_) async => true),
          isTrue,
        );
        expect(editor.target, same(next));
        expect(editor.body, '保留文字');
      },
    );

    test(
      'an outstanding target confirmation cannot restore input after leaving',
      () async {
        final editor = CommentEditor(CommentTarget(postId: _post))..body = '文字';
        final approval = Completer<bool>();
        final pending = editor.switchTarget(
          CommentTarget(
            postId: _post,
            rootCommentId: _id(5),
            commentId: _id(6),
          ),
          confirm: (_) => approval.future,
        );
        editor.leave();
        approval.complete(true);
        expect(await pending, isFalse);
        expect(editor.target.commentId, isNull);
      },
    );

    test('cross-post transfer is rejected without asking', () async {
      final editor = CommentEditor(CommentTarget(postId: _post))..body = '文字';
      expect(
        await editor.switchTarget(
          CommentTarget(postId: _id(99)),
          confirm: (_) async => throw StateError('Must not ask'),
        ),
        isFalse,
      );
    });

    test(
      'read failure retains text and target until image removed or replaced',
      () {
        final target = CommentTarget(
          postId: _post,
          rootCommentId: _id(5),
          commentId: _id(6),
        );
        final editor = CommentEditor(target)
          ..body = '保留'
          ..setImage(_image())
          ..imageFailed = true;
        expect(() => editor.content(), throwsStateError);
        editor.setImage(null);
        expect(editor.content().body, '保留');
        expect(editor.target, same(target));
        editor.body = '';
        expect(() => editor.content(), throwsFormatException);
        editor.setImage(_image());
        expect(editor.content().body, isEmpty);
      },
    );

    test('content reuses frozen Unicode grapheme and scalar rules', () {
      expect(_content('👩‍💻' * 3000).body, isNotEmpty);
      expect(() => _content('👨‍👩‍👧‍👦' * 3000), throwsFormatException);
      expect(() => _content('字' * 3001), throwsFormatException);
      expect(() => _content('\ud800'), throwsFormatException);
      expect(() => _content('\u200b \t'), throwsFormatException);
      expect(() => _content('a\u0000b'), throwsFormatException);
    });
  });

  group('durable intent and authoritative task state', () {
    late _Api api;
    late MemoryCommentJournalTestAdapter journal;
    late CommentController controller;
    Future<void> submit() => controller.submit(
      taskId: _task,
      commandId: _command,
      binding: _binding(),
      content: _content(),
    );
    setUp(() async {
      api = _Api();
      journal = MemoryCommentJournalTestAdapter();
      controller = CommentController(api: api, journal: journal);
      await controller.activate(_account);
    });
    tearDown(() => controller.dispose());

    test('does not send before the journal confirms durable save', () async {
      journal.blockWrite = Completer<void>();
      final pending = submit();
      await Future<void>.delayed(Duration.zero);
      expect(api.sent, isEmpty);
      journal.blockWrite!.complete();
      await pending;
      expect(api.sent, hasLength(1));
      expect(journal.events.take(2), ['put:start', 'put:done']);
      expect(controller.entries.single.task!.state, CommentTaskState.accepted);
    });

    test('save failure never sends or pretends to be accepted', () async {
      journal.failWrites = true;
      await expectLater(submit(), throwsStateError);
      expect(api.sent, isEmpty);
      expect(controller.entries, isEmpty);
    });

    test(
      'different tasks reserve the command before the first storage await',
      () async {
        journal.blockWrite = Completer<void>();
        final first = submit();
        await expectLater(
          controller.submit(
            taskId: _id(80),
            commandId: _command,
            binding: _binding(),
            content: _content(),
          ),
          throwsStateError,
        );
        journal.blockWrite!.complete();
        await first;
        expect(api.sent, hasLength(1));
        expect(await journal.read(_account), hasLength(1));
      },
    );

    test(
      'journal restoration validates all entries before exposing any task',
      () async {
        final intent = CommentIntent(
          commandId: _command,
          taskId: _task,
          operation: CommentOperation.create,
          binding: _binding(),
          content: _content(),
        );
        journal.data[_account] = {
          _task: CommentJournalEntry(
            localId: _task,
            intent: intent,
            transport: CommentTransportState.unknown,
          ),
          _id(80): CommentJournalEntry(
            localId: _id(80),
            intent: intent,
            transport: CommentTransportState.unknown,
          ),
        };
        await expectLater(controller.activate(_account), throwsFormatException);
        expect(controller.entries, isEmpty);
        expect(controller.ready, isFalse);
        expect(api.queried, isEmpty);
      },
    );

    test(
      'journal restoration rejects command reuse across distinct tasks',
      () async {
        CommentJournalEntry entry(String task) => CommentJournalEntry(
          localId: task,
          intent: CommentIntent(
            commandId: _command,
            taskId: task,
            operation: CommentOperation.create,
            binding: _binding(),
            content: _content(),
          ),
          transport: CommentTransportState.unknown,
        );
        journal.data[_account] = {_task: entry(_task), _id(80): entry(_id(80))};
        await expectLater(controller.activate(_account), throwsFormatException);
        expect(controller.entries, isEmpty);
        expect(api.queried, isEmpty);
      },
    );

    test(
      'mutations cannot overwrite unknown tasks while the journal is loading',
      () async {
        journal.blockRead = Completer<void>();
        final loading = controller.activate(_account);
        await expectLater(submit(), throwsStateError);
        journal.blockRead!.complete();
        await loading;
        expect(api.sent, isEmpty);
        expect(controller.ready, isTrue);
      },
    );

    test(
      'a stale ACCEPTED read cannot regress a confirmed FAILED attempt',
      () async {
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await submit();
        api.onQuery = (intent) async => _snapshot(intent);
        await controller.reconcile(_task);
        expect(controller.entries.single.task!.state, CommentTaskState.failed);
        expect(controller.failures, hasLength(1));
      },
    );

    test('rejected CREATE does not invent a server FAILED task and releases only into its open post', () async {
      api.onExecute = (_) async =>
          throw CommentCommandRejected('COMMENT_TARGET_UNAVAILABLE');
      await submit();
      expect(controller.entries.single.task, isNull);
      expect(
        controller.entries.single.rejectionCode,
        'COMMENT_TARGET_UNAVAILABLE',
      );
      expect(controller.failures, isEmpty);
      await expectLater(
        controller.releaseRejected(localId: _task, activePostId: _id(80)),
        throwsStateError,
      );
      await expectLater(
        controller.submit(
          taskId: _id(80),
          commandId: _retryCommand,
          binding: _binding(),
          content: _content(),
        ),
        throwsStateError,
      );
      final input = await controller.releaseRejected(
        localId: _task,
        activePostId: _post,
      );
      expect(input!.content.body, '原文');
      expect(input.binding.targetCommentId, _id(6));
      expect(controller.entries, isEmpty);
      expect(await journal.read(_account), isEmpty);
      expect(api.sent, hasLength(1));
    });

    test('deleting an identity while rejected input is releasing never revives its payload', () async {
      api.onExecute = (_) async =>
          throw CommentCommandRejected('COMMAND_SEALED');
      await submit();
      journal.blockRemove = Completer<void>();
      final releasing = controller.releaseRejected(
        localId: _task,
        activePostId: _post,
      );
      await Future<void>.delayed(Duration.zero);
      final deleting = controller.identityDeleted(_identity);
      expect(controller.entries, isEmpty);
      journal.blockRemove!.complete();
      expect(await releasing, isNull);
      await deleting;
      expect(await journal.read(_account), isEmpty);
    });

    test('failed journal removal cannot release rejected content or unlock resubmission', () async {
      api.onExecute = (_) async =>
          throw CommentCommandRejected('COMMAND_SEALED');
      await submit();
      journal.failRemoves = true;
      await expectLater(
        controller.releaseRejected(localId: _task, activePostId: _post),
        throwsStateError,
      );
      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.content!.body, '原文');
      expect(api.sent, hasLength(1));
    });

    test(
      'a lost CREATE result can resolve to a checked rejection during recovery',
      () async {
        api.onExecute = (_) async => throw TimeoutException('test');
        await submit();
        api.onQuery = (_) async =>
            throw CommentCommandRejected('COMMAND_SEALED');
        await controller.reconcile(_task);
        expect(
          controller.entries.single.transport,
          CommentTransportState.settled,
        );
        expect(controller.entries.single.task, isNull);
        expect(controller.entries.single.rejectionCode, 'COMMAND_SEALED');
        await controller.activate(_account);
        expect(
          controller.entries.single.transport,
          CommentTransportState.settled,
        );
        expect(api.sent, hasLength(1));
      },
    );

    test('rejected RETRY stays unknown until a fresh current-task query confirms failure', () async {
      api.onExecute = (intent) async =>
          _snapshot(intent, state: CommentTaskState.failed);
      await submit();
      final original = api.sent.single;
      api.onExecute = (_) async =>
          throw CommentCommandRejected('POSTING_RESTRICTED');
      await controller.retry(
        localId: _task,
        commandId: _retryCommand,
        content: _content('改后'),
      );
      expect(api.taskQueries, 1);
      expect(
        controller.entries.single.transport,
        CommentTransportState.unknown,
      );
      expect(controller.failures, isEmpty);
      await expectLater(
        controller.abandon(localId: _task, commandId: _abandonCommand),
        throwsStateError,
      );
      api.onQueryTask = (_, _) async =>
          _snapshot(original, state: CommentTaskState.failed);
      await controller.reconcile(_task);
      expect(
        controller.entries.single.transport,
        CommentTransportState.settled,
      );
      expect(controller.failures, hasLength(1));
      expect(controller.failures.single.content!.body, '改后');
      api.onExecute = (intent) async =>
          _snapshot(intent, state: CommentTaskState.abandoned);
      await controller.abandon(localId: _task, commandId: _abandonCommand);
      expect(controller.entries, isEmpty);
    });

    test(
      'rejected ABANDON reads latest state and preserves the retry content',
      () async {
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await submit();
        final original = api.sent.single;
        api.onExecute = (_) async =>
            throw CommentCommandRejected('TASK_VERSION_CONFLICT');
        api.onQueryTask = (_, _) async =>
            _snapshot(original, state: CommentTaskState.failed);
        await controller.abandon(localId: _task, commandId: _abandonCommand);
        expect(
          controller.entries.single.transport,
          CommentTransportState.settled,
        );
        expect(controller.failures.single.content!.body, '原文');
        expect(api.taskQueries, 1);
      },
    );

    test('a contradictory PUBLISHED read cannot rewrite a failed attempt at the same version', () async {
      api.onExecute = (intent) async =>
          _snapshot(intent, state: CommentTaskState.failed);
      await submit();
      api.onQuery = (intent) async =>
          _snapshot(intent, state: CommentTaskState.published);
      await controller.reconcile(_task);
      expect(controller.failures, hasLength(1));
      expect(controller.entries.single.task!.state, CommentTaskState.failed);
      expect(controller.resolvedTasks, isEmpty);
      expect(await journal.read(_account), hasLength(1));
    });

    test('lost result is UNKNOWN and queries never resend', () async {
      api.onExecute = (_) async => throw TimeoutException('test');
      await submit();
      expect(controller.entries.single.task, isNull);
      expect(
        controller.entries.single.transport,
        CommentTransportState.unknown,
      );
      await controller.reconcile(_task);
      await controller.reconcile(_task);
      expect(api.sent, hasLength(1));
      expect(api.queried, hasLength(2));
      expect(controller.failures, isEmpty);
      await expectLater(
        controller.retry(
          localId: _task,
          commandId: _retryCommand,
          content: _content(),
        ),
        throwsStateError,
      );
      await expectLater(
        controller.abandon(localId: _task, commandId: _abandonCommand),
        throwsStateError,
      );
    });

    test(
      'restart restores the original immutable command and only queries',
      () async {
        api.onExecute = (_) async => throw TimeoutException('test');
        await submit();
        final restoredApi = _Api()
          ..onQuery = (intent) async =>
              _snapshot(intent, state: CommentTaskState.published);
        final restored = CommentController(api: restoredApi, journal: journal);
        await restored.activate(_account);
        expect(restoredApi.sent, isEmpty);
        expect(restoredApi.queried.single.commandId, _command);
        expect(restoredApi.queried.single.taskId, _task);
        expect(restored.resolvedTasks.single.state, CommentTaskState.published);
        expect(await journal.read(_account), isEmpty);
        restored.dispose();
      },
    );

    test('FAILED projection keeps original identity and exact target without resolving on read', () async {
      api.onExecute = (intent) async =>
          _snapshot(intent, state: CommentTaskState.failed);
      await submit();
      final notice = controller.failures.single;
      expect(notice.ownerIdentityId, _identity);
      expect(notice.task.binding.targetCommentId, _id(6));
      expect(notice.content!.body, '原文');
      expect(controller.failures, hasLength(1));
      expect(await journal.read(_account), hasLength(1));
    });

    test(
      'retry edits only content, keeps binding and increments expected version',
      () async {
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await submit();
        api.onExecute = (intent) async => _snapshot(intent);
        await controller.retry(
          localId: _task,
          commandId: _retryCommand,
          content: _content('修改后'),
        );
        final retry = api.sent.last;
        expect(retry.taskId, _task);
        expect(retry.expectedAttemptVersion, 1);
        expect(retry.binding.sameAs(_binding()), isTrue);
        expect(retry.content!.body, '修改后');
        expect(controller.entries.single.task!.attemptVersion, 2);
        expect(controller.failures, isEmpty);
      },
    );

    test(
      'unknown retry does not accept an old FAILED task as retry failure',
      () async {
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await submit();
        api.onExecute = (_) async => throw TimeoutException('test');
        await controller.retry(
          localId: _task,
          commandId: _retryCommand,
          content: _content('修改后'),
        );
        api.onQuery = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed, version: 1);
        await controller.reconcile(_task);
        expect(
          controller.entries.single.transport,
          CommentTransportState.unknown,
        );
        expect(controller.failures, isEmpty);
        expect(api.sent, hasLength(2));
      },
    );

    test('command IDs cannot be reused after multiple retries', () async {
      api.onExecute = (intent) async =>
          _snapshot(intent, state: CommentTaskState.failed);
      await submit();
      await controller.retry(
        localId: _task,
        commandId: _retryCommand,
        content: _content(),
      );
      await expectLater(
        controller.retry(
          localId: _task,
          commandId: _command,
          content: _content(),
        ),
        throwsStateError,
      );
      expect(api.sent, hasLength(2));
    });

    test(
      'abandon is FAILED only and removes journal and failure projection',
      () async {
        await submit();
        await expectLater(
          controller.abandon(localId: _task, commandId: _abandonCommand),
          throwsStateError,
        );
        api.onQuery = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await controller.reconcile(_task);
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.abandoned);
        await controller.abandon(localId: _task, commandId: _abandonCommand);
        expect(controller.failures, isEmpty);
        expect(controller.entries, isEmpty);
        expect(
          controller.resolvedTasks.single.state,
          CommentTaskState.abandoned,
        );
        expect(await journal.read(_account), isEmpty);
      },
    );

    test(
      'unknown abandon keeps querying instead of offering another mutation',
      () async {
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await submit();
        api.onExecute = (_) async => throw TimeoutException('test');
        await controller.abandon(localId: _task, commandId: _abandonCommand);
        api.onQuery = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await controller.reconcile(_task);
        expect(
          controller.entries.single.transport,
          CommentTransportState.unknown,
        );
        expect(controller.entries.single.content!.body, '原文');
        await expectLater(
          controller.retry(
            localId: _task,
            commandId: _retryCommand,
            content: _content(),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'mismatched server identity or exact target is never accepted',
      () async {
        api.onExecute = (intent) async => _snapshot(
          intent,
          binding: CommentBinding(
            postId: _post,
            identityId: _identity,
            rootCommentId: _id(5),
            targetCommentId: _id(8),
          ),
        );
        await submit();
        expect(
          controller.entries.single.transport,
          CommentTransportState.unknown,
        );
        expect(controller.entries.single.task, isNull);
        expect(controller.failures, isEmpty);
      },
    );

    test(
      'account switch fences late results and keeps journals isolated',
      () async {
        final pending = Completer<CommentTask>();
        api.onExecute = (_) => pending.future;
        final sending = submit();
        await Future<void>.delayed(Duration.zero);
        final intent = api.sent.single;
        await controller.activate(_id(100));
        pending.complete(_snapshot(intent, state: CommentTaskState.published));
        await sending;
        expect(controller.entries, isEmpty);
        expect(controller.resolvedTasks, isEmpty);
        expect(await journal.read(_id(100)), isEmpty);
        expect(await journal.read(_account), hasLength(1));
      },
    );

    test(
      'switch while initial save is pending never sends under the new account',
      () async {
        journal.blockWrite = Completer<void>();
        final sending = submit();
        await Future<void>.delayed(Duration.zero);
        final switching = controller.activate(_id(100));
        journal.blockWrite!.complete();
        await sending;
        await switching;
        expect(api.sent, isEmpty);
        expect(controller.entries, isEmpty);
      },
    );

    test(
      'identity deletion clears known failed buffers and prevents retry',
      () async {
        api.onExecute = (intent) async =>
            _snapshot(intent, state: CommentTaskState.failed);
        await submit();
        await controller.identityDeleted(_identity);
        expect(controller.entries, isEmpty);
        expect(controller.failures, isEmpty);
        expect(await journal.read(_account), isEmpty);
        await expectLater(
          controller.retry(
            localId: _task,
            commandId: _retryCommand,
            content: _content(),
          ),
          throwsStateError,
        );
      },
    );

    test('identity deletion drops unknown private payload and retains query metadata', () async {
      api.onExecute = (_) async => throw TimeoutException('test');
      await submit();
      await controller.identityDeleted(_identity);
      final entry = controller.entries.single;
      expect(entry.intent.commandId, _command);
      expect(entry.intent.content, isNull);
      expect(entry.content, isNull);
      expect(entry.identityDeleted, isTrue);
      expect((await journal.read(_account)).single.intent.content, isNull);
      api.onQuery = (intent) async =>
          _snapshot(intent, state: CommentTaskState.published);
      await controller.reconcile(_task);
      expect(controller.resolvedTasks.single.state, CommentTaskState.published);
      expect(await journal.read(_account), isEmpty);
      expect(api.sent, hasLength(1));
    });

    test('late successful send after identity deletion cannot revive private payload', () async {
      final pending = Completer<CommentTask>();
      api.onExecute = (_) => pending.future;
      final sending = submit();
      await Future<void>.delayed(Duration.zero);
      final intent = api.sent.single;
      await controller.identityDeleted(_identity);
      expect(controller.entries.single.content, isNull);
      pending.complete(_snapshot(intent, state: CommentTaskState.published));
      await sending;
      expect(controller.resolvedTasks.single.state, CommentTaskState.published);
      expect(controller.entries, isEmpty);
      expect(await journal.read(_account), isEmpty);
    });
  });

  group('stable captured comment order', () {
    final time = DateTime.utc(2026, 10, 18);
    List<CommentRank> items() => [
      for (var i = 1; i <= 14; i++)
        CommentRank(
          id: _id(i),
          publishedAt: time.add(Duration(seconds: i)),
          likes: i,
        ),
    ];
    test('main comments take top ten, then remaining comments by time', () {
      final snapshot = CommentOrderSnapshot.capture(items());
      expect(snapshot.all.map((e) => e.id), [
        for (var i = 14; i >= 5; i--) _id(i),
        for (var i = 1; i <= 4; i++) _id(i),
      ]);
    });
    test('replies default five and expansion preserves top-five then time', () {
      final snapshot = CommentOrderSnapshot.capture(items(), replies: true);
      expect(snapshot.replies(expanded: false).map((e) => e.id), [
        for (var i = 14; i >= 10; i--) _id(i),
      ]);
      expect(snapshot.hiddenCount, 9);
      expect(snapshot.replies(expanded: true).skip(5).map((e) => e.id), [
        for (var i = 1; i <= 9; i++) _id(i),
      ]);
    });
    test('like updates do not reorder until a new capture', () {
      final snapshot = CommentOrderSnapshot.capture(items(), replies: true);
      final order = snapshot.all.map((e) => e.id).toList();
      snapshot.updateLikes(_id(1), 100);
      expect(snapshot.all.map((e) => e.id), order);
      expect(
        CommentOrderSnapshot.capture(snapshot.all, replies: true).all.first.id,
        _id(1),
      );
    });
    test('equal likes use earlier time then stable ID including boundary', () {
      final snapshot = CommentOrderSnapshot.capture([
        for (var i = 12; i >= 1; i--)
          CommentRank(id: _id(i), publishedAt: time, likes: 2),
      ]);
      expect(snapshot.all.map((e) => e.id), [
        for (var i = 1; i <= 12; i++) _id(i),
      ]);
    });
    test(
      'deleting a leading reply never promotes hidden replies into view',
      () {
        final snapshot = CommentOrderSnapshot.capture([
          for (var i = 1; i <= 7; i++)
            CommentRank(id: _id(i), publishedAt: time, likes: 0),
        ], replies: true);
        snapshot.remove([_id(2)]);
        expect(snapshot.replies(expanded: false).map((e) => e.id), [
          _id(1),
          _id(3),
          _id(4),
          _id(5),
        ]);
        expect(snapshot.hiddenCount, 2);
      },
    );

    test('known deletion removes rows without resorting survivors', () {
      final snapshot = CommentOrderSnapshot.capture(items());
      final survivors = snapshot.all
          .where((e) => e.id != _id(14))
          .map((e) => e.id)
          .toList();
      snapshot.remove([_id(14)]);
      expect(snapshot.all.map((e) => e.id), survivors);
    });
  });
}
