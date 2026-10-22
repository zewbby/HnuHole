import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

import 'dm_reliability_test.dart' as p1;

final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9xkAAAAASUVORK5CYII=',
);
Map<String, dynamic> descriptor(String id) => {
  'mediaId': id,
  'sha256': hashes.sha256.convert(photo).toString(),
  'byteLength': photo.length,
  'mimeType': 'image/png',
  'width': 1,
  'height': 1,
};
Map<String, dynamic> directory({
  int sequence = 10,
  int version = 1,
  int through = 0,
}) => {
  'id': p1.conversation,
  'identityId': p1.own,
  'peerId': p1.peer,
  'peerName': '对方当前昵称',
  'sourcePostId': p1.post,
  'sourceTitle': '学习小组',
  'sequence': sequence,
  'unread': 0,
  'waiting': false,
  'canSend': true,
  'version': version,
  'settingsVersion': version,
  'pinned': false,
  'muted': false,
  'hidden': false,
  'deleted': false,
  'deletedThrough': through,
  'note': '',
  'unavailableUnread': 0,
};
Map<String, Object> textIntent(String text) => {
  ...p1.intent(text),
  'conversationId': p1.conversation,
  'sourcePostId': '',
  'sourceCommentId': '',
};

class ChatRuntime implements DmRuntime {
  ChatRuntime(this.controller);
  @override
  final DmController controller;
  @override
  List<DmIdentity> identities = [const DmIdentity(id: p1.own, name: '本人面具')];
  @override
  final void Function(BuildContext, String)? openPost = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ChatApi extends p1.FakeDmApi {
  Map<String, dynamic> dir = directory();
  final controls = <Map<String, dynamic>>[];
  final operationReceipts = <String, Map<String, dynamic>>{};
  final media = <String, Map<String, dynamic>>{};
  final acceptedPhotos = <String, Map<String, Object>>{};
  bool failLastTwo = true, loseOperation = false;
  int imagePuts = 0, operationPuts = 0;
  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (offline) throw const PostFailure(kind: PostFailureKind.transport);
    Map<String, dynamic> value;
    if (resource == 'chat/conversations') {
      value = {
        'items': [dir],
      };
    } else if (resource == 'chat/controls') {
      final after = int.parse(query!['after']!);
      final events = controls.where((e) => e['sequence'] > after).toList();
      value = {
        'items': events,
        'next': events.isEmpty ? after : events.last['sequence'],
      };
    } else if (resource == 'chat/pending') {
      value = {'items': List.of(pending)};
    } else if (resource.startsWith('chat/media/')) {
      value = media[resource.split('/').last]!;
    } else if (resource.startsWith('chat/operations/')) {
      final id = resource.split('/').last;
      if (method == 'PUT') {
        operationPuts++;
        if (!operationReceipts.containsKey(id)) {
          dir = {
            ...dir,
            'version': dir['version'] + 1,
            'settingsVersion': dir['settingsVersion'] + 1,
          };
          if (body!['operation'] == 'SETTINGS') {
            dir.addAll({
              'note': body['note'],
              'pinned': body['pinned'],
              'muted': body['muted'],
            });
          }
          if (body['operation'] == 'DELETE') {
            dir.addAll({
              'deleted': true,
              'deletedThrough': body['throughSequence'],
            });
          }
          operationReceipts[id] = {
            'state': 'APPLIED',
            'errorCode': '',
            'conversationId': p1.conversation,
            'version': dir['version'],
            'settingsVersion': dir['settingsVersion'],
            'deletedThrough': dir['deletedThrough'],
            'messageId': '',
          };
        }
        if (loseOperation) {
          loseOperation = false;
          throw const PostFailure(kind: PostFailureKind.transport);
        }
      }
      value =
          operationReceipts[id] ??
          {
            'state': 'ABSENT',
            'errorCode': '',
            'conversationId': '',
            'version': 0,
            'settingsVersion': 0,
            'deletedThrough': 0,
            'messageId': '',
          };
    } else if (resource.startsWith('chat/images/')) {
      final id = resource.split('/').last;
      imagePuts++;
      if (failLastTwo && (body!['position'] as int) >= 7) {
        receipts[id] = {
          'state': 'FAILED',
          'attempt': body['attempt'],
          'errorCode': 'PENDING_LIMIT',
        };
      } else if (receipts[id]?['state'] != 'SENT') {
        acceptedPhotos[id] = Map.of(body!);
        receipts[id] = {
          'state': 'SENT',
          'attempt': body['attempt'],
          'messageId': dmId(),
          'conversationId': p1.conversation,
          'sequence': ++accepted,
          'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        };
      }
      value = receipts[id]!;
    } else {
      return super.dmRequest(token, method, resource, body: body, query: query);
    }
    final now = DateTime.now().toUtc();
    return PostResponse(
      value: decodeDm(value, resource),
      serverTime: now,
      sessionExpiresAt: now.add(const Duration(hours: 1)),
      requestId: 'chat-fixture',
      statusCode: 200,
    );
  }
}

void main() {
  late Directory root;
  late p1.Vault vault;
  setUp(() {
    root = Directory.systemTemp.createTempSync('hnuhole-dm-chat-');
    vault = p1.Vault();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<DmStore> open() => DmStore.open(
    File('${root.path}/chat.sqlite'),
    'chat-test',
    'account',
    vault,
  );
  Future<DmController> controller(ChatApi api) async {
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

  test('nine photos keep positions; only two explicit failures retry after restart', () async {
    final api = ChatApi();
    var c = await controller(api);
    final ids = List.generate(9, (_) => dmId());
    for (final id in ids) {
      await c.savePhoto(p1.own, p1.peer, descriptor(id), photo);
    }
    expect(await c.sendPhotos(textIntent(''), ids), isTrue);
    await c.sync();
    var rows = await c.history(p1.own, p1.peer);
    expect(rows.where((r) => r['_state'] == 'sent').length, 7);
    expect(rows.where((r) => r['_state'] == 'failed').length, 2);
    final failed = rows
        .where((r) => r['_state'] == 'failed')
        .map((r) => r['_id'] as String)
        .toList();
    expect(api.imagePuts, 9);
    expect(api.acceptedPhotos.length, 7);
    await close(c);
    c = await controller(api);
    api.failLastTwo = false;
    for (final id in failed) {
      await c.retry(id);
      await c.sync();
    }
    rows = await c.history(p1.own, p1.peer);
    expect(rows.every((r) => r['_state'] == 'sent'), isTrue);
    expect(api.imagePuts, 11);
    expect(api.acceptedPhotos.length, 9);
    expect(
      api.acceptedPhotos.values.map((v) => v['groupId']).toSet().length,
      1,
    );
    expect(
      api.acceptedPhotos.values.map((v) => v['position']).toSet(),
      Set.of(List.generate(9, (i) => i)),
    );
    await close(c);
  });

  test('encrypted photo draft and chunks survive reopen without plaintext originals', () async {
    var store = await open();
    final id = dmId();
    final big = Uint8List.fromList(List.generate(700000, (i) => i % 251));
    final d = {
      ...descriptor(id),
      'byteLength': big.length,
      'sha256': hashes.sha256.convert(big).toString(),
    };
    await store.savePhotoDraft(p1.own, p1.peer, d, big);
    await store.close();
    store = await open();
    expect(await store.photo(id), orderedEquals(big));
    expect((await store.photoDraft(p1.own, p1.peer)).single['mediaId'], id);
    expect(await store.photoDraft(p1.peer, p1.own), isEmpty);
    final disk = await File('${root.path}/chat.sqlite').readAsBytes();
    expect(
      utf8.decode(disk, allowMalformed: true),
      isNot(contains(base64Encode(big.sublist(0, 300)))),
    );
    await store.close();
  });

  test(
    'settings response lost recovers original operation receipt after reopen',
    () async {
      final api = ChatApi()..loseOperation = true;
      var c = await controller(api);
      await c.manage(
        c.conversations.single,
        'SETTINGS',
        note: '只属于这对面具',
        pinned: true,
      );
      expect(api.operationPuts, 1);
      await close(c);
      c = await controller(api);
      expect(c.conversations.single['note'], '只属于这对面具');
      expect(c.conversations.single['pinned'], isTrue);
      expect(api.operationPuts, 1);
      await close(c);
    },
  );

  test('delete boundary prunes older history but preserves newer messages and note', () async {
    final s = await open();
    await s.saveChatConversations([
      directory(sequence: 5, version: 5)..['note'] = '私人备注',
    ]);
    Map<String, dynamic> incoming(int seq) => {
      'messageId': dmId(),
      'conversationId': p1.conversation,
      'identityId': p1.own,
      'senderId': p1.peer,
      'sequence': seq,
      'text': '正文$seq',
      'acceptedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final old = incoming(4), newer = incoming(6);
    await s.receive([old, newer]);
    await s.saveChatConversations([
      directory(sequence: 6, version: 6, through: 5)..['note'] = '私人备注',
    ]);
    expect((await s.history(p1.own, p1.peer)).single['text'], '正文6');
    await s.saveChatConversations([directory(sequence: 4, version: 4)]);
    expect((await s.conversations()).single['deletedThrough'], 5);
    expect((await s.conversations()).single['note'], '私人备注');
    expect(await s.deliverySuppressed(old), isTrue);
    expect(await s.deliverySuppressed(newer), isFalse);
    expect(await s.searchText(p1.own, p1.peer), '正文6');
    await s.close();
  });

  test(
    'retract control applied before a late incoming image prevents revival',
    () async {
      final api = ChatApi();
      final id = dmId(), mediaId = dmId();
      api.controls.add({
        'eventId': dmId(),
        'sequence': 1,
        'identityId': p1.own,
        'conversationId': p1.conversation,
        'messageId': id,
        'messageSequence': 3,
        'type': 'RETRACTED',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      api.pending.add({
        'messageId': id,
        'conversationId': p1.conversation,
        'identityId': p1.own,
        'senderId': p1.peer,
        'sequence': 3,
        'text': '',
        'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        'kind': 'IMAGE',
        'groupId': dmId(),
        'position': 0,
        'groupSize': 1,
        'media': descriptor(mediaId),
      });
      final c = await controller(api);
      expect(await c.history(p1.own, p1.peer), isEmpty);
      expect(api.acknowledgments, 1);
      await close(c);
      final s = await open();
      expect(await s.controlCursor(), 1);
      expect(await s.isRetracted(id), isTrue);
      await s.close();
    },
  );

  test(
    'partial receive only ACKs images whose complete bytes were committed',
    () async {
      final api = ChatApi();
      final group = dmId();
      for (var i = 0; i < 2; i++) {
        final id = dmId(), mid = dmId();
        api.pending.add({
          'messageId': id,
          'conversationId': p1.conversation,
          'identityId': p1.own,
          'senderId': p1.peer,
          'sequence': i + 1,
          'text': '',
          'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          'kind': 'IMAGE',
          'groupId': group,
          'position': i,
          'groupSize': 2,
          'media': descriptor(mid),
        });
        api.media[id] = {
          'messageId': id,
          ...descriptor(mid),
          'data': base64Encode(i == 0 ? photo : [1, 2, 3]),
        };
      }
      final c = await controller(api);
      expect(api.acknowledgments, 1);
      expect(api.pending.length, 1);
      expect((await c.history(p1.own, p1.peer)).single['_state'], 'inbox');
      expect(c.error, contains('未保存'));
      await close(c);
    },
  );

  test('strict chat decoder rejects private fields and invalid grouping', () {
    expect(
      () => decodeDm({
        'items': [directory()..['accountId'] = 'private'],
      }, 'chat/conversations'),
      throwsFormatException,
    );
    expect(
      () => decodeDm({'items': [], 'next': -1}, 'chat/controls'),
      throwsFormatException,
    );
  });

  testWidgets(
    'real inbox management pin and note; cancelling deletion has no side effect',
    (tester) async {
      final api = ChatApi();
      late DmController c;
      await tester.runAsync(() async {
        c = await controller(api);
      });
      await tester.pumpWidget(
        MaterialApp(home: DmInboxRoute(runtime: ChatRuntime(c))),
      );
      await tester.longPress(find.text('对方当前昵称'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dm-manage-pin')));
      await tester.pumpAndSettle();
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
      await tester.runAsync(() async {
        await c.sync();
      });
      await tester.pumpAndSettle();
      expect(api.dir['pinned'], isTrue);
      await tester.longPress(find.text('对方当前昵称'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dm-manage-note')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dm-note-input')),
        '本地备注检索',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
      await tester.runAsync(() async {
        await c.sync();
      });
      await tester.pumpAndSettle();
      expect(find.text('本地备注检索'), findsOneWidget);
      final puts = api.operationPuts;
      await tester.longPress(find.text('本地备注检索'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dm-manage-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.operationPuts, puts);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await close(c);
      });
    },
  );

  testWidgets(
    'chat reload removes a locally deleted row and reflects recall without stale text',
    (tester) async {
      final api = ChatApi();
      late DmController c;
      await tester.runAsync(() async {
        c = await controller(api);
        await c.send(textIntent('本地将删除的文字'));
        await c.sync();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DmChatRoute(
            runtime: ChatRuntime(c),
            own: const DmIdentity(id: p1.own, name: '本人面具'),
            peer: const DmIdentity(id: p1.peer, name: '对方当前昵称'),
            conversation: p1.conversation,
            sourcePost: p1.post,
          ),
        ),
      );
      for (var i = 0; i < 20 && find.text('本地将删除的文字').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(HhDirectMessageScreen), findsOneWidget);
      expect(find.text('本地将删除的文字'), findsOneWidget);
      await tester.runAsync(() async {
        final row = (await c.history(p1.own, p1.peer)).single;
        await c.deleteLocal(row['_id']);
      });
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('本地将删除的文字'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await close(c);
      });
    },
  );
}
