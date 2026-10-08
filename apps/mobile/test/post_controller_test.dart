import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:sqlite3/sqlite3.dart';

import 'identity_test_support.dart';

const _channel = '11111111-1111-4111-8111-111111111111';
const _taskId = '22222222-2222-4222-8222-222222222222';
const _postId = '33333333-3333-4333-8333-333333333333';
const _otherAccount = '44444444-4444-4444-8444-444444444444';
final _at = DateTime.utc(2026, 10, 8);

class _KeyVault implements BusinessKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

PostTask _task({
  PostTaskState state = PostTaskState.accepted,
  int version = 1,
  String title = '原标题',
  String body = '原始正文',
  bool visible = true,
  bool available = true,
}) => PostTask(
  taskId: _taskId,
  postId: _postId,
  channelId: _channel,
  identityId: identityTestId,
  attemptVersion: version,
  state: state,
  acceptedAt: _at,
  serverSortAt: _at,
  terminalAt: state == PostTaskState.accepted ? null : _at,
  failureCode: state == PostTaskState.failed ? 'PUBLISHING_STOPPED' : null,
  visible:
      visible &&
      (state == PostTaskState.accepted || state == PostTaskState.failed),
  contentAvailable: available && state != PostTaskState.cancelled,
  canRetry: visible && available && state == PostTaskState.failed,
  canCancel: visible && state == PostTaskState.accepted,
  canHide: visible && state == PostTaskState.failed,
  content: available && state != PostTaskState.cancelled
      ? PostContent(title: title, body: body)
      : null,
);

PostCommandResult _accepted({
  PostOperation operation = PostOperation.create,
  int version = 1,
}) => PostCommandResult(
  state: PostCommandState.accepted,
  operation: operation,
  taskId: _taskId,
  postId: _postId,
  attemptVersion: version,
);

class _Api implements PostApi {
  final creates = <Map<String, Object>>[],
      retries = <Map<String, Object>>[],
      cancels = <Map<String, Object>>[],
      deletes = <Map<String, Object>>[],
      queries = <Map<String, String>>[],
      seals = <Map<String, Object>>[];
  final receipts = <String, PostCommandResult>{};
  PostTask currentTask = _task();
  bool createLost = false,
      retryLost = false,
      cancelUnsent = false,
      deleteLost = false,
      deleted = false;
  PostFailure? queryFailure;
  Completer<PostResponse<PostCommandResult>>? createWait;
  Completer<PostResponse<PostsPage<PostCard>>>? feedWait;
  Completer<PostResponse<PostCommandResult>>? queryWait;
  int taskReads = 0, capabilitiesReads = 0, publishOnRead = 0;
  List<PostCard> feedCards = [];
  bool autoPublishedFeed = true;
  String? feedCursor;
  String? ownCursor;
  final ownCursors = <String?>[];
  PostResponse<T> reply<T>(T value, {int status = 200}) => PostResponse(
    value: value,
    serverTime: _at,
    sessionExpiresAt: identityTestRenewed,
    requestId: AuthCrypto.encode(List.filled(16, 10)),
    statusCode: status,
  );
  PostDetail published() => PostDetail(
    postId: _postId,
    channelId: _channel,
    title: currentTask.content?.title ?? '公开标题',
    body: currentTask.content?.body ?? '公开正文',
    author: const PostAuthor(
      state: PostAuthorState.active,
      avatar: 'default-v1',
      nickname: '面具一',
    ),
    publishedAt: _at,
  );

  @override
  Future<PostResponse<PostCommandResult>> create({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
  }) async {
    creates.add({
      'token': sessionToken,
      'commandId': commandId,
      'channelId': channelId,
      'identityId': identityId,
      'title': title,
      'body': body,
    });
    currentTask = _task(title: title, body: body);
    receipts[commandId] = _accepted();
    if (createWait != null) return createWait!.future;
    if (createLost) throw const PostFailure(kind: PostFailureKind.transport);
    return reply(_accepted(), status: 202);
  }

  @override
  Future<PostResponse<PostCommandResult>> commandResult({
    required String sessionToken,
    required String commandId,
  }) async {
    queries.add({'token': sessionToken, 'commandId': commandId});
    if (queryWait != null) return queryWait!.future;
    if (queryFailure != null) throw queryFailure!;
    return reply(
      receipts[commandId] ??
          const PostCommandResult(state: PostCommandState.unknownNotObserved),
    );
  }

  @override
  Future<PostResponse<PostCommandResult>> seal({
    required String sessionToken,
    required String commandId,
    required PostOperation operation,
    required String requestDigest,
  }) async {
    seals.add({
      'token': sessionToken,
      'commandId': commandId,
      'operation': operation,
      'digest': requestDigest,
    });
    final result =
        receipts[commandId] ??
        PostCommandResult(
          state: PostCommandState.notAccepted,
          operation: operation,
          reason: 'COMMAND_SEALED',
        );
    receipts[commandId] = result;
    return reply(result);
  }

  @override
  Future<PostResponse<PostsPage<PostTask>>> tasks({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) async => reply(
    PostsPage(
      items: currentTask.visible ? [currentTask] : [],
      nextCursor: null,
    ),
  );
  @override
  Future<PostResponse<PostTask>> task({
    required String sessionToken,
    required String taskId,
  }) async {
    taskReads++;
    if (publishOnRead > 0 && taskReads >= publishOnRead) {
      currentTask = _task(
        state: PostTaskState.published,
        version: currentTask.attemptVersion,
        title: currentTask.content?.title ?? '标题',
        body: currentTask.content?.body ?? '正文',
      );
    }
    return reply(currentTask);
  }

  @override
  Future<PostResponse<PostCommandResult>> cancel({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) async {
    cancels.add({
      'token': sessionToken,
      'commandId': commandId,
      'taskId': taskId,
      'version': expectedAttemptVersion,
    });
    if (cancelUnsent) throw const PostFailure(kind: PostFailureKind.transport);
    final state = currentTask.state == PostTaskState.accepted
        ? PostTaskState.cancelled
        : currentTask.state;
    currentTask = _task(
      state: state,
      version: currentTask.attemptVersion,
      title: currentTask.content?.title ?? '标题',
      body: currentTask.content?.body ?? '正文',
    );
    final result = PostCommandResult(
      state: PostCommandState.committed,
      operation: PostOperation.cancel,
      taskId: taskId,
      attemptVersion: expectedAttemptVersion,
      taskState: state,
    );
    receipts[commandId] = result;
    return reply(result);
  }

  @override
  Future<PostResponse<PostCommandResult>> retry({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
  }) async {
    retries.add({
      'token': sessionToken,
      'commandId': commandId,
      'taskId': taskId,
      'version': expectedAttemptVersion,
      'title': title,
      'body': body,
    });
    if (retryLost) throw const PostFailure(kind: PostFailureKind.transport);
    currentTask = _task(
      version: expectedAttemptVersion + 1,
      title: title,
      body: body,
    );
    final result = _accepted(
      operation: PostOperation.retry,
      version: expectedAttemptVersion + 1,
    );
    receipts[commandId] = result;
    return reply(result, status: 202);
  }

  @override
  Future<PostResponse<PostCommandResult>> hide({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) async {
    currentTask = _task(
      state: PostTaskState.failed,
      visible: false,
      available: false,
    );
    final result = PostCommandResult(
      state: PostCommandState.committed,
      operation: PostOperation.hideTask,
      taskId: taskId,
      attemptVersion: expectedAttemptVersion,
    );
    receipts[commandId] = result;
    return reply(result);
  }

  @override
  Future<PostResponse<PostsPage<PostCard>>> feed({
    required String sessionToken,
    required String channelId,
    String? cursor,
    int limit = 20,
  }) async =>
      feedWait?.future ??
      reply(
        PostsPage(
          items:
              feedCards.isEmpty &&
                  autoPublishedFeed &&
                  currentTask.state == PostTaskState.published
              ? [published()]
              : feedCards,
          nextCursor: feedCursor,
        ),
      );
  @override
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  }) async {
    if (deleted) {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 404,
        code: 'POST_NOT_FOUND',
      );
    }
    return reply(published());
  }

  @override
  Future<PostResponse<PostsPage<OwnPostCard>>> ownPosts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) async {
    ownCursors.add(cursor);
    return reply(
      PostsPage(
        items: currentTask.state == PostTaskState.published && !deleted
            ? [OwnPostCard(post: published(), serverSortAt: _at)]
            : [],
        nextCursor: ownCursor,
      ),
    );
  }

  @override
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  }) async {
    capabilitiesReads++;
    if (deleted) {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 404,
        code: 'POST_NOT_FOUND',
      );
    }
    return reply(
      PostCapabilities(postId: postId, canDelete: true, canEdit: false),
    );
  }

  @override
  Future<PostResponse<PostCommandResult>> delete({
    required String sessionToken,
    required String commandId,
    required String postId,
  }) async {
    deletes.add({
      'token': sessionToken,
      'commandId': commandId,
      'postId': postId,
    });
    deleted = true;
    final result = PostCommandResult(
      state: PostCommandState.committed,
      operation: PostOperation.deletePost,
      postId: postId,
    );
    receipts[commandId] = result;
    if (deleteLost) throw const PostFailure(kind: PostFailureKind.transport);
    return reply(result);
  }

  @override
  Future<PostResponse<ComposerContext>> composerContext({
    required String sessionToken,
  }) async => reply(
    const ComposerContext(
      selectionState: ComposerSelectionState.defaultAvailable,
      defaultIdentityId: identityTestId,
    ),
  );
}

class _Fixture {
  _Fixture(this.auth, this.directory, this.api);
  final IdentityTestFixture auth;
  final Directory directory;
  final _Api api;
  final vaults = <String, _KeyVault>{};
  final stores = <PostStore>[];
  final opening = <String, Future<void>>{};
  final latest = <String, PostStore>{};
  late PostController controller;
  int sequence = 1;
  File file(String owner) => File(
    '${directory.path}/${PostStore.scopeFor('https://community.test.invalid', owner)}.sqlite3',
  );
  Future<PostStore> open(String owner) async {
    final previous = opening[owner];
    final finished = Completer<void>();
    opening[owner] = finished.future;
    if (previous != null) await previous;
    try {
      // 控制器切换账号会自动打开新库；旁路查库必须等同一账号初始化结束。
      final store = await PostStore.openFile(
        file(owner),
        environment: 'https://community.test.invalid',
        accountId: owner,
        vault: vaults.putIfAbsent(owner, _KeyVault.new),
      );
      stores.add(store);
      latest[owner] = store;
      return store;
    } finally {
      finished.complete();
    }
  }

  void start({Duration poll = Duration.zero}) {
    controller = PostController(
      api: api,
      sessions: auth.sessions,
      authStore: auth.store,
      identities: auth.api,
      openStore: open,
      clock: () => _at,
      pollInterval: poll,
      newId: () => AuthCrypto.encode(List.filled(16, sequence++)),
    );
  }

  static Future<_Fixture> create({
    _Api? api,
    Duration poll = Duration.zero,
  }) async {
    final auth = await IdentityTestFixture.create(
      api: IdentityTestApi()
        ..items = [
          identityTestItem(),
          identityTestItem(id: identityTestSecondId, original: false),
        ],
    );
    final fixture = _Fixture(
      auth,
      await Directory.systemTemp.createTemp('hnuhole-post-controller-'),
      api ?? _Api(),
    );
    fixture.start(poll: poll);
    return fixture;
  }

  PostDraftEditor editor({String title = '原标题', String body = '原始正文'}) =>
      controller.newDraft(_channel)
        ..identityId = identityTestId
        ..title = title
        ..body = body;
  Future<List<StoredPostEntry>> entries([
    String owner = identityTestAccount,
  ]) async {
    await opening[owner];
    final existing = latest[owner];
    if (existing != null &&
        controller.accountId == owner &&
        controller.available) {
      // 已有真实文件连接的读操作进入其串行队列，避免旁路初始化抢 SQLite 锁。
      return await existing.list();
    }
    if (existing != null) {
      await existing.close();
    }
    final store = await open(owner);
    return await store.list();
  }

  Future<void> restart({Duration poll = Duration.zero}) async {
    controller.dispose();
    for (final store in stores) {
      await store.close();
    }
    start(poll: poll);
  }

  Future<void> switchAccount() async {
    auth.sessionApi.account = _otherAccount;
    await auth.sessions.acceptSession(
      AuthSession(
        accountId: _otherAccount,
        sessionToken: identityTestOtherToken,
        expiresAt: identityTestExpiry,
      ),
    );
  }

  Future<void> close() async {
    controller.dispose();
    for (final store in stores) {
      await store.close();
    }
    auth.dispose();
    await directory.delete(recursive: true);
  }
}

Future<void> _until(
  bool Function() condition, {
  String reason = 'condition',
}) async {
  final limit = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(limit)) fail('Timed out waiting for $reason');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<StoredPostEntry> _entry(_Fixture f, String id) async =>
    (await f.entries()).firstWhere((e) => e.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() {
    // 独立执行器用来读真实文件并验证重开，不共享同一 QueryExecutor。
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });
  late _Fixture f;
  tearDown(() async => f.close());

  test('SQLite draft edits use durable CAS revision, reopen restores multiple drafts and ignores blank new draft', () async {
    f = await _Fixture.create();
    final first = f.editor();
    expect(await f.controller.saveDraft(first), isTrue);
    expect(first.revision, 1);
    first.title = '改后标题';
    first.body = '改后正文';
    first.saved = false;
    expect(await f.controller.saveDraft(first), isTrue);
    expect(first.revision, 2);
    final second = f.editor(title: '第二篇');
    expect(await f.controller.saveDraft(second), isTrue);
    final empty = f.controller.newDraft(_channel)
      ..title = ' \u200b\r\n '
      ..body = '\u{e0100}';
    expect(await f.controller.saveDraft(empty), isTrue);
    expect(empty.persisted, isFalse);
    expect(await f.entries(), hasLength(2));
    await f.restart();
    final restored = await f.controller.restoreDraft(first.id);
    expect(restored!.title, '改后标题');
    expect(restored.body, '改后正文');
    expect(restored.identityId, identityTestId);
    expect(restored.revision, 2);
    expect((await f.controller.restoreDraft(second.id))!.title, '第二篇');
    expect(f.api.creates, isEmpty);
  });

  test('SQLite command-index write failure rolls back original intent and never sends', () async {
    f = await _Fixture.create();
    final editor = f.editor();
    expect(await f.controller.saveDraft(editor), isTrue);
    final db = sqlite3.open(f.file(identityTestAccount).path);
    try {
      db.execute(
        "CREATE TRIGGER reject_intent BEFORE INSERT ON post_command_index BEGIN SELECT RAISE(ABORT,'controlled failure'); END",
      );
      expect(await f.controller.publish(editor), isFalse);
      expect(editor.error, isNotNull);
      expect(f.api.creates, isEmpty);
      final row = await _entry(f, editor.id);
      expect(row.isDraft, isTrue);
      expect(row.intents, isEmpty);
      expect(row.data['body'], '原始正文');
      expect(
        db.select('SELECT COUNT(*) AS n FROM post_command_index').single['n'],
        0,
      );
    } finally {
      db.close();
    }
  });

  test('lost CREATE response and controller restart reconcile same original key without sending again', () async {
    final api = _Api()
      ..createLost = true
      ..queryFailure = const PostFailure(kind: PostFailureKind.transport);
    f = await _Fixture.create(api: api);
    final editor = f.editor(body: ' 原始\r\n正文 ');
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () =>
          api.creates.length == 1 &&
          api.queries.isNotEmpty &&
          !f.controller.busy,
    );
    final before = await _entry(f, editor.id);
    final key = before.intents.single.commandId;
    expect(before.data['identityId'], identityTestId);
    expect(before.intents.single.payload['body'], ' 原始\r\n正文 ');
    api.queryFailure = null;
    await f.restart();
    await _until(
      () => f.controller.personalItems.any(
        (item) => item.task?.state == PostTaskState.accepted,
      ),
      reason: 'original task restored',
    );
    expect(api.creates, hasLength(1));
    expect(api.queries.every((query) => query['commandId'] == key), isTrue);
    expect((await _entry(f, editor.id)).intents.single.commandId, key);
    expect(await f.controller.restoreDraft(editor.id), isNull);
  });

  test('ACCEPTED periodically reconciles to public post without another CREATE or duplicate own card', () async {
    final api = _Api()..publishOnRead = 2;
    f = await _Fixture.create(api: api, poll: const Duration(milliseconds: 20));
    await f.controller.loadFeed(_channel);
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () => f.controller.feedItems.any((post) => post.postId == _postId),
      reason: 'published feed insert',
    );
    await _until(
      () =>
          f.controller.personalItems
              .where((item) => item.post?.postId == _postId)
              .length ==
          1,
    );
    expect(api.creates, hasLength(1));
    expect((await _entry(f, editor.id)).state.toUpperCase(), 'PUBLISHED');
    expect(f.controller.personalItems.any((item) => item.isDraft), isFalse);
    expect(
      f.controller.feedItems.where((post) => post.postId == _postId),
      hasLength(1),
    );
  });

  test('seal of an unsent CANCEL preserves original accepted task and original fixed identity', () async {
    final api = _Api()..cancelUnsent = true;
    f = await _Fixture.create(api: api);
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () => f.controller.personalItems.any((item) => item.task != null),
    );
    await f.controller.cancelTask(_taskId);
    await _until(() => api.cancels.length == 1 && api.queries.isNotEmpty);
    await f.controller.seal(editor.id);
    final row = await _entry(f, editor.id);
    expect(api.seals.single['operation'], PostOperation.cancel);
    expect(row.state.toUpperCase(), 'ACCEPTED');
    expect(row.data['identityId'], identityTestId);
    expect(row.data['body'], '原始正文');
    expect(
      f.controller.personalItems.single.task!.state,
      PostTaskState.accepted,
    );
    expect(f.controller.personalItems.single.task!.canCancel, isTrue);
    expect(api.creates, hasLength(1));
  });

  test('historical CANCEL receipt cannot roll a newer accepted attempt back to old FAILED state', () async {
    final api = _Api()
      ..cancelUnsent = true
      ..queryFailure = const PostFailure(kind: PostFailureKind.transport);
    f = await _Fixture.create(api: api);
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () => f.controller.personalItems.any((item) => item.task != null),
    );
    await f.controller.cancelTask(_taskId);
    await _until(() => api.cancels.length == 1 && api.queries.isNotEmpty);
    final key = api.cancels.single['commandId'] as String;
    await _entry(f, editor.id);
    api.queryFailure = null;
    // 另一设备已把失败的第一轮改为第二轮受理；旧命令回执仍是第一轮事实。
    api.receipts[key] = const PostCommandResult(
      state: PostCommandState.committed,
      operation: PostOperation.cancel,
      taskId: _taskId,
      attemptVersion: 1,
      taskState: PostTaskState.failed,
    );
    api.currentTask = _task(version: 2, body: '另一设备第二轮正文');
    await f.controller.reconcile(editor.id);
    final row = await _entry(f, editor.id);
    expect(row.state, 'ACCEPTED');
    expect(row.data['attemptVersion'], 2);
    expect(f.controller.personalItems.single.task!.attemptVersion, 2);
    expect(
      f.controller.personalItems.single.task!.state,
      PostTaskState.accepted,
    );
    expect(api.creates, hasLength(1));
    expect(api.retries, isEmpty);
  });

  test('NOT_ACCEPTED retry preserves failed original task and permits a later explicit new retry', () async {
    final api = _Api()
      ..currentTask = _task(state: PostTaskState.failed)
      ..retryLost = true;
    f = await _Fixture.create(api: api);
    final editor = await f.controller.editFailedTask(_taskId);
    editor!.title = '第一次未送达修改';
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () =>
          api.retries.length == 1 &&
          api.queries.isNotEmpty &&
          !f.controller.busy,
    );
    final before = (await f.entries()).firstWhere((e) => !e.isDraft);
    final old = before.intents.last;
    await f.controller.seal(before.id);
    final row = await _entry(f, before.id);
    expect(api.seals.single['operation'], PostOperation.retry);
    expect(api.seals.single['digest'], old.digest);
    expect(row.state, 'FAILED');
    expect(row.data['postId'], _postId);
    expect(row.data['identityId'], identityTestId);
    expect(row.data['attemptVersion'], 1);
    expect(f.controller.personalItems.single.task!.canRetry, isTrue);
    final next = await f.controller.editFailedTask(_taskId);
    expect(next, isNotNull);
    next!.body = '明确核对未受理后的新重试';
    api.retryLost = false;
    expect(await f.controller.publish(next), isTrue);
    await _until(() => api.retries.length == 2 && !f.controller.busy);
    final after = await _entry(f, before.id);
    final retries = after.intents.where((e) => e.operation == 'RETRY').toList();
    expect(retries, hasLength(2));
    expect(retries.first.commandId, old.commandId);
    expect(retries.last.commandId, isNot(old.commandId));
    expect(api.currentTask.attemptVersion, 2);
    expect(api.creates, isEmpty);
  });

  test('FAILED retry editing buffer survives SQLite reopen and cannot choose a new identity/channel', () async {
    final api = _Api()..currentTask = _task(state: PostTaskState.failed);
    f = await _Fixture.create(api: api);
    await f.controller.loadPersonal();
    final editor = await f.controller.editFailedTask(_taskId);
    expect(editor, isNotNull);
    expect(editor!.isRetry, isTrue);
    editor.title = '重试修改';
    editor.body = '保存的新文字';
    editor.saved = false;
    expect(await f.controller.saveDraft(editor), isTrue);
    expect(editor.saved, isTrue);
    await f.restart();
    final restored = await f.controller.editFailedTask(_taskId);
    expect(restored!.title, '重试修改');
    expect(restored.body, '保存的新文字');
    expect(restored.channelId, _channel);
    expect(restored.identityId, identityTestId);
    expect(restored.attemptVersion, 1);
    restored.identityId = identityTestSecondId;
    expect(await f.controller.publish(restored), isFalse);
    expect(api.retries, isEmpty);
    restored.identityId = identityTestId;
    expect(await f.controller.publish(restored), isTrue);
    await _until(() => api.retries.length == 1 && !f.controller.busy);
    expect(api.retries.single['version'], 1);
    expect(api.retries.single.containsKey('identityId'), isFalse);
    expect(api.retries.single.containsKey('channelId'), isFalse);
    expect(api.currentTask.attemptVersion, 2);
    expect(api.currentTask.identityId, identityTestId);
    expect(api.creates, isEmpty);
  });

  test('retry buffer sorted before task anchor cannot replace maintenance anchor after reopen', () async {
    final api = _Api()..currentTask = _task(state: PostTaskState.failed);
    f = await _Fixture.create(api: api);
    f.sequence = 200;
    final editor = await f.controller.editFailedTask(_taskId);
    editor!.body = '应从独立编辑缓冲恢复';
    final anchorId = editor.id;
    expect(editor.bufferId!.compareTo(anchorId), lessThan(0));
    expect(await f.controller.saveDraft(editor), isTrue);
    await f.restart();
    final restored = await f.controller.editFailedTask(_taskId);
    expect(restored!.id, anchorId);
    expect(restored.body, '应从独立编辑缓冲恢复');
    expect(await f.controller.publish(restored), isTrue);
    await _until(() => api.retries.length == 1 && !f.controller.busy);
    expect(api.retries.single['version'], 1);
    expect(api.creates, isEmpty);
  });

  test('UNKNOWN retry blocks new retry editor and second publish from same existing editor', () async {
    final api = _Api()
      ..currentTask = _task(state: PostTaskState.failed)
      ..retryLost = true;
    f = await _Fixture.create(api: api);
    final editor = await f.controller.editFailedTask(_taskId);
    editor!.title = '第一次重试';
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () =>
          api.retries.length == 1 &&
          api.queries.isNotEmpty &&
          !f.controller.busy,
    );
    expect(await f.controller.editFailedTask(_taskId), isNull);
    editor.title = '第二次文字';
    expect(await f.controller.publish(editor), isFalse);
    expect(api.retries, hasLength(1));
    final row = (await f.entries()).firstWhere(
      (entry) => entry.data['taskId'] == _taskId && !entry.isDraft,
    );
    expect(
      row.intents.where((intent) => intent.operation == 'RETRY'),
      hasLength(1),
    );
    expect(row.intents.last.payload['title'], '第一次重试');
    expect(row.data['identityId'], identityTestId);
  });

  test('UNKNOWN CREATE is never restored as draft or published twice from retained editor', () async {
    final api = _Api()
      ..createLost = true
      ..queryFailure = const PostFailure(kind: PostFailureKind.transport);
    f = await _Fixture.create(api: api);
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () =>
          api.creates.isNotEmpty &&
          api.queries.isNotEmpty &&
          !f.controller.busy,
    );
    expect(await f.controller.restoreDraft(editor.id), isNull);
    editor.identityId = identityTestSecondId;
    editor.body = '另一个身份的新文字';
    expect(await f.controller.publish(editor), isFalse);
    expect(api.creates, hasLength(1));
    final row = await _entry(f, editor.id);
    expect(row.intents.single.payload['identityId'], identityTestId);
    expect(row.intents.single.payload['body'], '原始正文');
  });

  test('sealed unaccepted CREATE keeps text until explicit recovery and preserves original permanent receipt', () async {
    final api = _Api()
      ..createLost = true
      ..queryFailure = const PostFailure(kind: PostFailureKind.transport);
    f = await _Fixture.create(api: api);
    final editor = f.editor(body: ' 未受理原文\r\n ');
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () =>
          api.creates.length == 1 &&
          api.queries.isNotEmpty &&
          !f.controller.busy,
    );
    final before = await _entry(f, editor.id);
    final original = before.intents.single;
    api.receipts.clear();
    api.queryFailure = null;
    await f.controller.seal(editor.id);
    final sealed = await _entry(f, editor.id);
    expect(sealed.state, 'NOT_ACCEPTED');
    expect(sealed.data['body'], ' 未受理原文\r\n ');
    expect(sealed.intents.single.commandId, original.commandId);
    expect(await f.controller.restoreDraft(editor.id), isNull);
    final recovered = await f.controller.recoverUnaccepted(editor.id);
    expect(recovered, isNotNull);
    expect(recovered!.id, isNot(editor.id));
    expect(recovered.body, ' 未受理原文\r\n ');
    expect(recovered.identityId, identityTestId);
    expect(recovered.saved, isTrue);
    expect(recovered.persisted, isTrue);
    expect((await _entry(f, recovered.id)).isDraft, isTrue);
    final receipt = await _entry(f, editor.id);
    expect(receipt.data['abandoned'], isTrue);
    expect(receipt.data.containsKey('body'), isFalse);
    expect(receipt.intents.single.commandId, original.commandId);
    expect(receipt.intents.single.digest, original.digest);
    expect(receipt.intents.single.payload, {'compacted': true});
    expect(api.creates, hasLength(1));
  });

  test('durable task-state write failure cannot appear through a later unrelated draft refresh', () async {
    f = await _Fixture.create();
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(
      () => f.controller.personalItems.any((item) => item.task != null),
    );
    final db = sqlite3.open(f.file(identityTestAccount).path);
    try {
      db.execute(
        "CREATE TRIGGER reject_task_update BEFORE UPDATE ON post_entries BEGIN SELECT RAISE(ABORT,'controlled failure'); END",
      );
      f.api.currentTask = _task(state: PostTaskState.failed);
      await f.controller.reconcile(editor.id);
      expect((await _entry(f, editor.id)).state, 'ACCEPTED');
      final independent = f.editor(title: '新草稿');
      expect(await f.controller.saveDraft(independent), isTrue);
      final item = f.controller.personalItems.firstWhere(
        (e) => e.id == editor.id,
      );
      expect(item.task!.state, PostTaskState.accepted);
      expect(item.local!.state, 'ACCEPTED');
    } finally {
      db.close();
    }
  });

  test(
    'publication insertion preserves already loaded own-post pagination cursor',
    () async {
      final api = _Api()
        ..currentTask = _task(state: PostTaskState.published)
        ..ownCursor = 'loaded-page-anchor';
      f = await _Fixture.create(api: api);
      await f.controller.loadPersonal();
      final editor = f.editor();
      expect(await f.controller.publish(editor), isTrue);
      await _until(
        () => f.controller.personalItems.any(
          (e) => e.task != null && e.task!.state == PostTaskState.accepted,
        ),
      );
      api.currentTask = _task(state: PostTaskState.published);
      api.ownCursor = 'fresh-first-page-anchor';
      await f.controller.reconcile(editor.id);
      await _until(
        () =>
            f.controller.personalItems
                .where((item) => item.post != null)
                .length ==
            1,
      );
      await f.controller.loadPersonal(more: true);
      expect(api.ownCursors.last, 'loaded-page-anchor');
      expect(
        f.controller.personalItems.where((e) => e.post?.postId == _postId),
        hasLength(1),
      );
    },
  );

  test('historical publication outside authoritative latest page never moves to feed top', () async {
    final api = _Api()..autoPublishedFeed = false;
    final recent = PostCard(
      postId: '55555555-5555-4555-8555-555555555555',
      channelId: _channel,
      title: '较新帖子',
      author: api.published().author,
      publishedAt: _at.add(const Duration(days: 1)),
    );
    api.feedCards = [recent];
    api.feedCursor = 'old-feed-anchor';
    f = await _Fixture.create(api: api);
    await f.controller.loadFeed(_channel);
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(() => f.controller.personalItems.any((i) => i.task != null));
    api.currentTask = _task(state: PostTaskState.published);
    await f.controller.reconcile(editor.id);
    await _until(() => f.controller.personalItems.any((i) => i.post != null));
    expect(f.controller.feedItems.map((p) => p.postId), [recent.postId]);
    expect(f.controller.feedCursor, 'old-feed-anchor');
  });

  test('publication merges authoritative latest ordering while retaining loaded cursor', () async {
    final api = _Api()..autoPublishedFeed = false;
    final recent = PostCard(
      postId: '55555555-5555-4555-8555-555555555555',
      channelId: _channel,
      title: '并发较新帖子',
      author: api.published().author,
      publishedAt: _at.add(const Duration(seconds: 1)),
    );
    final older = PostCard(
      postId: '66666666-6666-4666-8666-666666666666',
      channelId: _channel,
      title: '已加载旧帖子',
      author: api.published().author,
      publishedAt: _at.subtract(const Duration(days: 1)),
    );
    api.feedCards = [older];
    api.feedCursor = 'loaded-feed-anchor';
    f = await _Fixture.create(api: api);
    await f.controller.loadFeed(_channel);
    final editor = f.editor();
    expect(await f.controller.publish(editor), isTrue);
    await _until(() => f.controller.personalItems.any((i) => i.task != null));
    api.currentTask = _task(state: PostTaskState.published);
    api.feedCards = [recent, api.published()];
    api.feedCursor = 'fresh-anchor';
    await f.controller.reconcile(editor.id);
    await _until(() => f.controller.feedItems.length == 3);
    expect(f.controller.feedItems.map((p) => p.postId), [
      recent.postId,
      _postId,
      older.postId,
    ]);
    expect(f.controller.feedCursor, 'loaded-feed-anchor');
  });

  test('identity projection refresh preserves loaded personal pagination and updates nickname', () async {
    final api = _Api()
      ..currentTask = _task(state: PostTaskState.published)
      ..ownCursor = 'loaded-own-anchor';
    f = await _Fixture.create(api: api);
    await f.controller.loadPersonal();
    f.auth.api.items = [identityTestItem(name: '更新后的身份')];
    api.ownCursor = 'new-first-page';
    await f.controller.refreshPersonalProjections();
    expect(f.controller.personalIdentity!.nickname, '更新后的身份');
    expect(
      f.controller.personalItems.where((i) => i.post != null),
      hasLength(1),
    );
    expect(api.ownCursors, [null]);
    await f.controller.loadPersonal(more: true);
    expect(api.ownCursors.last, 'loaded-own-anchor');
  });

  test('lost DELETE response reconciles stored original before now404 capability and does not create a second key', () async {
    final api = _Api()
      ..currentTask = _task(state: PostTaskState.published)
      ..deleteLost = true
      ..queryFailure = const PostFailure(kind: PostFailureKind.transport);
    f = await _Fixture.create(api: api);
    expect(await f.controller.deletePost(_postId), isFalse);
    await _until(() => api.deletes.length == 1 && api.queries.isNotEmpty);
    final oldKey = api.deletes.single['commandId'];
    api.queryFailure = null;
    final capsBefore = api.capabilitiesReads;
    expect(await f.controller.deletePost(_postId), isTrue);
    expect(api.capabilitiesReads, capsBefore);
    expect(api.deletes, hasLength(1));
    expect(api.queries.last['commandId'], oldKey);
    expect(
      f.controller.personalItems.any((item) => item.state == 'UNKNOWN'),
      isFalse,
    );
  });

  test('late feed result from previous account cannot renew current account or reveal its post', () async {
    final api = _Api()
      ..feedWait = Completer<PostResponse<PostsPage<PostCard>>>();
    f = await _Fixture.create(api: api);
    final pending = f.controller.loadFeed(_channel);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await f.switchAccount();
    api.feedWait!.complete(
      api.reply(PostsPage(items: [api.published()], nextCursor: null)),
    );
    await pending;
    expect(f.controller.accountId, _otherAccount);
    expect(f.controller.feedItems, isEmpty);
    expect(f.auth.store.current!.session!.accountId, _otherAccount);
    expect(f.auth.store.current!.session!.expiresAt, identityTestExpiry);
    expect(await f.entries(_otherAccount), isEmpty);
  });

  test('late CREATE acceptance from previous account never writes task into current account SQLite or view', () async {
    final api = _Api()
      ..createWait = Completer<PostResponse<PostCommandResult>>();
    f = await _Fixture.create(api: api);
    final editor = f.editor(body: '旧账号私密正文');
    expect(await f.controller.publish(editor), isTrue);
    await _until(() => api.creates.length == 1);
    await f.switchAccount();
    api.createWait!.complete(api.reply(_accepted(), status: 202));
    await _until(() => !f.controller.busy);
    expect(f.controller.accountId, _otherAccount);
    expect(f.controller.personalItems, isEmpty);
    expect(f.controller.feedItems, isEmpty);
    expect(await f.entries(_otherAccount), isEmpty);
    final original = await _entry(f, editor.id);
    expect(original.data['body'], '旧账号私密正文');
    expect(original.intents.single.commandId, api.creates.single['commandId']);
    expect(original.state.toUpperCase(), isNot('PUBLISHED'));
  });

  test('auth metadata durable-write failure blocks feed disclosure rather than publishing response in memory', () async {
    f = await _Fixture.create();
    f.api.feedCards = [f.api.published()];
    f.auth.vault.failContaining = '2031-01-31';
    await f.controller.loadFeed(_channel);
    expect(f.controller.feedItems, isEmpty);
    expect(f.controller.personalItems, isEmpty);
    expect(f.auth.sessions.status, AuthStatus.storageFailure);
    expect(f.controller.available, isFalse);
  });

  test('auth metadata failure after CREATE keeps persisted exact original intent and exposes no accepted task', () async {
    f = await _Fixture.create();
    final editor = f.editor();
    f.auth.vault.failContaining = '2031-01-31';
    expect(await f.controller.publish(editor), isTrue);
    await _until(() => f.api.creates.length == 1 && !f.controller.busy);
    expect(f.controller.personalItems, isEmpty);
    expect(f.controller.feedItems, isEmpty);
    final row = await _entry(f, editor.id);
    expect(row.intents.single.payload['body'], '原始正文');
    expect(row.intents.single.commandId, f.api.creates.single['commandId']);
    expect(row.state.toUpperCase(), isNot('PUBLISHED'));
    expect(f.api.creates, hasLength(1));
  });
}
