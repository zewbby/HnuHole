import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

const _post = '11111111-1111-4111-8111-111111111111';
const _case = '22222222-2222-4222-8222-222222222222';
const _notice = '33333333-3333-4333-8333-333333333333';
const _sanction = '44444444-4444-4444-8444-444444444444';
const _appeal = '55555555-5555-4555-8555-555555555555';

Map<String, dynamic> _report(
  String id, {
  String description = '',
  String reason = 'OTHER',
}) => {
  'state': 'SUBMITTED',
  'report': {
    'id': id,
    'caseId': _case,
    'state': 'PENDING',
    'postId': _post,
    'reason': reason,
    'description': description,
    'createdAt': '2026-10-18T00:00:00Z',
    'outcome': '',
    'explanation': '',
  },
};
Map<String, dynamic> _noticeJson({
  String id = _notice,
  String? identity,
  String? readAt,
  String title = '已收到你的举报',
}) => {
  'id': id,
  'eventId': id,
  'source': 'SERVER',
  'scope': identity == null ? 'ACCOUNT' : 'IDENTITY',
  if (identity != null) 'identityId': identity,
  'kind': 'REPORT_PROGRESS',
  'state': 'PENDING',
  'title': title,
  'body': '请查看处理进度',
  'createdAt': '2026-10-18T00:00:00Z',
  'readAt': readAt,
  'route': {'name': 'REPORT', 'resourceId': _post},
};
Map<String, dynamic> _appealJson({String id = _appeal}) => {
  'id': id,
  'sanctionId': _sanction,
  'caseId': _case,
  'version': 1,
  'action': 'MUTE',
  'state': 'PENDING',
  'ordinal': 1,
  'reason': '',
  'materials': [
    {
      'description': '复核材料',
      'createdAt': '2026-10-18T00:00:00Z',
      'images': <Object>[],
    },
  ],
};

class _Call {
  _Call(this.token, this.method, this.path, this.body, this.query);
  final String token, method, path;
  final Map<String, dynamic>? body;
  final Map<String, String>? query;
}

class _Api implements GovernanceApi {
  final calls = <_Call>[];
  late Future<Map<String, dynamic>> Function(_Call) respond;
  @override
  Future<GovernanceResponse> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final call = _Call(token, method, path, body, query);
    calls.add(call);
    return GovernanceResponse(await respond(call), identityTestRenewed);
  }
}

class _Fixture {
  _Fixture(this.auth, this.api, this.vault, this.controller);
  final IdentityTestFixture auth;
  final _Api api;
  final IdentityTestVault vault;
  final GovernanceController controller;
  static Future<_Fixture> create({IdentityTestVault? vault, _Api? api}) async {
    final auth = await IdentityTestFixture.create();
    auth.api.items = [
      identityTestItem(),
      identityTestItem(id: identityTestSecondId, name: '面具二', original: false),
    ];
    final remote = api ?? _Api(), pending = vault ?? IdentityTestVault();
    remote.respond = (call) async => call.path == '/api/v1/system-notifications'
        ? {'items': <Object>[], 'nextBefore': null}
        : call.method == 'GET'
        ? {'state': 'NOT_SUBMITTED', 'retryToken': _case}
        : _report(
            call.path.split('/').last,
            description: call.body!['description'] as String,
          );
    final c = GovernanceController(
      api: remote,
      sessions: auth.sessions,
      authStore: auth.store,
      identitiesApi: auth.api,
      pendingStore: GovernancePendingStore(pending),
    );
    await c.pendingStore.get(identityTestAccount);
    return _Fixture(auth, remote, pending, c);
  }

  Future<bool> submit({String description = ''}) => controller.submitReport(
    postId: _post,
    identityId: identityTestId,
    reason: 'OTHER',
    description: description,
    images: [],
  );
  void dispose() {
    controller.dispose();
    auth.dispose();
  }
}

void _paginationTests() {
  test(
    'appeal material page keeps opaque cursor and rejects repeated cursor',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      const cursor =
          '2026-10-18T00:00:00.123456789Z|55555555-5555-4555-8555-555555555555';
      f.api.respond = (_) async => {
        'items': [
          {
            'description': '追加材料',
            'createdAt': '2026-10-18T01:00:00Z',
            'images': <Object>[],
          },
        ],
        'nextCursor': null,
      };
      final page = await f.controller.readAppealMaterials(_appeal, cursor);
      expect(page!.items.single['description'], '追加材料');
      expect(f.api.calls.single.query, {'cursor': cursor});
      f.api.respond = (_) async => {'items': <Object>[], 'nextCursor': cursor};
      expect(await f.controller.readAppealMaterials(_appeal, cursor), isNull);
    },
  );
  test('appeal receipt accepts bounded first batch and following cursor without admin fields', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async => {
      ..._appealJson(),
      'nextMaterialsCursor': 'opaque-cursor',
    };
    expect(
      await f.controller.readResource(
        const NotificationRoute('APPEAL', _appeal),
      ),
      isNotNull,
    );
    f.api.respond = (_) async => {..._appealJson(), 'platformNumber': '123456'};
    expect(
      await f.controller.readResource(
        const NotificationRoute('APPEAL', _appeal),
      ),
      isNull,
    );
  });
  testWidgets(
    'appeal material pagination appends batches and preserves them on failure',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (call) async {
        if (call.query?['cursor'] == 'first-cursor') {
          return {
            'items': [
              {
                'description': '第二批材料',
                'createdAt': '2026-10-18T01:00:00Z',
                'images': <Object>[],
              },
            ],
            'nextCursor': 'second-cursor',
          };
        }
        throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppealMaterialStream(
                controller: f.controller,
                appealId: _appeal,
                initialMaterials: const [
                  {
                    'description': '第一批材料',
                    'createdAt': '2026-10-18T00:00:00Z',
                    'images': <Object>[],
                  },
                ],
                nextCursor: 'first-cursor',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('加载后续材料'));
      await tester.pumpAndSettle();
      expect(find.text('已提交材料：第一批材料'), findsOneWidget);
      expect(find.text('已提交材料：第二批材料'), findsOneWidget);
      await tester.tap(find.text('加载后续材料'));
      await tester.pumpAndSettle();
      expect(find.text('已提交材料：第一批材料'), findsOneWidget);
      expect(find.text('已提交材料：第二批材料'), findsOneWidget);
      expect(find.text('后续材料暂时无法读取，已显示的材料仍保留。'), findsOneWidget);
    },
  );
  testWidgets('late material page after logout cannot restore old evidence', (
    tester,
  ) async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final wait = Completer<Map<String, dynamic>>();
    f.api.respond = (_) async => wait.future;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppealMaterialStream(
            controller: f.controller,
            appealId: _appeal,
            initialMaterials: const [
              {
                'description': '原材料',
                'createdAt': '2026-10-18T00:00:00Z',
                'images': <Object>[],
              },
            ],
            nextCursor: 'cursor',
          ),
        ),
      ),
    );
    await tester.tap(find.text('加载后续材料'));
    await tester.pump();
    await f.auth.sessions.logout();
    wait.complete({
      'items': [
        {
          'description': '不得恢复的材料',
          'createdAt': '2026-10-18T01:00:00Z',
          'images': <Object>[],
        },
      ],
      'nextCursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('已提交材料：原材料'), findsNothing);
    expect(find.text('已提交材料：不得恢复的材料'), findsNothing);
    expect(find.text('会话已变化，请重新进入后查看材料。'), findsOneWidget);
  });
}

void main() {
  _paginationTests();
  test(
    'comment report original result cannot resolve a different target',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (call) async => _report(call.path.split('/').last);
      expect(
        await f.controller.submitReport(
          postId: _post,
          commentId: _appeal,
          identityId: identityTestId,
          reason: 'OTHER',
          description: '',
          images: [],
        ),
        isFalse,
      );
      expect(f.controller.pending, isNotNull);
      expect(f.api.calls.first.body!['commentId'], _appeal);
      final original = f.api.calls.first.path;
      f.api.respond = (call) async {
        final result = _report(call.path.split('/').last);
        (result['report'] as Map)['commentId'] = _appeal;
        return result;
      };
      expect(await f.controller.reconcilePending(), isTrue);
      expect(f.api.calls.last.path, original);
      expect(f.controller.pending, isNull);
    },
  );
  test(
    'comment report lost response reconciles the same comment and original key',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (call) async {
        if (call.method == 'PUT')
          throw const GovernanceFailure(null, 'TIMEOUT', uncertain: true);
        final result = _report(call.path.split('/').last);
        (result['report'] as Map)['commentId'] = _appeal;
        return result;
      };
      expect(
        await f.controller.submitReport(
          postId: _post,
          commentId: _appeal,
          identityId: identityTestId,
          reason: 'OTHER',
          description: '',
          images: [],
        ),
        isTrue,
      );
      expect(f.api.calls.map((c) => c.method), ['PUT', 'GET']);
      expect(f.api.calls.map((c) => c.path).toSet().length, 1);
      expect(f.controller.pending, isNull);
    },
  );
  test(
    'report intent is durable before request and successful receipt clears it',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (call) async {
        expect(f.vault.value, contains(call.path.split('/').last));
        expect(f.vault.value, contains('原材料'));
        return _report(call.path.split('/').last, description: '原材料');
      };
      expect(await f.submit(description: '原材料'), isTrue);
      expect(f.controller.pending, isNull);
      expect(await f.controller.pendingStore.get(identityTestAccount), isNull);
      expect(f.api.calls.single.method, 'PUT');
    },
  );

  test(
    'lost report response automatically reconciles original request',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (call) async {
        if (call.method == 'PUT') {
          throw const GovernanceFailure(null, 'TIMEOUT', uncertain: true);
        }
        return _report(call.path.split('/').last);
      };
      expect(await f.submit(), isTrue);
      expect(f.api.calls.map((c) => c.method), ['PUT', 'GET']);
      expect(f.api.calls.map((c) => c.path).toSet().length, 1);
      expect(f.controller.pending, isNull);
    },
  );

  test('unknown remains pending, second submit is blocked, retry keeps exact key/material', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async =>
        throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
    expect(await f.submit(description: '不改材料'), isFalse);
    final first = f.api.calls.first;
    expect(f.controller.pending, isNotNull);
    final count = f.api.calls.length;
    expect(await f.submit(description: '另一个请求'), isFalse);
    expect(f.api.calls.length, count);
    f.api.respond = (call) async => call.method == 'GET'
        ? {'state': 'NOT_SUBMITTED', 'retryToken': _case}
        : _report(first.path.split('/').last, description: '不改材料');
    expect(await f.controller.reconcilePending(retry: true), isTrue);
    final last = f.api.calls.last;
    expect(last.path, first.path);
    expect({...last.body!}..remove('retryToken'), first.body);
    expect(last.body!['retryToken'], _case);
  });

  test('mismatched submitted receipt cannot discard original intent', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async => _report(_case);
    expect(await f.submit(), isFalse);
    expect(f.controller.pending, isNotNull);
    expect(await f.controller.pendingStore.get(identityTestAccount), isNotNull);
  });
  test(
    'retry token is durably saved before sending and sealed retry only queries',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (_) async =>
          throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
      await f.submit(description: '原举报');
      var queries = 0;
      f.api.respond = (call) async {
        if (call.method == 'GET') {
          return {
            'state': 'NOT_SUBMITTED',
            'retryToken': ++queries == 1 ? _case : _notice,
          };
        }
        expect(call.body!['retryToken'], _case);
        expect(f.vault.value, contains('"retryToken":"$_case"'));
        throw const GovernanceFailure(409, 'REPORT_ATTEMPT_SEALED');
      };
      final before = f.api.calls.length;
      expect(await f.controller.reconcilePending(retry: true), isFalse);
      expect(f.api.calls.skip(before).map((c) => c.method), [
        'GET',
        'PUT',
        'GET',
      ]);
      expect(f.controller.pending!['retryToken'], _notice);
      expect((f.controller.pending!['body'] as Map)['description'], '原举报');
    },
  );
  test('retry token storage failure prevents replacement PUT', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async =>
        throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
    await f.submit();
    f.api.respond = (_) async => {
      'state': 'NOT_SUBMITTED',
      'retryToken': _case,
    };
    f.vault.failContaining = 'retryToken';
    final before = f.api.calls.length;
    expect(await f.controller.reconcilePending(retry: true), isFalse);
    expect(f.api.calls.skip(before).map((c) => c.method), ['GET']);
    expect(f.controller.pending, isNotNull);
  });

  test('vault failure prevents transmission', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.vault.failContaining = 'queryPath';
    expect(await f.submit(), isFalse);
    expect(f.api.calls, isEmpty);
    expect(f.controller.error, contains('安全保存失败'));
  });

  test(
    'uncertain committed vault write is recovered before a new key sends',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.vault.failContaining = 'queryPath';
      f.vault.commitUnknown = true;
      expect(await f.submit(description: '保留'), isFalse);
      expect(f.api.calls, isEmpty);
      expect(await f.submit(description: '不能另发'), isFalse);
      expect(f.controller.pending!['body'], containsPair('description', '保留'));
      expect(f.api.calls, isEmpty);
    },
  );

  test('original unknown cannot be discarded without NOT_SUBMITTED', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async =>
        throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
    await f.submit();
    expect(await f.controller.reconcilePending(discard: true), isFalse);
    expect(f.controller.pending, isNotNull);
    f.api.respond = (_) async => {
      'state': 'NOT_SUBMITTED',
      'retryToken': _case,
    };
    expect(await f.controller.reconcilePending(discard: true), isTrue);
    expect(f.controller.pending, isNull);
  });
  test('restart restores original pending material without creating another request', () async {
    final first = await _Fixture.create();
    first.api.respond = (_) async =>
        throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
    await first.submit(description: '重启保留的材料');
    final original = first.controller.pending!['id'];
    final vault = first.vault;
    first.dispose();
    final restored = await _Fixture.create(vault: vault);
    addTearDown(restored.dispose);
    await restored.controller.restorePending();
    expect(restored.controller.pending!['id'], original);
    expect(
      (restored.controller.pending!['body'] as Map)['description'],
      '重启保留的材料',
    );
    expect(
      restored.api.calls.every(
        (c) => c.method == 'GET' && c.path.endsWith(original as String),
      ),
      isTrue,
    );
    expect(await restored.submit(description: '不能换键'), isFalse);
  });
  test('confirmed closed account clears only its pending material', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async =>
        throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
    await f.submit();
    await f.controller.purgeClosedAccount(identityTestAccount);
    expect(await f.controller.pendingStore.get(identityTestAccount), isNull);
  });

  test(
    'late submission after logout cannot publish or clear another authority',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final waiting = Completer<Map<String, dynamic>>(),
          entered = Completer<void>();
      f.api.respond = (_) async {
        entered.complete();
        return waiting.future;
      };
      final submitting = f.submit();
      await entered.future;
      final path = f.api.calls.single.path;
      await f.auth.sessions.logout();
      waiting.complete(_report(path.split('/').last));
      expect(await submitting, isFalse);
      expect(f.controller.available, isFalse);
      expect(f.controller.pending, isNull);
      expect(
        await f.controller.pendingStore.get(identityTestAccount),
        isNotNull,
      );
    },
  );

  test(
    'notification list never marks all read and preserves opaque paging cursor',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      const cursor =
          '2026-10-18T00:00:00.123456789Z|33333333-3333-4333-8333-333333333333';
      f.api.respond = (_) async => {
        'items': [_noticeJson()],
        'nextBefore': cursor,
      };
      await f.controller.loadNotifications();
      expect(f.controller.items.single.unread, isTrue);
      expect(f.api.calls.every((c) => c.method == 'GET'), isTrue);
      await f.controller.loadNotifications(more: true);
      expect(f.api.calls.last.query!['before'], cursor);
      expect(f.controller.items.length, 1);
    },
  );

  test('503 authorization failure hides ordinary notifications and suspends authority', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async => {
      'items': [_noticeJson()],
    };
    await f.controller.loadNotifications();
    expect(f.controller.items, isNotEmpty);
    f.api.respond = (_) async => throw const GovernanceFailure(
      503,
      'AUTHORIZATION_UNAVAILABLE',
      uncertain: true,
    );
    await f.controller.loadNotifications();
    expect(f.controller.available, isFalse);
    expect(f.controller.items, isEmpty);
    expect(f.auth.sessions.status, AuthStatus.unavailable);
  });
  test('cross identity notifications are rejected before display', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (_) async => {
      'items': [_noticeJson(identity: identityTestId)],
    };
    await f.controller.loadNotifications();
    expect(f.controller.items, isEmpty);
    expect(f.controller.error, isNotNull);
  });

  test('opening one account notice marks only it read without removing or moving it', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.respond = (call) async {
      if (call.path == '/api/v1/system-notifications') {
        return {
          'items': [_noticeJson(), _noticeJson(id: _case)],
        };
      }
      return _noticeJson(
        readAt: call.method == 'POST' ? '2026-10-18T01:00:00Z' : null,
      );
    };
    await f.controller.loadNotifications();
    expect(await f.controller.openNotice(_notice), isNotNull);
    expect(f.controller.items.map((n) => n.id), [_notice, _case]);
    expect(f.controller.items.first.unread, isFalse);
    expect(f.controller.items.last.unread, isTrue);
    expect(
      f.api.calls.where((c) => c.method == 'POST').single.path,
      '/api/v1/system-notifications/$_notice/read',
    );
  });

  test(
    'opening identity notice selects owner while keeping other unread state',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.loadIdentities();
      f.api.respond = (call) async => _noticeJson(
        identity: identityTestSecondId,
        readAt: call.method == 'POST' ? '2026-10-18T01:00:00Z' : null,
      );
      f.api.respond = (call) async =>
          call.path == '/api/v1/system-notifications'
          ? {'items': <Object>[]}
          : _noticeJson(
              identity: identityTestSecondId,
              readAt: call.method == 'POST' ? '2026-10-18T01:00:00Z' : null,
            );
      expect(
        await f.controller.openNotice(
          _notice,
          targetIdentityId: identityTestSecondId,
        ),
        isNotNull,
      );
      expect(f.controller.selectedIdentityId, identityTestSecondId);
      expect(f.api.calls.last.query, {'identityId': identityTestSecondId});
    },
  );

  test(
    'late previous identity list cannot overwrite current identity',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.loadIdentities();
      final waiting = Completer<Map<String, dynamic>>();
      f.api.respond = (call) async =>
          call.query?['identityId'] == identityTestId
          ? waiting.future
          : {
              'items': [_noticeJson(identity: identityTestSecondId)],
            };
      final old = f.controller.selectIdentity(identityTestId);
      await Future<void>.delayed(Duration.zero);
      await f.controller.selectIdentity(identityTestSecondId);
      waiting.complete({
        'items': [_noticeJson(identity: identityTestId)],
      });
      await old;
      expect(f.controller.items.single.identityId, identityTestSecondId);
    },
  );

  test(
    'appeal query uses original request id before retry and validates sanction',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (_) async =>
          throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
      expect(await f.controller.submitAppeal(_sanction, '复核材料', []), isFalse);
      final p = f.controller.pending!;
      expect(
        p['queryPath'],
        '/api/v1/sanctions/$_sanction/appeal-requests/${p['id']}',
      );
      f.api.respond = (call) async => call.method == 'GET'
          ? {'state': 'NOT_SUBMITTED', 'retryToken': _case}
          : _appealJson();
      expect(await f.controller.reconcilePending(retry: true), isTrue);
    },
  );

  test(
    'supplement uses three-image limit without creating another appeal',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (_) async => _appealJson();
      expect(await f.controller.supplementAppeal(_appeal, '复核材料', []), isTrue);
      expect(
        f.api.calls.single.path,
        startsWith('/api/v1/appeals/$_appeal/materials/'),
      );
      final image = EvidenceImage('image/png', Uint8List.fromList([1]));
      expect(
        () => f.controller.supplementAppeal(_appeal, '', List.filled(4, image)),
        throwsFormatException,
      );
    },
  );

  test(
    'notice DTO rejects private fields, invalid scope and arbitrary URL route',
    () {
      expect(
        () => SystemNotice.parse({
          ..._noticeJson(),
          'email': 'do-not-display@example.invalid',
        }),
        throwsFormatException,
      );
      expect(
        () => SystemNotice.parse({..._noticeJson(), 'scope': 'IDENTITY'}),
        throwsFormatException,
      );
      expect(
        () => SystemNotice.parse({
          ..._noticeJson(),
          'route': {'name': 'https://example.invalid', 'resourceId': _post},
        }),
        throwsFormatException,
      );
    },
  );

  test('strict decoder rejects duplicate keys and malformed unicode', () {
    expect(
      () =>
          GovernanceStrictJson('{"state":"SUBMITTED","state":"NOT_SUBMITTED"}')
              .decode(),
      throwsFormatException,
    );
    expect(
      () => GovernanceStrictJson('{"x":"\\ud800"}').decode(),
      throwsFormatException,
    );
  });

  testWidgets(
    'notification list is a concrete time stream and opens one read detail',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (call) async {
        if (call.path == '/api/v1/system-notifications') {
          return {
            'items': [_noticeJson()],
          };
        }
        if (call.path.startsWith('/api/v1/reports/')) return _report(_post);
        return _noticeJson(
          readAt: call.method == 'POST' ? '2026-10-18T01:00:00Z' : null,
        );
      };
      await tester.pumpWidget(
        MaterialApp(home: SystemNotificationsScreen(controller: f.controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('已收到你的举报'), findsOneWidget);
      expect(f.api.calls.where((c) => c.method == 'POST'), isEmpty);
      await tester.tap(find.text('已收到你的举报'));
      await tester.pumpAndSettle();
      expect(find.text('通知详情'), findsOneWidget);
      expect(find.text('状态：待处理'), findsOneWidget);
      expect(find.text('重复举报'), findsNothing);
      expect(find.text('申诉'), findsNothing);
      expect(f.api.calls.where((c) => c.method == 'POST').length, 1);
    },
  );

  testWidgets(
    'report form has six reasons, preserves input and confirms abandonment',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReportScreen(
                      controller: f.controller,
                      postId: _post,
                      title: '被举报帖子',
                    ),
                  ),
                ),
                child: const Text('打开举报'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开举报'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('举报原因'));
      await tester.pumpAndSettle();
      for (final reason in reportReasons.values) {
        expect(find.text(reason), findsOneWidget);
      }
      await tester.tap(find.text('泄露隐私'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留本次说明');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('放弃本次材料？'), findsOneWidget);
      await tester.tap(find.text('继续填写'));
      await tester.pumpAndSettle();
      expect(find.text('保留本次说明'), findsOneWidget);
      expect(f.vault.value, isNull);
    },
  );
  testWidgets(
    'confirmed retry returns to source and cannot expose a new duplicate form',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.respond = (_) async =>
          throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
      await f.submit(description: '原材料');
      final id = f.controller.pending!['id'] as String;
      f.api.respond = (call) async => call.method == 'GET'
          ? {'state': 'NOT_SUBMITTED', 'retryToken': _case}
          : _report(id, description: '原材料');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReportScreen(
                      controller: f.controller,
                      postId: _post,
                      title: '原帖子',
                    ),
                  ),
                ),
                child: const Text('原页面'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('原页面'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('核对后重试原任务'));
      await tester.tap(find.text('核对后重试原任务'));
      await tester.pumpAndSettle();
      expect(find.text('原页面'), findsOneWidget);
      expect(find.text('提交举报'), findsNothing);
      expect(f.controller.pending, isNull);
    },
  );
  testWidgets(
    'small-screen notification selector and long identity support large text',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.auth.api.items = [identityTestItem(name: '很长的合规身份昵称名字')];
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: SystemNotificationsScreen(controller: f.controller),
        ),
      );
      await tester.pumpAndSettle();
      await f.controller.selectIdentity(identityTestId);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
