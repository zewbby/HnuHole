import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/comments/comment_failure_view.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/comments/comment_runtime.dart';

import 'identity_test_support.dart';

const _post = '11111111-1111-4111-8111-111111111111';
const _task = '22222222-2222-4222-8222-222222222222';
const _blob = '33333333-3333-4333-8333-333333333333';
const _otherAccount = '44444444-4444-4444-8444-444444444444';
const _createKey = 'AQEBAQEBAQEBAQEBAQEBAQ';
const _pendingKey = 'AgICAgICAgICAgICAgICAg';
typedef _Reply = ({Map<String, dynamic> value, DateTime expires});

CommentBinding _binding() =>
    CommentBinding(postId: _post, identityId: identityTestId);
CommentContent _content({bool image = false}) => CommentContent(
  body: 'original worker retry',
  image: image
      ? CommentImage(
          blobId: _blob,
          selection: PostImageSelection.fromJson({
            'mediaId': _blob,
            'sha256': 'a' * 64,
            'byteLength': 3,
            'mimeType': 'image/png',
            'width': 1,
            'height': 1,
          }),
        )
      : null,
);

CommentJournalEntry _entry({
  CommentTaskState state = CommentTaskState.accepted,
  CommentOperation operation = CommentOperation.create,
  bool image = false,
}) {
  final content = _content(image: image);
  return CommentJournalEntry(
    localId: _task,
    intent: CommentIntent(
      commandId: operation == CommentOperation.create
          ? _createKey
          : _pendingKey,
      taskId: _task,
      operation: operation,
      binding: _binding(),
      expectedAttemptVersion: operation == CommentOperation.create ? null : 1,
      content: operation == CommentOperation.abandon ? null : content,
    ),
    retainedContent: content,
    transport: operation == CommentOperation.create
        ? CommentTransportState.settled
        : CommentTransportState.unknown,
    task: CommentTask(
      taskId: _task,
      binding: _binding(),
      attemptVersion: 1,
      state: state,
      contentAvailable: true,
      canRetry: state == CommentTaskState.failed,
      canAbandon: state == CommentTaskState.failed,
      failureCode: state == CommentTaskState.failed
          ? 'PUBLICATION_FAILED'
          : null,
    ),
  );
}

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

// HTTP and encrypted storage are explicit substitutes. The runtime, authority
// window, command parser/controller, timer and failure page are production code.
class _Journal extends NativeCommentJournal {
  _Journal() : super((account) async => _Store(account));
  final data = <String, Map<String, CommentJournalEntry>>{};
  final writes = <String>[];
  Completer<Uint8List>? imageRead;
  bool failWrites = false;
  @override
  Future<List<CommentJournalEntry>> read(String accountId) async =>
      data[accountId]?.values.toList() ?? [];
  @override
  Future<void> put(String accountId, CommentJournalEntry entry) async {
    if (failWrites) throw StateError('Synthetic storage failure');
    writes.add(accountId);
    (data[accountId] ??= {})[entry.localId] = entry;
  }

  @override
  Future<void> remove(String accountId, String localId) async {
    data[accountId]?.remove(localId);
  }

  @override
  Future<Uint8List> bytes(String account, CommentImage image) async =>
      imageRead == null ? Uint8List.fromList([1, 2, 3]) : imageRead!.future;
}

class _Http extends CommentHttp {
  _Http() : super(Uri.parse('https://unused.invalid'));
  String state = 'ACCEPTED', failureCode = 'PUBLICATION_FAILED';
  int version = 1, commandReads = 0, imageWrites = 0;
  CommentOperation operation = CommentOperation.create;
  bool unknown = false;
  bool wrongTask = false;
  Completer<void>? commandGate;
  final commands = <({String path, Map<String, dynamic> body})>[];
  @override
  Future<_Reply> send(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
    String? snapshotRequest,
  }) async {
    Map<String, dynamic> result;
    if (path.startsWith('/api/v1/comment-commands/')) {
      if (method == 'PUT') {
        commands.add((path: path, body: Map.of(body!)));
        operation = CommentOperation.values.byName(
          (body['operation'] as String).toLowerCase(),
        );
        version =
            (body['expectedAttemptVersion'] as int) +
            (operation == CommentOperation.retry ? 1 : 0);
        state = operation == CommentOperation.abandon
            ? 'ABANDONED'
            : 'ACCEPTED';
      } else {
        commandReads++;
        await commandGate?.future;
      }
      result = unknown
          ? {'state': 'UNKNOWN_NOT_OBSERVED'}
          : {
              'state': operation == CommentOperation.abandon
                  ? 'APPLIED'
                  : 'ACCEPTED',
              'operation': operation.name.toUpperCase(),
              'taskId': _task,
              'attemptVersion': version,
            };
    } else if (path.endsWith('/image')) {
      imageWrites++;
      expect(bytes, [1, 2, 3]);
      result = {};
    } else if (path == '/api/v1/me/comment-tasks/$_task') {
      result = {
        'taskId': wrongTask ? _blob : _task,
        'ownerIdentityId': identityTestId,
        'postId': _post,
        'rootCommentId': null,
        'targetCommentId': null,
        'attemptVersion': version,
        'state': state,
        'failureCode': state == 'FAILED' ? failureCode : null,
        'materialsAvailable': state != 'ABANDONED',
        'content': state == 'ABANDONED'
            ? null
            : {'body': 'original worker retry', 'image': null},
        'allowedActions': state == 'FAILED' ? ['RETRY', 'ABANDON'] : <String>[],
        'publishedCommentId': null,
      };
    } else {
      throw StateError('Unexpected $method $path');
    }
    return (value: result, expires: identityTestRenewed);
  }
}

class _Fixture {
  _Fixture(this.auth, this.http, this.journal, this.runtime);
  final IdentityTestFixture auth;
  final _Http http;
  final _Journal journal;
  final CommentRuntime runtime;
  static Future<_Fixture> create({
    CommentJournalEntry? entry,
    String state = 'ACCEPTED',
  }) async {
    final auth = await IdentityTestFixture.create(
      api: IdentityTestApi()..items = [identityTestItem()],
    );
    final http = _Http()..state = state;
    if (entry != null) http.operation = entry.intent.operation;
    final journal = _Journal();
    if (entry != null) journal.data[identityTestAccount] = {_task: entry};
    final runtime = CommentRuntime(
      http: http,
      sessions: auth.sessions,
      authStore: auth.store,
      identities: auth.api,
      identityManagement: auth.controller,
      journal: journal,
    );
    return _Fixture(auth, http, journal, runtime);
  }

  Future<void> switchAccount(WidgetTester tester) async {
    auth.sessionApi.account = _otherAccount;
    await auth.sessions.login('synthetic-b', 'synthetic-password');
    await tester.pump();
    expect(auth.sessions.status, AuthStatus.authenticated);
    expect(runtime.accountId, _otherAccount);
    expect(runtime.core.ready, isTrue);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
    auth.dispose();
  }
}

Future<void> _open(
  WidgetTester tester,
  _Fixture f, {
  VoidCallback? onResolved,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AnimatedBuilder(
        animation: f.runtime,
        builder: (context, _) => Scaffold(
          body: SingleChildScrollView(
            child: CommentFailureView(
              runtime: f.runtime,
              taskId: _task,
              identityId: identityTestId,
              onResolved: onResolved,
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

FilledButton _retry(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '按原身份和对象重试'));

void main() {
  testWidgets(
    'worker failure after polling budget reconciles before one original retry',
    (tester) async {
      final f = await _Fixture.create(entry: _entry(image: true));
      try {
        await tester.pump();
        for (var i = 0; i < 42; i++) {
          await tester.pump(const Duration(seconds: 3));
          await tester.pump();
        }
        final reads = f.http.commandReads;
        await tester.pump(const Duration(seconds: 9));
        expect(f.http.commandReads, reads);
        expect(
          f.runtime.core.entries.single.task!.state,
          CommentTaskState.accepted,
        );
        f.http.state = 'FAILED';
        f.http.imageWrites = 0;
        await _open(tester, f);
        expect(
          f.journal.data[identityTestAccount]![_task]!.task!.state,
          CommentTaskState.failed,
        );
        expect(_retry(tester).onPressed, isNotNull);
        await tester.enterText(
          find.byType(TextField),
          'edited original content',
        );
        await tester.ensureVisible(find.text('按原身份和对象重试'));
        await tester.tap(find.text('按原身份和对象重试'));
        await tester.pumpAndSettle();
        final sent = f.http.commands.single;
        expect(sent.path.split('/').last, isNot(_createKey));
        expect(sent.body['operation'], 'RETRY');
        expect(sent.body['taskId'], _task);
        expect(sent.body['expectedAttemptVersion'], 1);
        expect(sent.body['body'], 'edited original content');
        expect(
          sent.body['image'],
          _content(image: true).image!.selection.toJson(),
        );
        final saved = f.journal.data[identityTestAccount]![_task]!;
        expect(saved.task!.attemptVersion, 2);
        expect(saved.intent.binding.sameAs(_binding()), isTrue);
        expect(saved.intent.commandId, sent.path.split('/').last);
        expect(f.http.imageWrites, greaterThan(0));
        expect(find.text('请核对任务结果后再操作。'), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final operation in [CommentOperation.retry, CommentOperation.abandon]) {
    testWidgets(
      'unknown ${operation.name} cannot be replaced after old FAILED read or reopen',
      (tester) async {
        final f = await _Fixture.create(
          entry: _entry(state: CommentTaskState.failed, operation: operation),
          state: 'FAILED',
        );
        f.http.unknown = true;
        try {
          await _open(tester, f);
          for (var i = 0; i < 2; i++) {
            expect(_retry(tester).onPressed, isNull);
            expect(
              tester
                  .widget<TextButton>(find.widgetWithText(TextButton, '放弃任务'))
                  .onPressed,
              isNull,
            );
            await tester.ensureVisible(find.text('核对最新状态'));
            await tester.tap(find.text('核对最新状态'));
            await tester.pumpAndSettle();
            await tester.pumpWidget(const SizedBox());
            await _open(tester, f);
          }
          expect(f.http.commands, isEmpty);
          expect(
            f.runtime.core.entries.single.transport,
            CommentTransportState.unknown,
          );
          expect(f.runtime.core.entries.single.intent.commandId, _pendingKey);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'busy original reconciliation keeps actions disabled until confirmed',
    (tester) async {
      final f = await _Fixture.create(entry: _entry());
      try {
        await tester.pump();
        f.http.state = 'FAILED';
        f.http.commandGate = Completer<void>();
        final pending = f.runtime.core.reconcile(_task);
        await _open(tester, f);
        expect(_retry(tester).onPressed, isNull);
        expect(f.http.commands, isEmpty);
        f.http.commandGate!.complete();
        await pending;
        await tester.tap(find.text('核对最新状态'));
        await tester.pumpAndSettle();
        expect(_retry(tester).onPressed, isNotNull);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets('failure persistence error cannot unlock a fresh mutation', (
    tester,
  ) async {
    final f = await _Fixture.create(entry: _entry());
    try {
      await tester.pump();
      f.http.state = 'FAILED';
      f.journal.failWrites = true;
      await _open(tester, f);
      expect(f.http.commands, isEmpty);
      expect(
        find.text('按原身份和对象重试').evaluate().isEmpty ||
            _retry(tester).onPressed == null,
        isTrue,
      );
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'fresh owner failure without local entry still supports recovery',
    (tester) async {
      final f = await _Fixture.create(state: 'FAILED');
      try {
        await _open(tester, f);
        await tester.ensureVisible(find.text('按原身份和对象重试'));
        await tester.tap(find.text('按原身份和对象重试'));
        await tester.pumpAndSettle();
        expect(f.http.commands.single.body['expectedAttemptVersion'], 1);
        expect(
          f.runtime.core.entries.single.intent.binding.sameAs(_binding()),
          isTrue,
        );
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'different owner task with same binding and version is rejected',
    (tester) async {
      final f = await _Fixture.create(state: 'FAILED');
      f.http.wrongTask = true;
      try {
        await _open(tester, f);
        expect(find.text('任务已移除或暂时无法读取，请重新核对。'), findsOneWidget);
        expect(find.text('按原身份和对象重试'), findsNothing);
        expect(f.http.commands, isEmpty);
        expect(f.runtime.core.entries, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'account switch during original command read drops old failure page',
    (tester) async {
      final f = await _Fixture.create(entry: _entry());
      try {
        await tester.pump();
        f.http.state = 'FAILED';
        f.http.commandGate = Completer<void>();
        await _open(tester, f, settle: false);
        await tester.pump();
        await f.switchAccount(tester);
        f.http.commandGate!.complete();
        await tester.pumpAndSettle();
        expect(f.http.commands, isEmpty);
        expect(f.journal.data[_otherAccount] ?? {}, isEmpty);
        expect(f.runtime.core.entries, isEmpty);
        expect(find.text('按原身份和对象重试'), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'account switch during post-action load suppresses old resolved callback',
    (tester) async {
      final f = await _Fixture.create(
        entry: _entry(state: CommentTaskState.failed),
        state: 'FAILED',
      );
      var resolved = 0;
      try {
        await _open(tester, f, onResolved: () => resolved++);
        final gate = Completer<IdentityDirectory>();
        f.auth.api.readWait = gate;
        await tester.ensureVisible(find.text('按原身份和对象重试'));
        await tester.tap(find.text('按原身份和对象重试'));
        await tester.pump();
        expect(f.http.commands, hasLength(1));
        await f.switchAccount(tester);
        gate.complete(f.auth.api.directory());
        await tester.pumpAndSettle();
        expect(resolved, 0);
        expect(f.journal.data[_otherAccount] ?? {}, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'account switch while reading retained image cannot retarget old task in B',
    (tester) async {
      final f = await _Fixture.create(
        entry: _entry(state: CommentTaskState.failed, image: true),
        state: 'FAILED',
      );
      f.http.failureCode = 'COMMENT_TARGET_DELETED';
      f.runtime.openRetarget = (_, _, _) async {};
      try {
        await _open(tester, f);
        f.journal.imageRead = Completer<Uint8List>();
        await tester.ensureVisible(find.text('保留内容，重新选择回复对象'));
        await tester.tap(find.text('保留内容，重新选择回复对象'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新选择'));
        await tester.pump();
        await f.switchAccount(tester);
        f.journal.imageRead!.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pumpAndSettle();
        expect(f.http.commands, isEmpty);
        expect(f.journal.data[_otherAccount] ?? {}, isEmpty);
        expect(f.journal.writes, isNot(contains(_otherAccount)));
      } finally {
        await f.close(tester);
      }
    },
  );
}
