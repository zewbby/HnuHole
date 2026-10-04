import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

void main() {
  test('initial nickname draft restores after recreation and same-account re-login', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    await f.controller.load();
    expect(await f.controller.saveInitialDraft('春风'), isTrue);
    f.controller.cancelView();
    final restarted = await IdentityTestFixture.create(vault: f.vault, initialize: false);
    addTearDown(restarted.dispose);
    await restarted.controller.load();
    expect(restarted.controller.initialNickname, '春风');
    await restarted.sessions.logout();
    await restarted.sessions.login('private_user', 'valid password');
    await restarted.controller.load();
    expect(restarted.controller.initialNickname, '春风');
    restarted.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await restarted.controller.create('春风');
    expect(restarted.store.current!.identityDrafts[identityTestAccount]['nickname'], '春风');
    expect(await restarted.controller.saveInitialDraft('改动原请求'), isFalse);
    expect(await restarted.controller.discardInitialDraft(), isFalse);
    restarted.api.queryOutcome = IdentityChangeOutcome(committed: true,
      operation: IdentityOperation.create, identityId: identityTestId,
      sessionExpiresAt: identityTestRenewed);
    restarted.api.items = [identityTestItem(name: '春风')]; restarted.api.createdCount = 1;
    await restarted.controller.reconcilePending();
    expect(restarted.store.current!.identityDrafts, isEmpty);
  });

  test('draft never appears for another account and explicit discard is durable', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    await f.controller.load();
    await f.controller.saveInitialDraft('春风');
    await f.sessions.logout();
    f.sessionApi.account = '00000000-0000-0000-0000-000000000002';
    f.sessionApi.username = 'other_user';
    await f.sessions.login('other_user', 'valid password');
    await f.controller.load();
    expect(f.controller.initialNickname, '');
    await f.controller.saveInitialDraft('秋雨');
    expect(await f.controller.discardInitialDraft(), isTrue);
    expect(f.store.current!.identityDrafts[identityTestAccount]['nickname'], '春风');
    expect(f.store.current!.identityDrafts.containsKey(f.sessionApi.account), isFalse);
  });

  test('queued stale draft write cannot persist after authority is cleared', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    await f.controller.load();
    final release = Completer<void>();
    f.vault.nextReadWait = release;
    final save = f.controller.saveInitialDraft('春风');
    await f.vault.readBlocked.future;
    f.sessions.sessionUnavailable(identityTestToken);
    release.complete();
    expect(await save, isFalse);
    expect(f.store.current!.identityDrafts, isEmpty);
  });

  test('oversized legal draft does not poison the authentication store', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    await f.controller.load();
    expect(await f.controller.saveInitialDraft('a${List.filled(300, '\u0301').join()}b'), isFalse);
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.store.current, isNotNull);
  });

  test('zero identities permits existing directory browsing and no automatic creation', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    await f.controller.load();
    expect(f.controller.directory!.identities, isEmpty);
    expect(f.api.submissions, isEmpty);
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.directory.channels, hasLength(7));
  });

  test('create intent is durable before send and metadata before publication', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.beforeSubmit = () {
      final saved = jsonDecode(f.vault.value!) as Map<String, dynamic>;
      expect(saved['identityChanges'][identityTestAccount]['nickname'], '面具一');
      expect(saved['identityChanges'][identityTestAccount]['state'], 'UNKNOWN');
      expect(f.controller.directory, isNull);
    };
    await f.controller.create('面具一');
    final key = f.api.submissions.single['key'] as String;
    expect(AuthCrypto.decode(key, bytes: 16), hasLength(16));
    expect(f.controller.status, IdentityManagementStatus.ready);
    expect(f.store.current!.session!.expiresAt, identityTestRenewed);
    expect(f.store.current!.identityChanges, isEmpty);
    expect(f.controller.directory!.identities.single.nickname, '面具一');
  });

  test('unknown survives process recreation and missing receipt retains original intent', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.controller.create('春风');
    final key = f.api.submissions.single['key'];
    final restarted = await IdentityTestFixture.create(vault: f.vault, initialize: false);
    addTearDown(restarted.dispose);
    await restarted.controller.load();
    expect(restarted.api.queries.single['key'], key);
    expect(restarted.api.submissions, isEmpty);
    expect(restarted.controller.status, IdentityManagementStatus.retryRequired);
    expect(restarted.store.current!.identityChanges[identityTestAccount]['key'], key);
    await restarted.controller.create('新的名字');
    expect(restarted.api.submissions, isEmpty);
    await restarted.controller.retryPending();
    expect(restarted.api.queries, hasLength(2));
    expect(restarted.api.submissions.single['key'], key);
    expect(restarted.api.submissions.single['nickname'], '春风');
  });

  test('retry queries committed original and never repeats mutation', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.unknownOutcome);
    await f.controller.create('春风');
    f.api.items = [identityTestItem(name: '春风')];
    f.api.createdCount = 1;
    f.api.queryOutcome = IdentityChangeOutcome(committed: true,
      operation: IdentityOperation.create, identityId: identityTestId,
      sessionExpiresAt: identityTestRenewed);
    await f.controller.retryPending();
    expect(f.api.submissions, hasLength(1));
    expect(f.controller.status, IdentityManagementStatus.ready);
    expect(f.store.current!.identityChanges, isEmpty);
  });

  test('durable REJECTED tombstone clears original without resubmission', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.controller.create('春风');
    f.api.queryOutcome = IdentityChangeOutcome(committed: false,
      operation: IdentityOperation.create, errorCode: 'IDENTITY_LIMIT',
      sessionExpiresAt: identityTestRenewed);
    await f.controller.retryPending();
    expect(f.api.submissions, hasLength(1));
    expect(f.store.current!.identityChanges, isEmpty);
    expect(f.controller.error!.code, 'IDENTITY_LIMIT');
    expect(f.store.current!.session!.expiresAt, identityTestRenewed);
  });

  test('business error without matching durable rejection cannot clear unknown original', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.rejected,
      statusCode: 409, code: 'IDENTITY_LIMIT');
    await f.controller.create('春风');
    expect(f.api.queries, hasLength(1));
    expect(f.controller.status, IdentityManagementStatus.retryRequired);
    final key = f.store.current!.identityChanges[identityTestAccount]['key'];
    f.api.queryOutcome = IdentityChangeOutcome(committed: true,
      operation: IdentityOperation.create, identityId: identityTestId,
      sessionExpiresAt: identityTestRenewed);
    f.api.items = [identityTestItem(name: '春风')];
    f.api.createdCount = 1;
    await f.controller.reconcilePending();
    expect(f.api.queries.last['key'], key);
    expect(f.api.submissions, hasLength(1));
    expect(f.controller.directory!.identities.single.nickname, '春风');
  });

  test('malformed and conflicting result preserve immutable original', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.controller.create('春风');
    final anchor = Map<String, dynamic>.from(f.store.current!.identityChanges[identityTestAccount]);
    f.api.queryOutcome = IdentityChangeOutcome(committed: false,
      operation: IdentityOperation.delete, errorCode: 'IDENTITY_NOT_FOUND',
      sessionExpiresAt: identityTestRenewed);
    await f.controller.reconcilePending();
    expect(f.store.current!.identityChanges[identityTestAccount], anchor);
    f.api.queryFailure = const AuthFailure(kind: AuthFailureKind.rejected,
      statusCode: 409, code: 'IDENTITY_CHANGE_CONFLICT');
    await f.controller.retryPending();
    expect(f.store.current!.identityChanges[identityTestAccount], anchor);
    expect(f.api.submissions, hasLength(1));
  });

  test('late mutation cannot publish or clear intent after logout and same-account re-login', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitWait = Completer<IdentityChangeOutcome>();
    final request = f.controller.create('春风');
    await f.api.submissionStarted.future;
    final original = f.store.current!.identityChanges[identityTestAccount]['key'];
    await f.sessions.logout();
    await f.sessions.login('private_user', 'valid password');
    f.api.submitWait!.complete(IdentityChangeOutcome(committed: true,
      operation: IdentityOperation.create, identityId: identityTestId,
      sessionExpiresAt: DateTime.utc(2035)));
    await request;
    expect(f.store.current!.identityChanges[identityTestAccount]['key'], original);
    expect(f.store.current!.identityChanges[identityTestAccount]['state'], 'UNKNOWN');
    expect(f.store.current!.session!.expiresAt, identityTestExpiry);
    expect(f.controller.directory, isNull);
    await f.controller.load();
    expect(f.api.queries.single['token'], identityTestOtherToken);
    expect(f.api.queries.single['key'], original);
  });

  test('another account does not query replay or overwrite first account pending', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.controller.create('春风');
    final first = f.store.current!.identityChanges[identityTestAccount];
    await f.sessions.logout();
    f.sessionApi.account = '00000000-0000-0000-0000-000000000002';
    f.sessionApi.username = 'other_user';
    await f.sessions.login('other_user', 'valid password');
    await f.controller.load();
    expect(f.api.queries, isEmpty);
    expect(f.controller.directory!.identities, isEmpty);
    await f.controller.create('秋雨');
    expect(f.store.current!.identityChanges[identityTestAccount], first);
    expect(f.store.current!.identityChanges[f.sessionApi.account]['username'], 'other_user');
    expect(f.api.submissions.last['nickname'], '秋雨');
    expect(f.api.submissions.last['key'], isNot(first['key']));
  });

  test('unknown durable initial write sends nothing and result-write failure stays recoverable', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.vault.failContaining = '"operation":"CREATE"';
    f.vault.commitUnknown = true;
    await f.controller.create('春风');
    expect(f.api.submissions, isEmpty);
    expect(f.controller.directory, isNull);
    expect(f.controller.status, IdentityManagementStatus.storageFailure);
    await f.sessions.retry();
    await f.controller.load();
    expect(f.controller.status, IdentityManagementStatus.retryRequired);
    expect(f.api.queries, hasLength(1));
    f.api.submitFailure = null;
    f.vault.failContaining = '"state":"COMMITTED"';
    await f.controller.retryPending();
    expect(f.controller.status, IdentityManagementStatus.storageFailure);
    expect(f.controller.directory, isNull);
    final restarted = await IdentityTestFixture.create(vault: f.vault, initialize: false, api: f.api);
    addTearDown(restarted.dispose);
    await restarted.controller.load();
    expect(restarted.controller.status, IdentityManagementStatus.ready);
    expect(restarted.store.current!.identityChanges, isEmpty);
  });

  test('Gate unavailable clears prior list and preserves unknown owner anchor', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.items = [identityTestItem()]; f.api.createdCount = 1;
    await f.controller.load();
    f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.unavailable,
      statusCode: 503, code: 'SERVICE_UNAVAILABLE');
    await f.controller.rename(identityTestId, '秋雨');
    expect(f.controller.directory, isNull);
    expect(f.sessions.isAuthenticated, isFalse);
    expect(f.store.current!.identityChanges[identityTestAccount]['nickname'], '秋雨');
  });

  test('authorityVersion invalidates a late list even after same-bearer restoration', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.readWait = Completer<IdentityDirectory>();
    final load = f.controller.load();
    await f.api.readStarted.future;
    f.sessions.sessionUnavailable(identityTestToken);
    await f.sessions.retry();
    f.api.readWait!.complete(IdentityDirectory(identities: [identityTestItem(name: '旧结果')],
      createdCount: 1, serverTime: DateTime.utc(2026, 10, 3), sessionExpiresAt: DateTime.utc(2035)));
    await load;
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.controller.directory, isNull);
    expect(f.store.current!.session!.expiresAt, identityTestExpiry);
  });

  test('concurrent create tap cannot allocate another intent while first request is outstanding', () async {
    final f = await IdentityTestFixture.create();
    addTearDown(f.dispose);
    f.api.submitWait = Completer<IdentityChangeOutcome>();
    final first = f.controller.create('春风');
    await f.api.submissionStarted.future;
    await f.controller.create('秋雨');
    expect(f.api.submissions, hasLength(1));
    f.api.submitWait!.complete(IdentityChangeOutcome(committed: true,
      operation: IdentityOperation.create, identityId: identityTestId,
      sessionExpiresAt: identityTestRenewed));
    await first;
    expect(f.api.submissions, hasLength(1));
  });

  test('codec rejects secret extension target shape and noncanonical key', () {
    final pending = {'v': 1, 'key': AuthCrypto.randomEncoded(16), 'username': 'private_user',
      'operation': 'CREATE', 'nickname': '春风', 'state': 'UNKNOWN'};
    for (final item in <Map<String, dynamic>>[
      {...pending, 'password': 'secret'}, {...pending, 'identityId': identityTestId},
      {...pending, 'key': AuthCrypto.randomEncoded(32)}, {...pending, 'state': 'NOT_FOUND'},
    ]) {
      expect(() => AuthState.parse(AuthState(identityChanges: {identityTestAccount: item})
        .toJson('test'), 'test'), throwsFormatException);
    }
    final old = const AuthState().toJson('test')..remove('identityChanges');
    expect(AuthState.parse(old, 'test').identityChanges, isEmpty);
    const draft = AuthState(identityDrafts: {identityTestAccount:
      {'v': 1, 'username': 'private_user', 'nickname': '春'}});
    expect(AuthState.parse(draft.toJson('test'), 'test').identityDrafts[identityTestAccount]['nickname'], '春');
    expect(() => AuthState.parse(const AuthState(identityDrafts: {identityTestAccount:
      {'v': 1, 'username': 'private_user', 'nickname': '春', 'password': 'secret'}})
      .toJson('test'), 'test'), throwsFormatException);
  });
}
