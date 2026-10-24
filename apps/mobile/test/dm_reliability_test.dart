import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';

const own = '11111111-1111-4111-8111-111111111111';
const peer = '22222222-2222-4222-8222-222222222222';
const conversation = '33333333-3333-4333-8333-333333333333';
const post = '44444444-4444-4444-8444-444444444444';
Map<String, Object> intent([String text = '你好，持久消息']) => {
  'identityId': own,
  'peerId': peer,
  'conversationId': '',
  'sourcePostId': post,
  'sourceCommentId': '',
  'text': text,
  'attempt': 1,
};

class Vault implements BusinessKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}

class FakeDmApi implements DmApi {
  final receipts = <String, Map<String, dynamic>>{};
  final pending = <Map<String, dynamic>>[];
  final read = <String>{};
  bool loseSend = false, failAck = false, reject = false, offline = false;
  int sends = 0, accepted = 0, acknowledgments = 0;
  int rateLimitSends = 0;
  int closeRateLimits = 0, closes = 0;
  String? closeUnavailableCode;
  String? failPeer;
  String? sendUnavailableCode;
  final putIds = <String>[];
  Completer<void>? hold;
  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (offline) throw const PostFailure(kind: PostFailureKind.transport);
    Map<String, dynamic> result;
    if (resource.startsWith('commands/')) {
      final id = resource.split('/')[1];
      if (method == 'POST' && resource.endsWith('/close')) {
        closes++;
        if (closeRateLimits > 0) {
          closeRateLimits--;
          throw const PostFailure(
            kind: PostFailureKind.rejected,
            statusCode: 429,
            code: 'RATE_LIMITED',
            retryAfterSeconds: 60,
          );
        }
        if (closeUnavailableCode != null) {
          throw PostFailure(
            kind: PostFailureKind.unavailable,
            statusCode: 503,
            code: closeUnavailableCode,
          );
        }
        if (receipts[id]?['state'] != 'SENT' &&
            receipts[id]?['errorCode'] != 'COMMAND_CLOSED') {
          receipts[id] = {
            'state': 'FAILED',
            'attempt': body!['attempt'],
            'errorCode': 'COMMAND_CLOSED',
          };
        }
      }
      if (method == 'PUT') {
        sends++;
        putIds.add(id);
        if (sendUnavailableCode != null) {
          throw PostFailure(
            kind: PostFailureKind.unavailable,
            statusCode: 503,
            code: sendUnavailableCode,
          );
        }
        if (rateLimitSends > 0) {
          rateLimitSends--;
          throw const PostFailure(
            kind: PostFailureKind.rejected,
            statusCode: 429,
            code: 'RATE_LIMITED',
            retryAfterSeconds: 60,
          );
        }
        if (failPeer != null && body?['peerId'] == failPeer) {
          throw const PostFailure(kind: PostFailureKind.transport);
        }
        if (receipts[id]?['state'] != 'SENT' &&
            receipts[id]?['errorCode'] != 'COMMAND_CLOSED') {
          if (reject) {
            receipts[id] = {
              'state': 'FAILED',
              'attempt': body!['attempt'],
              'errorCode': 'WAITING_FOR_REPLY',
            };
          } else {
            accepted++;
            receipts[id] = {
              'state': 'SENT',
              'attempt': body!['attempt'],
              'messageId': dmId(),
              'conversationId': conversation,
              'sequence': accepted,
              'acceptedAt': '2026-10-21T16:00:00Z',
            };
          }
        }
        if (hold != null) await hold!.future;
        if (loseSend) {
          loseSend = false;
          throw const PostFailure(kind: PostFailureKind.transport);
        }
      }
      result = receipts[id] ?? {'state': 'ABSENT', 'attempt': 0};
    } else if (resource == 'pending') {
      result = {'items': List.of(pending)};
    } else if (resource == 'conversations') {
      result = {'items': []};
    } else {
      final ids = (body!['messageIds'] as List).cast<String>();
      if (resource == 'ack') {
        if (failAck) throw const PostFailure(kind: PostFailureKind.transport);
        acknowledgments += ids.length;
        pending.removeWhere((e) => ids.contains(e['messageId']));
      } else {
        read.addAll(ids);
      }
      result = {'state': 'APPLIED'};
    }
    final now = DateTime.utc(2026, 10, 21, 16);
    return PostResponse(
      value: decodeDm(result, resource),
      serverTime: now,
      sessionExpiresAt: now.add(const Duration(hours: 1)),
      requestId: 'fixture',
      statusCode: 200,
    );
  }
}

void main() {
  late Directory root;
  late Vault vault;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hnuhole-dm-test-');
    file = File('${root.path}/dm.sqlite');
    vault = Vault();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<DmStore> open([String account = 'account-a']) =>
      DmStore.open(file, 'test', account, vault);

  test('hidden unknown absence obtains original close anchor and releases queued successor', () async {
    final store = await open();
    final hidden = await store.enqueue(
      intent('must never replay erased content'),
    );
    await store.transition(hidden, 'queued', 'unknown');
    await store.hideMessage(hidden);
    final next = await store.enqueue(intent('next after authoritative close'));
    await store.close();
    final api = FakeDmApi();
    late DmStore active;
    final c = DmController(
      api: api,
      openStore: (_) async => active = await open(),
    );
    await c.bind(
      account: 'account-a',
      token: 'token',
      identities: [own],
      isCurrent: () => true,
    );
    expect(api.closes, 1);
    expect(api.putIds, [next]);
    expect(
      (await active.get(hidden))?['receipt']?['errorCode'],
      'COMMAND_CLOSED',
    );
    expect(await active.hasPredecessor(next), isFalse);
    expect((await active.get(next))?['_state'], 'sent');
    await c.detach();
  });

  test(
    'close429 has its own persistent wait while receive and ACK continue',
    () async {
      final store = await open();
      final hidden = await store.enqueue(intent());
      await store.transition(hidden, 'queued', 'unknown');
      await store.hideMessage(hidden);
      await store.close();
      final api = FakeDmApi()..closeRateLimits = 1;
      api.pending.add({
        'messageId': dmId(),
        'conversationId': conversation,
        'identityId': own,
        'senderId': peer,
        'sequence': 1,
        'text': 'incoming during close wait',
        'acceptedAt': '2026-10-21T16:00:00Z',
      });
      late DmStore active;
      final c = DmController(
        api: api,
        openStore: (_) async => active = await open(),
      );
      await c.bind(
        account: 'account-a',
        token: 'token',
        identities: [own],
        isCurrent: () => true,
      );
      expect(api.closes, 1);
      expect(api.sends, 0);
      expect(api.acknowledgments, 1);
      expect((await active.get(hidden))?['_state'], 'unknown');
      expect(await active.cooldown('close'), isNotNull);
      expect(await active.cooldown('control'), isNull);
      expect(await active.cooldown('send'), isNull);
      await c.detach();
      final restored = await open();
      expect(await restored.cooldown('close'), isNotNull);
      expect((await restored.get(hidden))?['_kind'], 'hidden_message');
      await restored.close();
    },
  );

  test('three normal same-conversation messages drain immediately in original order', () async {
    final store = await open();
    final ids = <String>[];
    for (final text in ['一', '二', '三']) {
      ids.add(await store.enqueue(intent(text)));
    }
    await store.close();
    final api = FakeDmApi();
    final c = DmController(api: api, openStore: (_) => open());
    await c.bind(
      account: 'account-a',
      token: 'token',
      identities: [own],
      isCurrent: () => true,
    );
    expect(api.putIds, ids);
    expect(api.accepted, 3);
    expect(
      (await c.history(own, peer)).every((r) => r['_state'] == 'sent'),
      isTrue,
    );
    await c.detach();
    c.dispose();
  });

  test(
    'verified quota503 retains DM window and ACK lane; Gate503 still suspends',
    () async {
      final api = FakeDmApi()..sendUnavailableCode = 'SHARED_RATE_UNAVAILABLE';
      var now = DateTime.utc(2026, 10, 24);
      final c = DmController(
        api: api,
        openStore: (_) => open(),
        clock: () => now,
      );
      await c.bind(
        account: 'account-a',
        token: 'token',
        identities: [own],
        isCurrent: () => true,
      );
      await c.send(intent());
      await c.sync();
      expect(c.available, isTrue);
      expect(c.error, contains('服务暂不可用'));
      api.pending.add({
        'messageId': dmId(),
        'conversationId': conversation,
        'identityId': own,
        'senderId': peer,
        'sequence': 1,
        'text': '故障期间仍可补收',
        'acceptedAt': '2026-10-21T16:00:00Z',
      });
      await c.sync();
      expect(api.pending, isEmpty);
      expect(api.acknowledgments, 1);
      expect(api.sends, 1);
      api.sendUnavailableCode = 'AUTHORIZATION_UNAVAILABLE';
      now = now.add(const Duration(seconds: 6));
      await c.sync();
      expect(c.available, isFalse);
      expect(c.conversations, isEmpty);
      expect(await c.history(own, peer), isEmpty);
      await c.detach();
      c.dispose();
    },
  );

  test('send429 persists account cooldown across restart, keeps id and still receives/ACKs', () async {
    var now = DateTime.utc(2026, 10, 24);
    final api = FakeDmApi()..rateLimitSends = 1;
    var c = DmController(api: api, openStore: (_) => open(), clock: () => now);
    await c.bind(
      account: 'account-a',
      token: 'token',
      identities: [own],
      isCurrent: () => true,
    );
    await c.send(intent());
    await c.sync();
    final original = (await c.history(own, peer)).single['_id'];
    expect(api.sends, 1);
    api.pending.add({
      'messageId': dmId(),
      'conversationId': conversation,
      'identityId': own,
      'senderId': peer,
      'sequence': 1,
      'text': '仍可收件',
      'acceptedAt': '2026-10-21T16:00:00Z',
    });
    await c.send({
      ...intent('另一个身份'),
      'identityId': peer,
      'peerId': own,
    }); // unauthorized identity cannot enqueue
    await c.sync();
    expect(api.pending, isEmpty);
    expect(api.acknowledgments, 1);
    expect(api.sends, 1);
    await c.detach();
    c.dispose();
    c = DmController(api: api, openStore: (_) => open(), clock: () => now);
    await c.bind(
      account: 'account-a',
      token: 'token',
      identities: [own, peer],
      isCurrent: () => true,
    );
    await c.send({...intent('另一身份同账号'), 'identityId': peer, 'peerId': own});
    await c.sync();
    expect(api.sends, 1);
    now = now.add(const Duration(seconds: 61));
    await c.sync();
    expect(api.putIds.where((id) => id == original), hasLength(2));
    expect(api.accepted, 2);
    await c.detach();
    c.dispose();
  });

  test('unknown predecessor cannot be overtaken while another conversation and ACK progress', () async {
    final api = FakeDmApi()..failPeer = peer;
    final store = await open();
    final first = await store.enqueue(intent('前项'));
    final second = await store.enqueue(intent('后项'));
    final other = await store.enqueue({...intent('独立会话'), 'peerId': post});
    await store.close();
    final c = DmController(api: api, openStore: (_) => open());
    await c.bind(
      account: 'account-a',
      token: 'token',
      identities: [own],
      isCurrent: () => true,
    );
    await c.sync();
    expect(api.putIds, contains(first));
    expect(api.putIds, isNot(contains(second)));
    expect(api.putIds, contains(other));
    expect((await c.message(first))!['_state'], 'unknown');
    expect((await c.message(second))!['_state'], 'queued');
    expect((await c.message(other))!['_state'], 'sent');
    await c.detach();
    c.dispose();
  });

  test('queue capacity retains draft and queued cancel differs from unknown cancel', () async {
    final store = await DmStore.open(
      file,
      'test',
      'account-a',
      vault,
      maxPendingSends: 2,
    );
    final first = await store.enqueue(intent('尚未发出'));
    final second = await store.enqueue(intent('已在途'));
    await store.transition(second, 'queued', 'unknown');
    await store.saveDraft(own, peer, '满时保留');
    await expectLater(
      store.enqueue(intent('满时保留')),
      throwsA(isA<DmQueueFull>()),
    );
    expect(await store.draft(own, peer), '满时保留');
    await store.hideMessage(first);
    expect((await store.get(first))!['_state'], 'deleted');
    expect((await store.get(first))!.containsKey('intent'), isFalse);
    expect((await store.work()).any((r) => r['_id'] == first), isFalse);
    await store.hideMessage(second);
    expect((await store.get(second))!['_kind'], 'hidden_message');
    final third = await store.enqueue(intent('后项'));
    expect(await store.hasPredecessor(third), isTrue);
    expect((await store.get(second))!['intent'], isNot(contains('text')));
    await store.close();
  });

  test(
    'only explicit resend of ADMISSION_EXPIRED creates a fresh key',
    () async {
      final store = await open();
      final id = await store.enqueue(intent());
      await store.transition(
        id,
        'queued',
        'failed',
        receipt: {
          'state': 'FAILED',
          'attempt': 1,
          'errorCode': 'ADMISSION_EXPIRED',
        },
      );
      expect(await store.work(), isEmpty);
      await store.retry(id);
      final rows = await store.work();
      expect(rows, hasLength(1));
      expect(rows.single['_id'], isNot(id));
      expect((rows.single['intent'] as Map)['attempt'], 1);
      await store.close();
    },
  );

  test(
    'enqueue is atomic with draft; restart preserves one encrypted intent',
    () async {
      var store = await open();
      await store.saveDraft(own, peer, '你好，持久消息');
      final id = await store.enqueue(intent());
      expect(await store.draft(own, peer), '');
      await store.close();
      store = await open();
      final row = await store.get(id);
      expect(row!['_state'], 'queued');
      expect((row['intent'] as Map)['identityId'], own);
      expect((await store.history(own, peer)).length, 1);
      expect(
        latin1.decode(await file.readAsBytes()).contains('sourcePostId'),
        isFalse,
      );
      expect(latin1.decode(await file.readAsBytes()).contains(own), isFalse);
      await store.close();
      await expectLater(open('account-b'), throwsA(isA<PostStorageFailure>()));
    },
  );
  test('write failure preserves draft and refuses enqueue', () async {
    final store = await open();
    await store.saveDraft(own, peer, '保留输入');
    final original = vault.value;
    vault.value = 'changed-key';
    await expectLater(
      store.enqueue(intent('保留输入')),
      throwsA(isA<PostStorageFailure>()),
    );
    vault.value = original;
    expect(await store.draft(own, peer), '保留输入');
    expect(await store.history(own, peer), isEmpty);
    await store.close();
  });
  test(
    'offline first send stays reachable in the inbox across restart',
    () async {
      final api = FakeDmApi()..offline = true;
      var c = DmController(api: api, openStore: (_) => open());
      Future<void> bind() => c.bind(
        account: 'account-a',
        token: 'token-a',
        identities: [own],
        isCurrent: () => true,
      );
      await bind();
      expect(await c.send(intent(), peerName: '对方面具'), isTrue);
      await c.sync();
      expect(c.conversations.single['localOnly'], isTrue);
      expect(c.conversations.single['peerName'], '对方面具');
      expect(c.conversations.single['localPreview'], intent()['text']);
      await c.detach();
      c.dispose();
      c = DmController(api: api, openStore: (_) => open());
      await bind();
      // GET failed before any PUT: this is still a cancellable queued task,
      // not an in-flight unknown send. Restart keeps the original local key.
      expect(c.conversations.single['localState'], 'queued');
      expect((await c.history(own, peer)).length, 1);
      expect(api.sends, 0);
      final originalId = (await c.history(own, peer)).single['_id'];
      api.offline = false;
      await c.sync();
      expect(api.accepted, 1);
      expect(api.putIds, [originalId]);
      await c.detach();
      c.dispose();
    },
  );
  test(
    'an older overlapping bind cannot replace the current account window',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final c = DmController(
        api: FakeDmApi(),
        openStore: (account) async {
          if (account == 'account-a') {
            started.complete();
            await release.future;
            return open();
          }
          return DmStore.open(
            File('${root.path}/second.sqlite'),
            'test',
            account,
            Vault(),
          );
        },
      );
      final old = c.bind(
        account: 'account-a',
        token: 'a',
        identities: [own],
        isCurrent: () => true,
      );
      await started.future;
      await c.bind(
        account: 'account-b',
        token: 'b',
        identities: [peer],
        isCurrent: () => true,
      );
      release.complete();
      await old;
      expect(c.scope, startsWith('account-b:'));
      expect(await c.send(intent()), isFalse);
      expect(await c.history(own, peer), isEmpty);
      await c.detach();
      c.dispose();
    },
  );
  test('unknown survives lost response/restart; reconcile never creates second message', () async {
    final api = FakeDmApi()..loseSend = true;
    var controller = DmController(api: api, openStore: (_) => open());
    await controller.bind(
      account: 'account-a',
      token: 'token-a',
      identities: [own],
      isCurrent: () => true,
    );
    expect(await controller.send(intent()), isTrue);
    await controller.sync();
    var rows = await controller.history(own, peer);
    expect(rows.single['_state'], 'unknown');
    await controller.detach();
    controller.dispose();
    controller = DmController(api: api, openStore: (_) => open());
    await controller.bind(
      account: 'account-a',
      token: 'token-a',
      identities: [own],
      isCurrent: () => true,
    );
    rows = await controller.history(own, peer);
    expect(rows.single['_state'], 'sent');
    expect(api.accepted, 1);
    expect(api.sends, 1);
    await controller.detach();
    controller.dispose();
  });
  test(
    'explicit failure retry keeps id/identity/text and increments only attempt',
    () async {
      final api = FakeDmApi()..reject = true;
      final c = DmController(api: api, openStore: (_) => open());
      await c.bind(
        account: 'account-a',
        token: 'token-a',
        identities: [own],
        isCurrent: () => true,
      );
      await c.send(intent());
      await c.sync();
      final before = (await c.history(own, peer)).single;
      expect(before['_state'], 'failed');
      api.reject = false;
      await c.retry(before['_id']);
      final after = (await c.history(own, peer)).single;
      expect(after['_id'], before['_id']);
      expect(after['_state'], 'sent');
      expect((after['intent'] as Map)['attempt'], 2);
      expect((after['intent'] as Map)['text'], intent()['text']);
      expect(api.accepted, 1);
      await c.detach();
      c.dispose();
    },
  );
  test('persist before ACK; replay after crash deduplicates and does not mark read', () async {
    final api = FakeDmApi()..failAck = true;
    final id = dmId();
    api.pending.add({
      'messageId': id,
      'conversationId': conversation,
      'identityId': own,
      'senderId': peer,
      'sequence': 1,
      'text': '离线补收',
      'acceptedAt': '2026-10-21T16:00:00Z',
    });
    var c = DmController(api: api, openStore: (_) => open());
    await c.bind(
      account: 'account-a',
      token: 'token-a',
      identities: [own],
      isCurrent: () => true,
    );
    expect((await c.history(own, peer)).single['_state'], 'received');
    expect(c.conversations.single['peerId'], peer);
    expect(c.conversations.single['unread'], 1);
    expect(c.conversations.single['localPreview'], '离线补收');
    expect(api.acknowledgments, 0);
    await c.detach();
    c.dispose();
    api.failAck = false;
    c = DmController(api: api, openStore: (_) => open());
    await c.bind(
      account: 'account-a',
      token: 'token-a',
      identities: [own],
      isCurrent: () => true,
    );
    expect((await c.history(own, peer)).length, 1);
    expect(api.read, isEmpty);
    expect(api.pending, isEmpty);
    await c.visible([id]);
    await c.sync();
    expect(api.read, {id});
    await c.detach();
    c.dispose();
  });
  test(
    'expired session cannot apply a late send receipt to a new window',
    () async {
      final api = FakeDmApi()..hold = Completer<void>();
      var current = true;
      final c = DmController(api: api, openStore: (_) => open());
      await c.bind(
        account: 'account-a',
        token: 'token-a',
        identities: [own],
        isCurrent: () => current,
      );
      await c.send(intent());
      while (api.sends == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      current = false;
      api.hold!.complete();
      await c.sync();
      expect(await c.history(own, peer), isEmpty);
      await c.detach();
      c.dispose();
      final store = await open();
      expect((await store.history(own, peer)).single['_state'], 'unknown');
      await store.close();
    },
  );
  test('pagination and drafts stay within the identity pair', () async {
    final store = await open();
    for (var i = 0; i < 45; i++) {
      await store.enqueue(intent('消息$i'));
    }
    final recent = await store.history(own, peer);
    expect(recent.length, 40);
    final older = await store.history(own, peer, before: recent.first['_sort']);
    expect(older.length, 5);
    expect(
      recent
          .map((e) => e['_id'])
          .toSet()
          .intersection(older.map((e) => e['_id']).toSet()),
      isEmpty,
    );
    expect(await store.history(peer, own), isEmpty);
    await store.close();
  });
  test(
    'late incoming delivery is ordered before a later outgoing sequence',
    () async {
      final store = await open();
      final outgoing = await store.enqueue(intent('第三条'));
      await store.transition(
        outgoing,
        'queued',
        'sent',
        receipt: {
          'state': 'SENT',
          'sequence': 3,
          'conversationId': conversation,
        },
      );
      final incoming = dmId();
      final item = <String, dynamic>{
        'messageId': incoming,
        'conversationId': conversation,
        'identityId': own,
        'senderId': peer,
        'sequence': 2,
        'text': '第二条晚到',
        'acceptedAt': '2026-10-21T16:00:00Z',
      };
      await store.receive([item]);
      await store.receive([item]);
      final pending = await store.enqueue(intent('等待受理'));
      expect((await store.history(own, peer)).map((e) => e['_id']), [
        incoming,
        outgoing,
        pending,
      ]);
      await store.close();
      final restored = await open();
      expect(
        (await restored.history(own, peer, before: 3)).single['_id'],
        incoming,
      );
      await restored.close();
    },
  );
  test(
    'wire parser rejects body/account leakage and invalid delivery batch',
    () {
      expect(
        () => decodeDm({
          'state': 'SENT',
          'attempt': 1,
          'accountId': 'private',
        }, 'commands/$own'),
        throwsFormatException,
      );
      expect(dmValidText('  \n'), isFalse);
      expect(dmValidText('👍🏽' * 4000), isFalse);
      expect(dmValidText('你' * 4000), isTrue);
    },
  );
}
