import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';
import 'package:sqlite3/sqlite3.dart';

import 'dm_chat_test.dart' as chat;
import 'dm_chat_races_test.dart' as races;
import 'dm_reliability_test.dart' as p1;

class LifecycleApi extends chat.ChatApi {
  String? pausePath;
  Completer<void>? started, release;
  PostFailure? failure;
  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (failure != null) throw failure!;
    if (method == 'GET' &&
        pausePath != null &&
        resource.startsWith(pausePath!)) {
      started!.complete();
      pausePath = null;
      await release!.future;
    }
    if (resource == 'chat/conversations' && query?['identityId'] != p1.own) {
      final now = DateTime.now().toUtc();
      return PostResponse(
        value: {'items': <dynamic>[]},
        serverTime: now,
        sessionExpiresAt: now.add(const Duration(hours: 1)),
        requestId: 'lifecycle',
        statusCode: 200,
      );
    }
    return super.dmRequest(token, method, resource, body: body, query: query);
  }

  void pause(String path) {
    pausePath = path;
    started = Completer<void>();
    release = Completer<void>();
  }
}

void main() {
  late Directory root;
  late Map<String, p1.Vault> vaults;
  setUp(() {
    root = Directory.systemTemp.createTempSync('hnuhole-dm-lifecycle-');
    vaults = {};
  });
  tearDown(() async => root.delete(recursive: true));
  File file(String account) => File('${root.path}/$account.sqlite');
  Future<DmStore> open([String account = 'a']) => DmStore.open(
    file(account),
    'lifecycle',
    account,
    vaults.putIfAbsent(account, p1.Vault.new),
  );
  Future<void> bind(
    DmController c, {
    String account = 'a',
    List<String>? identities,
  }) => c.bind(
    account: account,
    token: 'token-$account',
    identities: identities ?? [p1.own],
    isCurrent: () => true,
  );

  test('authoritative removal erases only owner records, queues and media, including standalone drafts', () async {
    final store = await open();
    final keep = races.other, removedPhoto = dmId(), keptPhoto = dmId();
    await store.saveChatConversations([
      {...chat.directory(), 'note': '删除身份的私人备注'},
    ]);
    final command = await store.enqueue(chat.textIntent('删除身份的正文'));
    await store.transition(command, 'queued', 'unknown');
    await store.saveDraft(p1.own, p1.peer, '删除身份的草稿');
    await store.savePhotoDraft(
      p1.own,
      p1.peer,
      chat.descriptor(removedPhoto),
      chat.photo,
    );
    await store.enqueueOperation({
      'identityId': p1.own,
      'conversationId': p1.conversation,
      'operation': 'SETTINGS',
      'note': '队列中的备注',
    });
    // Both drafts have no corresponding conversation, the old cleanup blind spot.
    await store.saveDraft(p1.own, keep, '单独草稿');
    await store.saveDraft(keep, p1.peer, '另一身份草稿');
    await store.savePhotoDraft(
      keep,
      p1.peer,
      chat.descriptor(keptPhoto),
      chat.photo,
    );
    final received = races.incoming(p1.peer, dmId(), chat.photo);
    await store.receivePhoto(received, chat.photo);
    await store.applyControls([races.retraction(received, 1)], 1);
    await store.reconcileIdentities([keep]);
    expect(await store.conversations(), isEmpty);
    expect(await store.work(), isEmpty);
    expect(await store.operations(), isEmpty);
    expect(await store.get(command), isNull);
    expect(await store.get('retracted:${received['messageId']}'), isNull);
    expect(await store.draft(p1.own, keep), '');
    expect(await store.photoDraft(p1.own, p1.peer), isEmpty);
    expect(await store.draft(keep, p1.peer), '另一身份草稿');
    expect(await store.photo(keptPhoto, senderId: keep), chat.photo);
    await expectLater(
      store.photo(removedPhoto, senderId: p1.own),
      throwsA(isA<PostStorageFailure>()),
    );
    // Stale work cannot reintroduce an identity, even using a stale directory.
    await expectLater(
      store.enqueue(chat.textIntent('迟到正文')),
      throwsA(isA<PostStorageFailure>()),
    );
    await expectLater(
      store.savePhotoDraft(
        p1.own,
        p1.peer,
        chat.descriptor(dmId()),
        chat.photo,
      ),
      throwsA(isA<PostStorageFailure>()),
    );
    await expectLater(
      store.receivePhoto(received, chat.photo),
      throwsA(isA<PostStorageFailure>()),
    );
    await store.reconcileIdentities([p1.own, keep]);
    await expectLater(
      store.saveDraft(p1.own, p1.peer, '迟到草稿'),
      throwsA(isA<PostStorageFailure>()),
    );
    await store.close();
    final db = sqlite3.open(file('a').path);
    expect(
      db.select("SELECT * FROM dm_records WHERE kind='operation'"),
      isEmpty,
    );
    expect(
      db.select("SELECT * FROM dm_records WHERE kind='media_meta'").length,
      1,
    );
    db.close();
  });

  test('refresh removes stale unknown sender before replay, without switching identity', () async {
    final api = LifecycleApi();
    // Seed an unknown command from the old session, then log in with new directory.
    final store = await open();
    final id = await store.enqueue(chat.textIntent('原身份未知结果'));
    await store.transition(id, 'queued', 'unknown');
    await store.close();
    final controller = DmController(
      api: api,
      openStore: open,
      chatEnabled: true,
    );
    await bind(controller, identities: [races.other]);
    expect(api.sends, 0);
    expect(controller.conversations, isEmpty);
    expect(
      await controller.send({...chat.textIntent('拒绝'), 'identityId': p1.own}),
      false,
    );
    await controller.detach();
    controller.dispose();
    final reopened = await open();
    expect(await reopened.get(id), isNull);
    await reopened.close();
  });

  test(
    'identity cleanup retains media still referenced by another own identity',
    () async {
      final store = await open();
      final image = dmId();
      final first = races.incoming(p1.peer, image, chat.photo);
      final second = {
        ...races.incoming(p1.peer, image, chat.photo),
        'identityId': races.other,
      };
      await store.receivePhoto(first, chat.photo);
      await store.receivePhoto(second, chat.photo);
      await store.reconcileIdentities([races.other]);
      expect(await store.get(first['messageId']), isNull);
      expect(await store.get(second['messageId']), isNotNull);
      expect(await store.photo(image, senderId: p1.peer), chat.photo);
      await store.close();
    },
  );

  test(
    'file-store CLOSED tombstone rejects reopened and stale handle writes',
    () async {
      final store = await open();
      await store.saveDraft(p1.own, p1.peer, '清除正文');
      final stale = await open();
      await store.purgeClosedAccount();
      await expectLater(
        stale.saveDraft(p1.own, p1.peer, '迟到正文'),
        throwsA(isA<PostStorageFailure>()),
      );
      await stale.close();
      await store.close();
      final reopened = await open();
      await expectLater(
        reopened.conversations(),
        throwsA(isA<PostStorageFailure>()),
      );
      await reopened.close();
      final db = sqlite3.open(file('a').path);
      expect(db.select('SELECT id FROM dm_records').map((r) => r['id']), [
        'account-closed',
      ]);
      db.close();
    },
  );

  test(
    'identity refresh fences an in-flight unknown lookup before it can PUT',
    () async {
      final api = LifecycleApi();
      final controller = DmController(
        api: api,
        openStore: open,
        chatEnabled: true,
      );
      await bind(controller);
      api.pause('commands/');
      expect(await controller.send(chat.textIntent('原身份的待发送')), true);
      await api.started!.future;
      final refreshed = bind(controller, identities: [races.other]);
      expect(controller.available, false);
      api.release!.complete();
      await refreshed;
      expect(api.sends, 0);
      expect(controller.conversations, isEmpty);
      await controller.detach();
      controller.dispose();
      final store = await open();
      expect(await store.work(), isEmpty);
      await store.close();
    },
  );

  test('late private-image response after identity removal cannot commit or notify', () async {
    final api = LifecycleApi();
    var notifications = 0;
    final c = DmController(
      api: api,
      openStore: open,
      chatEnabled: true,
      onIncoming: (_, _) async {
        notifications++;
      },
    );
    await bind(c);
    final item = races.incoming(p1.peer, dmId(), chat.photo);
    api.pending.add(item);
    api.media[item['messageId']] = {
      ...Map<String, dynamic>.from(item['media']),
      'messageId': item['messageId'],
      'data': base64Encode(chat.photo),
    };
    api.pause('chat/media/');
    final syncing = c.sync();
    await api.started!.future;
    final refreshed = bind(c, identities: [races.other]);
    api.release!.complete();
    await syncing;
    await refreshed;
    expect(notifications, 0);
    expect(api.acknowledgments, 0);
    await c.detach();
    c.dispose();
    final store = await open();
    expect(await store.get(item['messageId']), isNull);
    await expectLater(
      store.photo((item['media'] as Map)['mediaId'], senderId: p1.peer),
      throwsA(isA<PostStorageFailure>()),
    );
    await store.close();
  });

  test('normal detach preserves history and key, CLOSED purges only the original account', () async {
    final other = await open('b');
    await other.saveDraft(p1.own, p1.peer, '账号 b');
    await other.close();
    var purges = 0;
    final api = LifecycleApi()..offline = true;
    final c = DmController(
      api: api,
      openStore: open,
      chatEnabled: true,
      purgeStore: (account) async {
        purges++;
        await file(account).delete();
        vaults[account]!.value = null;
      },
    );
    await bind(c);
    expect(await c.send(chat.textIntent('账号 a 的历史')), true);
    final key = vaults['a']!.value;
    await c.detach();
    expect(await file('a').exists(), true);
    expect(vaults['a']!.value, key);
    final retained = await open();
    expect(
      (await retained.history(p1.own, p1.peer)).single['intent'],
      chat.textIntent('账号 a 的历史'),
    );
    await retained.close();
    await bind(c, account: 'b');
    expect(await c.draft(p1.own, p1.peer), '账号 b');
    await c.purgeClosedAccount('a');
    expect(await file('a').exists(), false);
    expect(vaults['a']!.value, null);
    expect(c.accountId, 'b');
    expect(c.available, true);
    expect(await c.draft(p1.own, p1.peer), '账号 b');
    await c.purgeClosedAccount('a');
    expect(purges, 1);
    await bind(c, account: 'a');
    expect(c.accountId, 'b');
    expect(await file('a').exists(), false);
    await c.detach();
    c.dispose();
  });

  test('CLOSED waits for a pending open and closes it before deleting native files', () async {
    final started = Completer<void>(), release = Completer<void>();
    var purged = false, opens = 0;
    late DmStore delayed;
    final c = DmController(
      api: LifecycleApi(),
      chatEnabled: true,
      openStore: (account) async {
        opens++;
        delayed = await open(account);
        started.complete();
        await release.future;
        return delayed;
      },
      purgeStore: (account) async {
        await expectLater(
          delayed.conversations(),
          throwsA(isA<PostStorageFailure>()),
        );
        await file(account).delete();
        vaults[account]!.value = null;
        purged = true;
      },
    );
    final binding = bind(c);
    await started.future;
    final closing = c.purgeClosedAccount('a');
    expect(c.available, false);
    expect(purged, false);
    release.complete();
    await binding;
    await closing;
    expect(purged, true);
    expect(c.accountId, null);
    await bind(c);
    expect(opens, 1);
    expect(await file('a').exists(), false);
    c.dispose();
  });

  test(
    'CLOSED fences late accepted send and waits for retired store before purge',
    () async {
      final api = LifecycleApi();
      var purged = false;
      final c = DmController(
        api: api,
        openStore: open,
        chatEnabled: true,
        purgeStore: (account) async {
          await file(account).delete();
          vaults[account]!.value = null;
          purged = true;
        },
      );
      await bind(c);
      api.hold = Completer<void>();
      await c.send(chat.textIntent('已受理但响应未返回'));
      while (api.sends == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final detached = c.detach();
      final closing = c.purgeClosedAccount('a');
      expect(c.available, false);
      expect(purged, false);
      api.hold!.complete();
      await detached;
      await closing;
      expect(purged, true);
      expect(c.conversations, isEmpty);
      expect(api.sends, 1);
      expect(await file('a').exists(), false);
      c.dispose();
    },
  );

  test('failed CLOSED purge stays fenced and can retry', () async {
    var calls = 0;
    final c = DmController(
      api: LifecycleApi(),
      openStore: open,
      purgeStore: (_) async {
        if (++calls == 1) throw const PostStorageFailure();
      },
    );
    await bind(c);
    await expectLater(
      c.purgeClosedAccount('a'),
      throwsA(isA<PostStorageFailure>()),
    );
    await bind(c);
    expect(c.available, false);
    await c.purgeClosedAccount('a');
    expect(calls, 2);
    c.dispose();
  });

  test('notification fires only once after reliable inbound commit and directory refresh', () async {
    final api = LifecycleApi();
    final notices = <String>[];
    late DmController c;
    c = DmController(
      api: api,
      openStore: open,
      chatEnabled: true,
      onIncoming: (items, account) async {
        expect(account, c.accountId);
        expect(c.conversations.single['peerName'], '对方当前昵称');
        notices.addAll(items.map((e) => e['messageId'] as String));
      },
    );
    await bind(c);
    final item = races.incoming(p1.peer, dmId(), chat.photo)
      ..['media'] = null
      ..['groupId'] = ''
      ..['position'] = 0
      ..['groupSize'] = 0
      ..['kind'] = 'TEXT'
      ..['text'] = '只提醒一次';
    api.pending.add(item);
    api.failAck = true;
    await c.sync();
    expect(notices, [item['messageId']]);
    await c.sync();
    expect(notices, [item['messageId']]);
    api.failAck = false;
    await c.sync();
    expect(notices, [item['messageId']]);
    await c.detach();
    c.dispose();
  });

  for (final failure in [
    const PostFailure(
      kind: PostFailureKind.unauthorized,
      code: 'SESSION_REPLACED',
    ),
    const PostFailure(kind: PostFailureKind.unavailable, code: 'C_GATE_CLOSED'),
  ]) {
    test(
      '${failure.kind} immediately hides history and stops callbacks without purge',
      () async {
        final api = LifecycleApi();
        var purges = 0, notices = 0;
        final c = DmController(
          api: api,
          openStore: open,
          chatEnabled: true,
          purgeStore: (_) async {
            purges++;
          },
          onIncoming: (_, _) async {
            notices++;
          },
        );
        await bind(c);
        await c.saveDraft(p1.own, p1.peer, '保留草稿');
        final oldScope = c.scope;
        api.failure = failure;
        if (failure.kind == PostFailureKind.unauthorized) {
          await expectLater(
            c.contact(p1.post, ''),
            throwsA(isA<PostFailure>()),
          );
        } else {
          await c.sync();
        }
        expect(c.available, false);
        expect(c.scope, isNot(oldScope));
        expect(c.conversations, isEmpty);
        expect(await c.draft(p1.own, p1.peer), '');
        expect(purges, 0);
        expect(notices, 0);
        await c.detach();
        c.dispose();
        final store = await open();
        expect(await store.draft(p1.own, p1.peer), '保留草稿');
        await store.close();
      },
    );
  }
}
