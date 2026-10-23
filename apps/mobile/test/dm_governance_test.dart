import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_governance_ui.dart';
import 'package:hnuhole_mobile/src/messaging/dm_notifications.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/system_notifications/governance_controller.dart';

import 'dm_reliability_test.dart' as p1;
import 'dm_chat_test.dart' as p2;

class _Vault implements AuthVault {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    if (fail) throw StateError('disk');
    value = v;
  }
}

class _Controller extends ChangeNotifier implements DmController {
  @override
  bool available = true;
  @override
  String scope = 'account:1';
  @override
  String? accountId = 'account';
  @override
  List<Map<String, dynamic>> conversations = [p2.directory()];
  void expire() {
    available = false;
    scope = 'expired';
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> incoming(int sequence, {int version = 1}) => {
  'messageId': p1.own,
  'sequence': sequence,
  'text': '证据原文$sequence',
  'identityId': p1.own,
  'senderId': p1.peer,
  'conversationId': p1.conversation,
  'kind': 'TEXT',
  'evidenceVersion': version,
  'outgoing': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('snapshot includes all available interval entries and explicit unknown gaps; immutable after recall', () async {
    final rows = [
      incoming(1),
      incoming(3),
      incoming(4, version: 0),
      incoming(5),
    ];
    final snapshot = await dmEvidenceSnapshot(
      directory: p2.directory(),
      rows: rows,
      first: 1,
      last: 4,
      photo: (_, _) async => Uint8List(0),
    );
    rows[0]['text'] = '改写';
    rows[1]['recalled'] = true;
    rows.add(incoming(6));
    final entries = snapshot['entries'] as List;
    expect(entries.length, 4);
    expect(entries[0]['text'], '证据原文1');
    expect(entries[1]['gap'], 'LOCAL_UNAVAILABLE');
    expect(entries[1]['kind'], 'UNKNOWN');
    expect(entries[2]['text'], '证据原文3');
    expect(entries[3]['gap'], 'UNVERIFIABLE');
    expect(entries[3]['text'], '');
    expect(snapshot.containsKey('authorized'), false);
  });
  test(
    'unverifiable-only and oversized ranges never masquerade as valid evidence',
    () async {
      for (final range in [(1, 1), (1, 201)]) {
        await expectLater(
          dmEvidenceSnapshot(
            directory: p2.directory(),
            rows: [incoming(1, version: 0)],
            first: range.$1,
            last: range.$2,
            photo: (_, _) async => Uint8List(0),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'P2 image without evidenceVersion remains reportable beside P3 text',
    () async {
      final oldImage = {
        ...incoming(1),
        'kind': 'IMAGE',
        'media': p2.descriptor(p1.post),
      }..remove('evidenceVersion');
      final snapshot = await dmEvidenceSnapshot(
        directory: p2.directory(),
        rows: [oldImage, incoming(2)],
        first: 1,
        last: 2,
        photo: (_, _) async => Uint8List.fromList(p2.photo),
      );
      expect(snapshot['entries'][0]['gap'], '');
      expect(base64Decode(snapshot['entries'][0]['data']), p2.photo);
      expect(snapshot['entries'][1]['text'], '证据原文2');
    },
  );
  test('fixed image bytes remain independent after local deletion', () async {
    final original = Uint8List.fromList(p2.photo);
    final row = {
      ...incoming(1),
      'kind': 'IMAGE',
      'media': p2.descriptor(p1.post),
    };
    final snapshot = await dmEvidenceSnapshot(
      directory: p2.directory(),
      rows: [row],
      first: 1,
      last: 1,
      photo: (_, sender) async {
        expect(sender, p1.peer);
        return original;
      },
    );
    original.fillRange(0, original.length, 0);
    expect(base64Decode(snapshot['entries'][0]['data']), p2.photo);
  });
  test('P2 outgoing image alone uses original sender bytes without evidenceVersion', () async {
    final snapshot = await dmEvidenceSnapshot(
      directory: p2.directory(),
      rows: [
        {
          'outgoing': true,
          'messageType': 'IMAGE',
          'receipt': {'messageId': p1.post, 'sequence': 1},
          'intent': {'mediaId': p1.post},
        },
      ],
      first: 1,
      last: 1,
      photo: (id, sender) async {
        expect(id, p1.post);
        expect(sender, p1.own);
        return Uint8List.fromList(p2.photo);
      },
    );
    expect(snapshot['entries'][0]['gap'], '');
    expect(snapshot['entries'][0]['kind'], 'IMAGE');
    expect(base64Decode(snapshot['entries'][0]['data']), p2.photo);
  });
  test(
    'available images over budget reject the range instead of inventing gaps',
    () async {
      final rows = [
        for (var i = 1; i <= 3; i++)
          {...incoming(i), 'kind': 'IMAGE', 'media': p2.descriptor(p1.post)},
      ];
      await expectLater(
        dmEvidenceSnapshot(
          directory: p2.directory(),
          rows: rows,
          first: 1,
          last: 3,
          photo: (_, _) async => Uint8List(9 * 1024 * 1024),
        ),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'evidence preview immediately hides private text when authority expires',
    (tester) async {
      final c = _Controller();
      final snapshot = await dmEvidenceSnapshot(
        directory: p2.directory(),
        rows: [incoming(1)],
        first: 1,
        last: 1,
        photo: (_, _) async => Uint8List(0),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DmEvidencePreview(
            controller: c,
            scope: c.scope,
            snapshot: snapshot,
            select: true,
          ),
        ),
      );
      expect(find.text('证据原文1'), findsOneWidget);
      c.expire();
      await tester.pump();
      expect(find.text('证据原文1'), findsNothing);
      expect(find.text('使用这份证据'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('pending DM report persists a full 200-item snapshot with same request identity', () async {
    final vault = _Vault(), store = GovernancePendingStore(_Vault());
    final actual = GovernancePendingStore(vault);
    final pending = {
      'id': p1.post,
      'kind': 'DM_REPORT',
      'path': '/api/v1/dm/governance/reports/${p1.post}',
      'queryPath': '/api/v1/dm/governance/reports/${p1.post}',
      'body': {
        'entries': [for (var i = 1; i <= 200; i++) incoming(i)],
      },
    };
    await actual.put(p1.own, pending, () => true);
    final reopened = GovernancePendingStore(vault);
    expect((await reopened.get(p1.own))!['body']['entries'].length, 200);
    expect(await reopened.get(p1.peer), isNull);
    await actual.close();
    await reopened.close();
    await store.close();
  });
  test(
    'DM directory receipt retains exact selected block without account fields',
    () {
      final directory = {...p2.directory(), 'ownBlockId': p1.own};
      expect(
        decodeDm({
          'items': [directory],
        }, 'chat/conversations')['items'][0]['ownBlockId'],
        p1.own,
      );
      expect(
        () => decodeDm({
          'items': [
            {...directory, 'accountId': p1.peer},
          ],
        }, 'chat/conversations'),
        throwsFormatException,
      );
      expect(
        decodeDm({
          'state': 'SENT',
          'attempt': 1,
          'messageId': p1.own,
          'conversationId': p1.conversation,
          'sequence': 1,
          'acceptedAt': '2026-10-22T00:00:00Z',
          'evidenceVersion': 1,
        }, 'commands/${p1.post}')['evidenceVersion'],
        1,
      );
    },
  );

  test(
    'P3 absent receipt and text directory preserve strict compatibility',
    () {
      for (final absent in [
        {'state': 'ABSENT', 'attempt': 0},
        {'state': 'ABSENT', 'attempt': 0, 'evidenceVersion': 0},
      ]) {
        expect(decodeDm(absent, 'commands/${p1.post}')['state'], 'ABSENT');
      }
      for (final extra in [
        {'evidenceVersion': 1},
        {'messageId': p1.own},
        {'evidenceVersion': null},
      ]) {
        expect(
          () => decodeDm({
            'state': 'ABSENT',
            'attempt': 0,
            ...extra,
          }, 'commands/${p1.post}'),
          throwsFormatException,
        );
      }
      final row = Map<String, dynamic>.from(p2.directory())
        ..removeWhere(
          (key, _) => !{
            'id',
            'identityId',
            'peerId',
            'peerName',
            'sourcePostId',
            'sequence',
            'unread',
            'waiting',
            'canSend',
          }.contains(key),
        );
      row['ownBlockId'] = p1.post;
      expect(
        decodeDm({
          'items': [row],
        }, 'conversations')['items'][0]['ownBlockId'],
        p1.post,
      );
      expect(
        () => decodeDm({
          'items': [
            {...row, 'accountId': p1.peer},
          ],
        }, 'conversations'),
        throwsFormatException,
      );
    },
  );
  group('private local notifications', () {
    const channel = MethodChannel('test/dm-notifications');
    late List<MethodCall> calls;
    late _Vault vault;
    late DmNotifications n;
    late _Controller c;
    setUp(() {
      calls = [];
      vault = _Vault();
      c = _Controller();
      n = DmNotifications(
        environment: 'test-origin',
        preferences: vault,
        channel: channel,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      n.dispose();
      c.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    test('default sends neither names nor content; explicit preview uses public peer name only', () async {
      await n.start();
      await n.bind('account');
      c.conversations[0]['note'] = 'private note';
      await n.incoming([incoming(1)], 'account', c);
      final hidden = Map.from(calls.last.arguments);
      expect(hidden['preview'], false);
      expect(hidden['sender'], '');
      expect(hidden['text'], '');
      await n.setPreview('account', true);
      await n.incoming([incoming(2)], 'account', c);
      final preview = Map.from(calls.last.arguments);
      expect(preview['sender'], '对方当前昵称');
      expect(preview['text'], '证据原文2');
      expect(preview.values, isNot(contains('private note')));
    });
    test(
      'muted, stale and cross-account callbacks do not post notifications',
      () async {
        await n.start();
        await n.bind('account');
        calls.clear();
        c.conversations[0]['muted'] = true;
        await n.incoming([incoming(1)], 'account', c);
        c.conversations[0]['muted'] = false;
        await n.incoming([incoming(1)], 'other', c);
        c.expire();
        await n.incoming([incoming(1)], 'account', c);
        expect(calls.where((call) => call.method == 'show'), isEmpty);
      },
    );
    test('cold click is read before bind clears notifications; cannot restore to another owner', () async {
      final hold = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'takeTap') {
              await hold.future;
              return {
                'scope': n.scopeFor('account'),
                'identityId': p1.own,
                'conversationId': p1.conversation,
              };
            }
            return null;
          });
      final start = n.start(), bind = n.bind('account');
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), ['takeTap']);
      hold.complete();
      await start;
      await bind;
      expect(n.pending?.identity, p1.own);
      await n.bind('other');
      expect(n.pending, isNull);
    });
    test('failed preview persistence stays private and opt-out cancels old expanded notifications', () async {
      await n.start();
      await n.bind('account');
      vault.fail = true;
      await expectLater(n.setPreview('account', true), throwsStateError);
      expect(n.preview('account'), false);
      vault.fail = false;
      await n.setPreview('account', true);
      await n.setPreview('account', false);
      expect(calls.last.method, 'clear');
      expect(n.preview('account'), false);
    });
  });
}
