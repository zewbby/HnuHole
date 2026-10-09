import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';
import 'package:sqlite3/sqlite3.dart';

class TestBusinessVault implements BusinessKeyVault {
  String? value;
  int writes = 0;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    writes++;
    if (failWrite || (value != null && value != next)) {
      throw const PostStorageFailure();
    }
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestBusinessVault vault;
  final opened = <PostStore>[];
  const environment = 'https://community.test.invalid:8443';
  const account = '11111111-1111-1111-1111-111111111111';
  const otherAccount = '22222222-2222-2222-2222-222222222222';
  Map<String, dynamic> text(String suffix) => {
    'title': '私密标题$suffix',
    'body': '尚未公开的正文$suffix',
    'identityId': 'identity-1',
  };
  StoredPostIntent intent(String command, {String title = '发布原文'}) =>
      StoredPostIntent(
        commandId: command,
        operation: 'CREATE',
        digest: 'original-digest-$command',
        payload: {
          'channelId': 'channel-1',
          'identityId': 'identity-1',
          'title': title,
          'body': '原始正文',
        },
      );
  Future<PostStore> open({
    String owner = account,
    String env = environment,
    File? file,
    TestBusinessVault? keyVault,
  }) async {
    final store = await PostStore.openFile(
      file ??
          File('${directory.path}/${PostStore.scopeFor(env, owner)}.sqlite3'),
      environment: env,
      accountId: owner,
      vault: keyVault ?? vault,
    );
    opened.add(store);
    return store;
  }

  File file() => File(
    '${directory.path}/${PostStore.scopeFor(environment, account)}.sqlite3',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hnuhole-post-storage-');
    vault = TestBusinessVault();
  });
  tearDown(() async {
    for (final store in opened) {
      await store.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  test('真实 SQLite 多草稿关闭重开，文件不包含文字或命令明文', () async {
    final first = await open();
    await first.createDraft('draft-1', text('一'));
    await first.createDraft('draft-2', text('二'));
    await first.submitDraft(
      'draft-1',
      1,
      intent('private-command-id-1'),
      text('一'),
    );
    await first.close();
    final disk = latin1.decode(await file().readAsBytes());
    for (final secret in [
      '私密标题一',
      '尚未公开的正文一',
      'private-command-id-1',
      'original-digest',
    ]) {
      expect(disk, isNot(contains(secret)));
      expect(disk, isNot(contains(latin1.decode(utf8.encode(secret)))));
    }
    final reopened = await open();
    expect((await reopened.list()).length, 2);
    final submitted = await reopened.get('draft-1');
    expect(submitted!.state, 'submitted');
    expect(submitted.intents.single.commandId, 'private-command-id-1');
    expect((await reopened.get('draft-2'))!.data['title'], '私密标题二');
    expect(vault.writes, 1);
  });

  test('同一修订的并发提交只有一个原子成功', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    final results = await Future.wait([
      store
          .submitDraft('draft-1', 1, intent('command-a'), text('一'))
          .then<Object>((v) => v, onError: (Object e) => e),
      store
          .submitDraft('draft-1', 1, intent('command-b'), text('一'))
          .then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(results.whereType<StoredPostEntry>().length, 1);
    expect(results.whereType<PostStorageConflict>().length, 1);
    expect((await store.get('draft-1'))!.intents.length, 1);
  });

  test('维护命令及跨设备任务锚点原子创建，故障不会留下可换身份草稿', () async {
    final store = await open();
    final database = sqlite3.open(file().path);
    try {
      database.execute(
        "CREATE TRIGGER reject_command_index BEFORE INSERT ON post_command_index BEGIN SELECT RAISE(ABORT,'controlled failure'); END",
      );
      await expectLater(
        store.createSubmitted(
          'import-task',
          intent('task-anchor'),
          text('原身份固定'),
          state: 'FAILED',
        ),
        throwsA(isA<PostStorageFailure>()),
      );
      expect(await store.get('import-task'), isNull);
      database.execute('DROP TRIGGER reject_command_index');
      final entry = await store.createSubmitted(
        'import-task',
        intent('task-anchor'),
        text('原身份固定'),
        state: 'FAILED',
      );
      expect(entry.state, 'FAILED');
      expect(entry.intents.single.commandId, 'task-anchor');
      await expectLater(
        store.saveDraft(entry.id, entry.revision, text('换身份')),
        throwsA(isA<PostStorageConflict>()),
      );
      await expectLater(
        store.createSubmitted(
          'draft-anchor',
          intent('bad-anchor'),
          text('一'),
          state: 'draft',
        ),
        throwsA(isA<PostStorageConflict>()),
      );
    } finally {
      database.close();
    }
  });

  test('两个 SQLite 连接按修订 CAS，迟到编辑不覆盖已提交意图', () async {
    final first = await open();
    await first.createDraft('draft-1', text('一'));
    final second = await open();
    final stale = await second.get('draft-1');
    await first.submitDraft('draft-1', 1, intent('command-a'), text('一'));
    await expectLater(
      second.saveDraft('draft-1', stale!.revision, text('迟到')),
      throwsA(isA<PostStorageConflict>()),
    );
    expect(
      (await second.get('draft-1'))!.intents.single.commandId,
      'command-a',
    );
  });

  test('SQLite 写故障回滚命令索引和项目，原输入可重试', () async {
    final store = await open();
    final data = text('未丢失');
    await store.createDraft('draft-1', data);
    final database = sqlite3.open(file().path);
    try {
      database.execute(
        "CREATE TRIGGER reject_post_write BEFORE UPDATE ON post_entries BEGIN SELECT RAISE(ABORT,'controlled failure'); END",
      );
      await expectLater(
        store.submitDraft('draft-1', 1, intent('command-a'), data),
        throwsA(isA<PostStorageFailure>()),
      );
      expect((await store.get('draft-1'))!.state, 'draft');
      expect((await store.get('draft-1'))!.data, data);
      expect(
        database
            .select('SELECT COUNT(*) AS n FROM post_command_index')
            .single['n'],
        0,
      );
      database.execute('DROP TRIGGER reject_post_write');
      await store.submitDraft('draft-1', 1, intent('command-a'), data);
      expect((await store.get('draft-1'))!.state, 'submitted');
    } finally {
      database.close();
    }
  });

  test('已存在数据库缺业务密钥拒绝且不重新生成', () async {
    final first = await open();
    await first.createDraft('draft-1', text('一'));
    await first.close();
    vault.value = null;
    final before = await file().readAsBytes();
    await expectLater(open(), throwsA(isA<PostStorageLostKey>()));
    expect(vault.writes, 1);
    expect(await file().readAsBytes(), before);
  });

  test('已有数据库不能用另一把合法格式密钥打开', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    await store.close();
    vault.value = jsonEncode({
      'version': 1,
      'key': base64UrlEncode(List.filled(32, 7)),
    });
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(vault.writes, 1);
  });

  test('首次钥匙写失败不创建 SQLite 或伪装持久成功', () async {
    vault.failWrite = true;
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(await file().exists(), isFalse);
    expect(vault.value, isNull);
  });

  test('环境和账号 AAD 拒绝跨 scope 读取原文件', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    await store.close();
    await expectLater(
      open(owner: otherAccount, file: file()),
      throwsA(isA<PostStorageFailure>()),
    );
    await expectLater(
      open(env: 'https://other.invalid', file: file()),
      throwsA(isA<PostStorageFailure>()),
    );
    expect(
      PostStore.scopeFor(environment, account),
      isNot(PostStore.scopeFor(environment, otherAccount)),
    );
    expect((await (await open()).get('draft-1'))!.data['title'], '私密标题一');
  });

  test('篡改状态或修订破坏认证，不能读出正文', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    final database = sqlite3.open(file().path);
    try {
      database.execute("UPDATE post_entries SET revision=2 WHERE id='draft-1'");
      await expectLater(
        store.get('draft-1'),
        throwsA(isA<PostStorageFailure>()),
      );
      database.execute(
        "UPDATE post_entries SET revision=1,state='submitted' WHERE id='draft-1'",
      );
      await expectLater(
        store.get('draft-1'),
        throwsA(isA<PostStorageFailure>()),
      );
    } finally {
      database.close();
    }
  });

  test('密文损坏拒绝读写，不覆盖无法恢复的原记录', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    final database = sqlite3.open(file().path);
    try {
      final bytes = List<int>.from(
        database.select('SELECT payload FROM post_entries').single['payload']
            as List<int>,
      );
      bytes[15] ^= 1;
      database.execute('UPDATE post_entries SET payload=?', [bytes]);
      await expectLater(
        store.get('draft-1'),
        throwsA(isA<PostStorageFailure>()),
      );
      await expectLater(
        store.saveDraft('draft-1', 1, text('覆盖')),
        throwsA(isA<PostStorageFailure>()),
      );
      expect(
        database.select('SELECT payload FROM post_entries').single['payload'],
        bytes,
      );
    } finally {
      database.close();
    }
  });

  test('同命令追加重放返回原事实，不能换 payload 或跨项目复用', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    await store.createDraft('draft-2', text('二'));
    final submitted = await store.submitDraft(
      'draft-1',
      1,
      intent('command-a'),
      text('一'),
    );
    final replay = await store.appendIntent(
      'draft-1',
      1,
      intent('command-a'),
      text('重放'),
    );
    expect(replay.revision, submitted.revision);
    expect(replay.data, submitted.data);
    await expectLater(
      store.appendIntent(
        'draft-1',
        submitted.revision,
        intent('command-a', title: '换原文'),
        text('一'),
      ),
      throwsA(isA<PostStorageConflict>()),
    );
    await expectLater(
      store.submitDraft('draft-2', 1, intent('command-a'), text('二')),
      throwsA(isA<PostStorageConflict>()),
    );
    expect((await store.get('draft-2'))!.state, 'draft');
  });

  test('UNKNOWN 项目不能变回草稿或用草稿删除入口消失', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    final submitted = await store.submitDraft(
      'draft-1',
      1,
      intent('command-a'),
      text('一'),
    );
    final unknown = await store.recordResult(
      'draft-1',
      submitted.revision,
      'unknown',
      text('一'),
    );
    await expectLater(
      store.saveDraft('draft-1', unknown.revision, text('换身份')),
      throwsA(isA<PostStorageConflict>()),
    );
    await expectLater(
      store.deleteDraft('draft-1', unknown.revision),
      throwsA(isA<PostStorageConflict>()),
    );
    await expectLater(
      store.recordResult('draft-1', unknown.revision, 'draft', text('一')),
      throwsA(isA<PostStorageConflict>()),
    );
    expect(
      (await store.get('draft-1'))!.intents.single.payload['identityId'],
      'identity-1',
    );
  });

  test('失败重试追加新不可变意图，重开保留原核对锚点', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    final first = await store.submitDraft(
      'draft-1',
      1,
      intent('command-a'),
      text('一'),
    );
    final failed = await store.recordResult(
      'draft-1',
      first.revision,
      'failed',
      {'taskId': 'original-task'},
    );
    await store.appendIntent(
      'draft-1',
      failed.revision,
      StoredPostIntent(
        commandId: 'command-b',
        operation: 'RETRY',
        digest: 'retry-digest',
        payload: {'taskId': 'original-task', 'title': '重试文字', 'body': '新正文'},
      ),
      {'taskId': 'original-task'},
    );
    await store.close();
    final restored = (await (await open()).get('draft-1'))!;
    expect(restored.intents.map((i) => i.commandId), [
      'command-a',
      'command-b',
    ]);
    expect(restored.intents.first.payload['title'], '发布原文');
    expect(restored.intents.last.payload['title'], '重试文字');
  });

  test('普通关闭重开保留业务，权威注销清理仅影响原账号', () async {
    final first = await open();
    final second = await open(
      owner: otherAccount,
      keyVault: TestBusinessVault(),
    );
    await first.createDraft('draft-1', text('原账号'));
    await second.createDraft('draft-1', text('新账号'));
    await first.close();
    final restored = await open();
    final concurrent = await open();
    expect((await restored.list()).length, 1);
    await restored.purgeClosedAccount();
    await restored.purgeClosedAccount();
    await expectLater(restored.list(), throwsA(isA<PostStorageClosed>()));
    await expectLater(
      concurrent.createDraft('late-draft', text('迟到')),
      throwsA(isA<PostStorageClosed>()),
    );
    await expectLater(open(), throwsA(isA<PostStorageClosed>()));
    expect((await second.get('draft-1'))!.data['title'], '私密标题新账号');
  });

  test('明确终态压缩文字，仅保留命令防重事实，未决不能压缩', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    final submitted = await store.submitDraft(
      'draft-1',
      1,
      intent('command-a'),
      text('一'),
    );
    await expectLater(
      store.compactTerminal(
        'draft-1',
        submitted.revision,
        'unknown',
        text('一'),
      ),
      throwsA(isA<PostStorageConflict>()),
    );
    final compacted = await store.compactTerminal(
      'draft-1',
      submitted.revision,
      'cancelled',
      {
        'title': '旧标题',
        'task': {'body': '旧正文', 'taskId': 'task-1'},
      },
    );
    expect(compacted.intents.single.commandId, 'command-a');
    expect(compacted.intents.single.digest, 'original-digest-command-a');
    expect(compacted.intents.single.payload, {'compacted': true});
    expect(compacted.data, {
      'task': {'taskId': 'task-1'},
    });
    await expectLater(
      store.appendIntent(
        'draft-1',
        compacted.revision,
        intent('command-b'),
        text('换正文'),
      ),
      throwsA(isA<PostStorageConflict>()),
    );
    await store.close();
    expect((await (await open()).get('draft-1'))!.intents.single.payload, {
      'compacted': true,
    });
  });

  test('公开和大写终态压缩保留状态及防重锚点，不能再追加发送', () async {
    final store = await open();
    for (final state in [
      'PUBLISHED',
      'CANCELLED',
      'HIDDEN',
      'DELETED',
      'CONTENT_UNAVAILABLE',
      'NOT_ACCEPTED',
    ]) {
      final id = 'entry-$state';
      final submitted = await store.createSubmitted(
        id,
        intent('command-$state'),
        text(state),
      );
      final compacted = await store.compactTerminal(
        id,
        submitted.revision,
        state,
        {'postId': 'post-$state', 'title': '去掉公开原文', 'body': '本机原文'},
      );
      expect(compacted.state, state);
      expect(compacted.data, {'postId': 'post-$state'});
      expect(compacted.intents.single.digest, 'original-digest-command-$state');
      final same = await store.recordResult(id, compacted.revision, state, {
        'postId': 'post-$state',
        'body': '不能重新写回',
      });
      expect(same.data, {'postId': 'post-$state'});
      await expectLater(
        store.appendIntent(
          id,
          same.revision,
          intent('new-$state'),
          text('不应重发'),
        ),
        throwsA(isA<PostStorageConflict>()),
      );
    }
  });

  test('草稿删除需要修订，不能删错或覆盖别的草稿', () async {
    final store = await open();
    await store.createDraft('draft-1', text('一'));
    await store.createDraft('draft-2', text('二'));
    final edited = await store.saveDraft('draft-1', 1, text('编辑'));
    await expectLater(
      store.deleteDraft('draft-1', 1),
      throwsA(isA<PostStorageConflict>()),
    );
    await store.deleteDraft('draft-1', edited.revision);
    expect(await store.get('draft-1'), isNull);
    expect((await store.get('draft-2'))!.data['title'], '私密标题二');
  });

  test('输入和输出均冻结，提交后调用方不能偷偷改原文', () async {
    final store = await open();
    final original = text('一');
    final draft = await store.createDraft('draft-1', original);
    original['title'] = '外部变更';
    expect(draft.data['title'], '私密标题一');
    expect(() => draft.data['title'] = '偷偷改', throwsUnsupportedError);
    final command = intent('command-a');
    expect(() => command.payload['title'] = '偷偷改', throwsUnsupportedError);
  });

  test('认证秘密字段不能进入业务 SQLite', () async {
    final store = await open();
    for (final field in [
      'token',
      'bearer',
      'password',
      'recoveryCode',
      'revocationSecret',
    ]) {
      await expectLater(
        store.createDraft('bad-$field', {
          'nested': {field: 'secret'},
        }),
        throwsA(isA<PostStorageFailure>()),
      );
    }
    expect(await store.list(), isEmpty);
  });

  test('损坏 SQLite 不重建，保留原文件供明确处理', () async {
    await file().writeAsString('controlled corrupt sqlite payload');
    vault.value = jsonEncode({
      'version': 1,
      'key': base64UrlEncode(List.filled(32, 8)),
    });
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(await file().readAsString(), 'controlled corrupt sqlite payload');
    expect(vault.writes, 0);
  });

  test('既有 v1 原子重开不改格式、修订或文件字节', () async {
    final store = await open();
    await store.createDraft('draft-1', text('v1'));
    final submitted = await store.submitDraft(
      'draft-1',
      1,
      intent('v1-command'),
      text('v1'),
    );
    await store.close();
    final before = await file().readAsBytes();
    final reopened = await open();
    final restored = (await reopened.get('draft-1'))!;
    expect(restored.revision, submitted.revision);
    expect(restored.state, submitted.state);
    expect(restored.intents.single.toJson(), submitted.intents.single.toJson());
    await reopened.close();
    expect(await file().readAsBytes(), before);
    final database = sqlite3.open(file().path);
    try {
      expect(database.select('PRAGMA user_version').single['user_version'], 1);
    } finally {
      database.close();
    }
    expect(vault.writes, 1);
  });

  test('未来 schema 和带既有表的版本零拒绝，不修改原库或密钥', () async {
    final store = await open();
    await store.createDraft('draft-1', text('未来'));
    await store.close();
    for (final version in [2, 0]) {
      final database = sqlite3.open(file().path);
      database.execute('PRAGMA user_version = $version');
      database.close();
      final before = await file().readAsBytes();
      await expectLater(open(), throwsA(isA<PostStorageFailure>()));
      expect(await file().readAsBytes(), before);
      expect(vault.writes, 1);
      final check = sqlite3.open(file().path);
      try {
        expect(
          check.select('PRAGMA user_version').single['user_version'],
          version,
        );
        expect(
          check.select('SELECT COUNT(*) AS n FROM post_entries').single['n'],
          1,
        );
      } finally {
        check.close();
      }
    }
  });

  test('正确版本号下的坏表结构及缺表拒绝，不重建或覆盖原库', () async {
    final store = await open();
    await store.createDraft('draft-1', text('坏结构'));
    await store.close();
    final altered = sqlite3.open(file().path);
    altered.execute('ALTER TABLE post_entries ADD COLUMN unexpected TEXT');
    altered.close();
    final beforeAltered = await file().readAsBytes();
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(await file().readAsBytes(), beforeAltered);
    final missing = sqlite3.open(file().path);
    missing.execute('DROP TABLE post_command_index');
    missing.close();
    final beforeMissing = await file().readAsBytes();
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(await file().readAsBytes(), beforeMissing);
    expect(vault.writes, 1);
  });

  test('已有项目却缺少加密 meta 拒绝，不重设账号或 closed 状态', () async {
    final store = await open();
    await store.createDraft('draft-1', text('保留原归属'));
    await store.close();
    final database = sqlite3.open(file().path);
    database.execute('DELETE FROM post_meta');
    database.close();
    final before = await file().readAsBytes();
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(await file().readAsBytes(), before);
    expect(vault.writes, 1);
  });

  test('遗留 retry 明文行键迁移为随机 ID，重绑 AAD且保留缓冲关联与修订', () async {
    const taskId = '7a8612c4-44f4-4c99-893c-b6e3a5b32aa4';
    const legacyId = 'retry-$taskId-2';
    final data = {
      ...text('重试缓冲'),
      'isRetryBuffer': true,
      'taskId': taskId,
      'attemptVersion': 2,
      'channelId': 'original-channel',
      'editedAt': '2026-10-09T00:00:00Z',
    };
    final store = await open();
    await store.createDraft(legacyId, data);
    await store.saveDraft(legacyId, 1, data);
    await store.createSubmitted('anchor', intent('anchor-command'), {
      'taskId': taskId,
      'attemptVersion': 2,
    }, state: 'FAILED');
    await store.close();
    final oldDatabase = sqlite3.open(file().path);
    final oldCipher = List<int>.from(
      oldDatabase.select('SELECT payload FROM post_entries WHERE id=?', [
            legacyId,
          ]).single['payload']
          as List<int>,
    );
    oldDatabase.close();
    final reopened = await open();
    final restored = (await reopened.findRetryBuffer(taskId, 2))!;
    expect(restored.id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    expect(restored.id, isNot(contains(taskId)));
    expect(restored.revision, 2);
    expect(restored.state, 'draft');
    expect(restored.data, data);
    expect(restored.intents, isEmpty);
    expect(await reopened.get(legacyId), isNull);
    expect(
      (await reopened.get('anchor'))!.intents.single.commandId,
      'anchor-command',
    );
    await reopened.close();
    expect(latin1.decode(await file().readAsBytes()), isNot(contains(taskId)));
    final second = await open();
    expect((await second.findRetryBuffer(taskId, 2))!.id, restored.id);
    // Ciphertext authenticated for the legacy id cannot replace the new row.
    final tamper = sqlite3.open(file().path);
    try {
      tamper.execute('UPDATE post_entries SET payload=? WHERE id=?', [
        oldCipher,
        restored.id,
      ]);
      await expectLater(
        second.get(restored.id),
        throwsA(isA<PostStorageFailure>()),
      );
    } finally {
      tamper.close();
    }
  });

  test('遗留行迁移事务移动命令索引，保留 original intent/digest及防重事实', () async {
    const taskId = 'cf6f9bf3-4288-46b0-bebc-112c4255681c';
    const legacyId = 'retry-$taskId-3';
    final data = {
      ...text('原意图'),
      'isRetryBuffer': true,
      'taskId': taskId,
      'attemptVersion': 3,
      'postId': 'original-post',
      'channelId': 'original-channel',
    };
    final store = await open();
    final original = await store.createSubmitted(
      legacyId,
      intent('original-command'),
      data,
      state: 'FAILED',
    );
    final appended = await store.appendIntent(
      legacyId,
      original.revision,
      StoredPostIntent(
        commandId: 'retry-command',
        operation: 'RETRY',
        digest: 'retry-original-digest',
        payload: {
          'taskId': taskId,
          'title': '精确重试',
          'body': '原文',
          'expectedAttemptVersion': 3,
        },
      ),
      data,
    );
    final failed = await store.recordResult(
      legacyId,
      appended.revision,
      'FAILED',
      data,
    );
    await store.close();
    final reopened = await open();
    final migrated = (await reopened.list()).single;
    expect(migrated.id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    expect(migrated.revision, failed.revision);
    expect(migrated.state, failed.state);
    expect(migrated.data, failed.data);
    expect(
      migrated.intents.map((e) => e.toJson()).toList(),
      failed.intents.map((e) => e.toJson()).toList(),
    );
    final database = sqlite3.open(file().path);
    try {
      expect(
        database
            .select('SELECT entry_id FROM post_command_index')
            .map((r) => r['entry_id'])
            .toList(),
        [migrated.id, migrated.id],
      );
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      database.close();
    }
    await reopened.createDraft('other-entry', text('不能复用键'));
    await expectLater(
      reopened.submitDraft(
        'other-entry',
        1,
        intent('original-command'),
        text('不能复用键'),
      ),
      throwsA(isA<PostStorageConflict>()),
    );
  });

  test('遗留行迁移写故障回滚所有 AAD和命令引用，修复后同原意图恢复', () async {
    const firstTask = '00000000-33f5-45b0-a5d2-1a0176cfcb2c';
    const firstLegacyId = 'retry-$firstTask-1';
    const taskId = '405fae55-33f5-45b0-a5d2-1a0176cfcb2c';
    const legacyId = 'retry-$taskId-1';
    final data = {
      ...text('故障保持'),
      'isRetryBuffer': true,
      'taskId': taskId,
      'attemptVersion': 1,
    };
    final store = await open();
    await store.createDraft(firstLegacyId, {
      ...text('前一个缓冲'),
      'isRetryBuffer': true,
      'taskId': firstTask,
      'attemptVersion': 1,
    });
    final original = await store.createSubmitted(
      legacyId,
      intent('original-command'),
      data,
      state: 'FAILED',
    );
    await store.close();
    final database = sqlite3.open(file().path);
    database.execute(
      "CREATE TRIGGER reject_remap BEFORE UPDATE ON post_command_index BEGIN SELECT RAISE(ABORT,'controlled migration failure'); END",
    );
    database.close();
    final before = await file().readAsBytes();
    await expectLater(open(), throwsA(isA<PostStorageFailure>()));
    expect(await file().readAsBytes(), before);
    final check = sqlite3.open(file().path);
    try {
      expect(
        check
            .select('SELECT id FROM post_entries ORDER BY id')
            .map((r) => r['id'])
            .toList(),
        [firstLegacyId, legacyId],
      );
      expect(
        check
            .select('SELECT entry_id FROM post_command_index')
            .single['entry_id'],
        legacyId,
      );
      check.execute('DROP TRIGGER reject_remap');
    } finally {
      check.close();
    }
    final restored = await open();
    final migrated = (await restored.list()).singleWhere((e) => !e.isDraft);
    expect(
      (await restored.findRetryBuffer(firstTask, 1))!.id,
      isNot(firstLegacyId),
    );
    expect(migrated.id, isNot(legacyId));
    expect(migrated.revision, original.revision);
    expect(migrated.intents.single.toJson(), original.intents.single.toJson());
    expect(migrated.data, data);
  });

  test('retry 缓冲只按解密关联检索，重复关联拒绝猜选且不覆盖', () async {
    final store = await open();
    final data = {
      ...text('关联'),
      'isRetryBuffer': true,
      'taskId': 'private-task',
      'attemptVersion': 2,
    };
    await store.createDraft('random-buffer-a', data);
    expect(
      (await store.findRetryBuffer('private-task', 2))!.id,
      'random-buffer-a',
    );
    expect(await store.findRetryBuffer('private-task', 3), isNull);
    await store.createDraft('random-buffer-b', data);
    await expectLater(
      store.findRetryBuffer('private-task', 2),
      throwsA(isA<PostStorageConflict>()),
    );
    expect((await store.list()).length, 2);
  });

  test('业务 MethodChannel 使用独立方法和 scope，不触碰认证 read/write', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('hnuhole/auth_vault');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'businessDatabasePath') {
            return '/native/no-backup/account.sqlite3';
          }
          if (call.method == 'businessRead') return 'key-record';
          return null;
        });
    try {
      final native = DurableBusinessVault(
        PostStore.scopeFor(environment, account),
      );
      expect(await native.databasePath(), '/native/no-backup/account.sqlite3');
      expect(await native.read(), 'key-record');
      await native.write('key-record');
      await native.purgeClosedAccount();
      expect(calls.map((c) => c.method), [
        'businessDatabasePath',
        'businessRead',
        'businessWrite',
        'businessPurgeClosedAccount',
      ]);
      expect(
        () => DurableBusinessVault('hnuhole.auth.v1'),
        throwsArgumentError,
      );
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
