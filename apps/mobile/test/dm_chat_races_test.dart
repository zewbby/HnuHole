import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'dm_chat_test.dart' as chat;
import 'dm_reliability_test.dart' as p1;

const other = '55555555-5555-4555-8555-555555555555';

class PausedLookupApi extends chat.ChatApi {
  final started = Completer<void>(), resume = Completer<void>();
  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'GET' &&
        resource.startsWith('commands/') &&
        !started.isCompleted) {
      started.complete();
      await resume.future;
    }
    return super.dmRequest(token, method, resource, body: body, query: query);
  }
}

// Recreate the pre-namespace encrypted layout of the isolated P2 build.
// Both message descriptors survive, but only the last writer's bytes remain.
Future<void> legacyMedia(
  File file,
  String keyRecord,
  String oldId,
  String sender,
) async {
  final key = SecretKey(base64Decode(keyRecord)), cipher = AesGcm.with256bits();
  final scope = DmStore.scopeFor('races', 'account');
  final pair = hashes.Hmac(hashes.sha256, base64Decode(keyRecord))
      .convert(utf8.encode(jsonEncode(['private-media:$sender', oldId])))
      .toString();
  final db = sqlite3.open(file.path);
  try {
    final raw = db.select(
      "SELECT * FROM dm_records WHERE kind IN ('media','media_meta') AND pair=?",
      [pair],
    );
    final records = <Map<String, Object?>>[for (final r in raw) Map.from(r)];
    db.execute(
      "DELETE FROM dm_records WHERE kind IN ('media','media_meta') OR id='chat-media-layout'",
    );
    for (final row in records) {
      final bytes = row['payload'] as Uint8List;
      List<int> aad(String id, String mediaPair) => utf8.encode(
        jsonEncode([
          scope,
          1,
          id,
          row['kind'],
          mediaPair,
          row['ordinal'],
          '${row['state']}:${row['sort_key']}',
        ]),
      );
      final plain = await cipher.decrypt(
        SecretBox(
          bytes.sublist(12, bytes.length - 16),
          nonce: bytes.sublist(0, 12),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: key,
        aad: aad(row['id'] as String, pair),
      );
      final id = (row['id'] as String).replaceFirst(pair, oldId);
      final box = await cipher.encrypt(
        plain,
        secretKey: key,
        aad: aad(id, oldId),
      );
      db.execute('INSERT INTO dm_records VALUES(?,?,?,?,?,?,?)', [
        id,
        row['kind'],
        oldId,
        row['ordinal'],
        row['sort_key'],
        row['state'],
        Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]),
      ]);
    }
  } finally {
    db.close();
  }
}

Map<String, dynamic> sent(int attempt, {int sequence = 11}) => {
  'state': 'SENT',
  'attempt': attempt,
  'messageId': dmId(),
  'conversationId': p1.conversation,
  'sequence': sequence,
  'acceptedAt': DateTime.now().toUtc().toIso8601String(),
};

Map<String, dynamic> incoming(String sender, String mid, Uint8List bytes) => {
  'messageId': dmId(),
  'conversationId': p1.conversation,
  'identityId': p1.own,
  'senderId': sender,
  'sequence': 11,
  'text': '',
  'acceptedAt': DateTime.now().toUtc().toIso8601String(),
  'kind': 'IMAGE',
  'groupId': dmId(),
  'position': 0,
  'groupSize': 1,
  'media': {
    ...chat.descriptor(mid),
    'byteLength': bytes.length,
    'sha256': hashes.sha256.convert(bytes).toString(),
  },
};

Map<String, dynamic> retraction(Map<String, dynamic> item, int seq) => {
  'eventId': dmId(),
  'sequence': seq,
  'identityId': p1.own,
  'conversationId': item['conversationId'],
  'messageId': item['messageId'],
  'messageSequence': item['sequence'],
  'type': 'RETRACTED',
  'createdAt': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  late Directory root;
  late p1.Vault vault;
  setUp(() {
    root = Directory.systemTemp.createTempSync('hnuhole-dm-races-');
    vault = p1.Vault();
  });
  tearDown(() async => root.delete(recursive: true));
  Future<DmStore> open() =>
      DmStore.open(File('${root.path}/dm.sqlite'), 'races', 'account', vault);
  Future<DmController> bind(chat.ChatApi api) async {
    final c = DmController(
      api: api,
      chatEnabled: true,
      openStore: (_) => open(),
    );
    await c.bind(
      account: 'account',
      token: 'token',
      identities: [p1.own],
      isCurrent: () => true,
    );
    return c;
  }

  Future<void> close(DmController c) async {
    await c.detach();
    c.dispose();
  }

  test('hidden unknown photo keeps checking ABSENT until late SENT without replay or bytes', () async {
    final s = await open(), mid = dmId();
    await s.saveChatConversations([chat.directory()]);
    await s.savePhotoDraft(p1.own, p1.peer, chat.descriptor(mid), chat.photo);
    await s.enqueueChat(chat.textIntent(''), [mid]);
    final id = (await s.work()).single['_id'] as String;
    await s.transition(id, 'queued', 'unknown');
    await s.hideMessage(id);
    expect(await s.history(p1.own, p1.peer), isEmpty);
    expect((await s.get(id))!['intent'], isNot(contains('mediaId')));
    await expectLater(s.photo(mid, senderId: p1.own), throwsException);
    await s.close();
    final api = chat.ChatApi(), c = await bind(api);
    expect((await c.message(id))!['_state'], 'unknown');
    expect(api.imagePuts, 0);
    api.receipts[id] = sent(1);
    await c.sync();
    expect((await c.message(id))!['_state'], 'deleted');
    expect(await c.history(p1.own, p1.peer), isEmpty);
    expect(api.imagePuts, 0);
    await close(c);
  });

  test(
    'hidden retry does not mistake FAILED attempt 1 for final attempt 2',
    () async {
      final s = await open();
      final id = await s.enqueue({...chat.textIntent('secret'), 'attempt': 2});
      await s.transition(id, 'queued', 'unknown');
      await s.hideMessage(id);
      expect((await s.get(id))!['intent'], isNot(contains('text')));
      await s.close();
      final api = chat.ChatApi();
      api.receipts[id] = {
        'state': 'FAILED',
        'attempt': 1,
        'errorCode': 'PENDING_LIMIT',
      };
      final c = await bind(api);
      expect((await c.message(id))!['_state'], 'unknown');
      api.receipts[id] = sent(2);
      await c.sync();
      expect((await c.message(id))!['_state'], 'deleted');
      expect(api.sends, 0);
      await close(c);
    },
  );

  test('same media ID from two senders remains isolated through retract and delete', () async {
    var s = await open();
    final mid = dmId(),
        first = Uint8List.fromList([1, 2, 3]),
        second = Uint8List.fromList([4, 5, 6, 7]);
    final a = incoming(p1.peer, mid, first), b = incoming(other, mid, second);
    await s.receivePhoto(a, first);
    await s.receivePhoto(b, second);
    await s.close();
    s = await open();
    expect(await s.photo(mid, senderId: p1.peer), orderedEquals(first));
    expect(await s.photo(mid, senderId: other), orderedEquals(second));
    await s.applyControls([retraction(a, 1)], 1);
    await expectLater(s.photo(mid, senderId: p1.peer), throwsException);
    expect(await s.photo(mid, senderId: other), orderedEquals(second));
    await s.hideMessage(b['messageId']);
    await expectLater(s.photo(mid, senderId: other), throwsException);
    await s.close();
  });

  test('download committed after retract or deletion boundary cannot restore bytes', () async {
    final s = await open(), mid = dmId();
    final item = incoming(p1.peer, mid, chat.photo);
    await s.applyControls([retraction(item, 1)], 1);
    await s.receivePhoto(item, chat.photo);
    expect(await s.history(p1.own, p1.peer), isEmpty);
    await expectLater(s.photo(mid, senderId: p1.peer), throwsException);
    final otherItem = incoming(p1.peer, dmId(), chat.photo);
    await s.saveChatConversations([chat.directory(sequence: 11, through: 11)]);
    await s.receivePhoto(otherItem, chat.photo);
    expect(await s.history(p1.own, p1.peer), isEmpty);
    await s.close();
  });

  test('late delete hides old unknown work while preserving new queue and changed drafts', () async {
    final s = await open(), oldPhoto = dmId(), newPhoto = dmId();
    await s.saveChatConversations([chat.directory()]);
    await s.saveDraft(p1.own, p1.peer, 'old draft');
    await s.savePhotoDraft(
      p1.own,
      p1.peer,
      chat.descriptor(oldPhoto),
      chat.photo,
    );
    final old = await s.enqueue(chat.textIntent('unknown old text'));
    await s.transition(old, 'queued', 'unknown');
    final oldQueued = await s.enqueue(chat.textIntent('old queued'));
    await s.enqueueOperation({
      'identityId': p1.own,
      'conversationId': p1.conversation,
      'operation': 'DELETE',
      'throughSequence': 10,
      'expectedVersion': 1,
    });
    final operation = (await s.operations()).single['_id'] as String;
    await s.saveDraft(p1.own, p1.peer, 'new draft');
    await s.savePhotoDraft(
      p1.own,
      p1.peer,
      chat.descriptor(newPhoto),
      chat.photo,
    );
    final newer = await s.enqueue(chat.textIntent('new queued'));
    await s.finishOperation(operation, {
      'state': 'APPLIED',
      'version': 2,
      'settingsVersion': 2,
      'deletedThrough': 10,
    });
    expect((await s.get(old))!['_kind'], 'hidden_message');
    expect((await s.get(old))!['_state'], 'unknown');
    expect((await s.get(old))!['intent'], isNot(contains('text')));
    expect((await s.get(oldQueued))!['_state'], 'deleted');
    expect((await s.get(newer))!['_state'], 'queued');
    expect(await s.draft(p1.own, p1.peer), 'new draft');
    expect((await s.photoDraft(p1.own, p1.peer)).single['mediaId'], newPhoto);
    await expectLater(s.photo(oldPhoto, senderId: p1.own), throwsException);
    expect(
      await s.photo(newPhoto, senderId: p1.own),
      orderedEquals(chat.photo),
    );
    // A stale directory cannot lower the locally committed delete boundary.
    await s.saveChatConversations([chat.directory(version: 2, through: 0)]);
    expect((await s.conversations()).single['deletedThrough'], 10);
    await s.close();
  });

  test(
    'a photo sent after delete confirmation keeps its original bytes',
    () async {
      final s = await open(), mid = dmId();
      await s.saveChatConversations([chat.directory()]);
      await s.savePhotoDraft(p1.own, p1.peer, chat.descriptor(mid), chat.photo);
      await s.enqueueOperation({
        'identityId': p1.own,
        'conversationId': p1.conversation,
        'operation': 'DELETE',
        'throughSequence': 10,
        'expectedVersion': 1,
      });
      final operation = (await s.operations()).single['_id'] as String;
      await s.enqueueChat(chat.textIntent(''), [mid]);
      await s.finishOperation(operation, {
        'state': 'APPLIED',
        'version': 2,
        'settingsVersion': 2,
        'deletedThrough': 10,
      });
      expect((await s.work()).single['_state'], 'queued');
      expect(await s.photo(mid, senderId: p1.own), orderedEquals(chat.photo));
      await s.close();
    },
  );

  test('deletion while command lookup is awaiting does not replay the snapshot body', () async {
    final api = PausedLookupApi();
    final active = await bind(api);
    expect(
      await active.send(chat.textIntent('delete while lookup pending')),
      isTrue,
    );
    await api.started.future;
    final id = (await active.history(p1.own, p1.peer)).single['_id'] as String;
    await active.deleteLocal(id);
    api.resume.complete();
    await active.sync();
    expect(api.sends, 0);
    expect((await active.message(id))!['_state'], 'unknown');
    expect((await active.message(id))!['intent'], isNot(contains('text')));
    await close(active);
  });

  test('legacy P2 media migration keeps matching bytes and refuses an overwritten collision', () async {
    var s = await open();
    final mid = dmId(),
        first = Uint8List.fromList([1, 2, 3]),
        second = Uint8List.fromList([4, 5, 6]);
    await s.receivePhoto(incoming(p1.peer, mid, first), first);
    await s.receivePhoto(incoming(other, mid, second), second);
    await s.enqueue(chat.textIntent('P1 text survives migration'));
    await s.close();
    await legacyMedia(File('${root.path}/dm.sqlite'), vault.value!, mid, other);
    s = await open();
    await expectLater(s.photo(mid, senderId: p1.peer), throwsException);
    expect(await s.photo(mid, senderId: other), orderedEquals(second));
    expect(
      (await s.history(p1.own, p1.peer)).last['intent']['text'],
      'P1 text survives migration',
    );
    await s.close();
    s = await open();
    expect(await s.photo(mid, senderId: other), orderedEquals(second));
    await s.close();
  });

  test('more than a batch of absent hidden lookups cannot starve new work or later receipts', () async {
    final s = await open();
    final hidden = <String>[];
    for (var i = 0; i < 101; i++) {
      final id = await s.enqueue(chat.textIntent('unknown $i'));
      await s.transition(id, 'queued', 'unknown');
      await s.hideMessage(id);
      hidden.add(id);
    }
    final fresh = await s.enqueue(chat.textIntent('new visible work'));
    final first = await s.work();
    expect(first.first['_id'], fresh);
    final second = await s.work();
    expect({
      ...first.map((r) => r['_id']),
      ...second.map((r) => r['_id']),
    }, containsAll(hidden));
    await s.close();
  });

  test('search is explicit, scoped to selected identity, and includes hidden history', () async {
    final s = await open();
    await s.saveChatConversations([
      chat.directory()..['hidden'] = true,
      {
        ...chat.directory(),
        'id': dmId(),
        'identityId': other,
        'note': 'needle',
      },
    ]);
    await s.enqueue(chat.textIntent('local needle text'));
    await s.close();
    final api = chat.ChatApi()..offline = true;
    final c = await bind(api);
    expect(
      c.conversations.every((d) => !d.containsKey('localSearchText')),
      isTrue,
    );
    expect(await c.search(p1.own, ''), isEmpty);
    expect(await c.search(p1.own, 'needle'), {p1.conversation});
    expect(await c.search(other, 'needle'), isEmpty);
    await close(c);
  });
}
