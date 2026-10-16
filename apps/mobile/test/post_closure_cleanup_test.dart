import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_api.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_flows.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_state_codec.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';

const _originalAccount = '11111111-1111-1111-1111-111111111111';
const _laterAccount = '22222222-2222-2222-2222-222222222222';
final _now = DateTime.utc(2026, 10, 8, 9);
String _bytes(int size, [int value = 1]) =>
    AuthCrypto.encode(List.filled(size, value));

class _Vault implements AuthVault {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrite) throw const AuthStorageFailure();
    value = next;
  }
}

class _ClosureApi implements AuthApi {
  final requests = <Map<String, String>>[];
  final queries = <Map<String, String>>[];
  AuthFailure? requestFailure;
  ClosureStatus result = ClosureStatus(
    state: ClosureState.pending,
    dueAt: _now.add(const Duration(days: 7)),
  );
  @override
  Future<ClosureAccepted> requestClosure({
    required String sessionToken,
    required String password,
    required String closureId,
    required String statusDigest,
  }) async {
    requests.add({
      'sessionToken': sessionToken,
      'password': password,
      'closureId': closureId,
      'statusDigest': statusDigest,
    });
    if (requestFailure != null) throw requestFailure!;
    return ClosureAccepted(
      closureId: closureId,
      dueAt: _now.add(const Duration(days: 7)),
    );
  }

  @override
  Future<ClosureStatus> closureStatus({
    required String closureId,
    required String statusSecret,
  }) async {
    queries.add({'closureId': closureId, 'statusSecret': statusSecret});
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final vault = _Vault();
  final api = _ClosureApi();
  final cleaned = <String>[];
  bool failCleanup = false;
  Completer<void>? cleanupGate;
  late final store = AuthStore(vault);
  AuthFlows makeFlows({AuthStore? storage}) => AuthFlows(
    api: api,
    store: storage ?? store,
    clock: () => _now,
    acceptRegistrationSession: (_) async {},
    clearCommunityAccess: () {},
    onAccountClosed: (accountId) async {
      cleaned.add(accountId);
      await cleanupGate?.future;
      if (failCleanup) throw StateError('controlled cleanup failure');
    },
  );
  Future<void> login([String account = _originalAccount]) => store.update(
    (state) => state.copyWith(
      session: SessionRecord(
        token: _bytes(32, account == _originalAccount ? 10 : 11),
        accountId: account,
        expiresAt: _now.add(const Duration(days: 30)),
      ),
    ),
  );
  Future<void> seed(String state, {bool legacy = false, String? owner}) =>
      store.update(
        (latest) => latest.copyWith(
          pendingClosure: _pending(state, legacy: legacy, owner: owner),
        ),
      );
}

Map<String, dynamic> _pending(
  String state, {
  bool legacy = false,
  String? owner,
}) {
  final secret = _bytes(32, 3);
  return {
    'v': 1,
    'closureId': _bytes(32, 2),
    'statusSecret': secret,
    'statusDigest': AuthCrypto.closureStatusDigest(secret),
    'state': state,
    if (!legacy) 'originalAccountId': owner ?? _originalAccount,
    if (state == 'UNKNOWN') 'originalBearer': _bytes(32, 10),
    if (state == 'PENDING' || state == 'FINALIZING')
      'dueAt': _now.add(const Duration(days: 7)).toIso8601String(),
    if (state == 'RELEASED') 'releaseReceipt': _bytes(120, 4),
  };
}

void main() {
  test('注销原账号仅进入私有vault记录，不添加公共API字段；申请和未知不清业务', () async {
    final h = _Harness();
    final flows = h.makeFlows();
    await h.login();
    h.api.requestFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await flows.requestClosure('private password');
    final unknown = (await h.store.read()).pendingClosure!;
    expect(unknown['state'], 'UNKNOWN');
    expect(unknown['originalAccountId'], _originalAccount);
    expect(h.cleaned, isEmpty);
    expect(h.vault.value, contains(_originalAccount));
    expect(h.api.requests.single.keys.toSet(), {
      'sessionToken',
      'password',
      'closureId',
      'statusDigest',
    });
    h.api.requestFailure = null;
    await flows.retryClosure('private password');
    final pending = (await h.store.read()).pendingClosure!;
    expect(pending['state'], 'PENDING');
    expect(pending['originalAccountId'], _originalAccount);
    expect(pending.containsKey('originalBearer'), isFalse);
    expect(h.cleaned, isEmpty);
    flows.dispose();
  });

  test('originalAccountId codec严格校验，历史缺owner兼容但未知字段拒绝', () {
    final good = _pending('PENDING');
    AuthWorkflowCodec.validate(pendingClosure: good);
    final state = AuthState(pendingClosure: good);
    expect(
      AuthState.parse(
        state.toJson('test-scope'),
        'test-scope',
      ).pendingClosure!['originalAccountId'],
      _originalAccount,
    );
    for (final owner in [
      '',
      'current-account',
      '11111111-1111-1111-1111-11111111111X',
      17,
      null,
    ]) {
      expect(
        () => AuthWorkflowCodec.validate(
          pendingClosure: {...good, 'originalAccountId': owner},
        ),
        throwsFormatException,
      );
    }
    expect(
      () => AuthWorkflowCodec.validate(
        pendingClosure: {...good, 'publicAccountId': _originalAccount},
      ),
      throwsFormatException,
    );
    AuthWorkflowCodec.validate(
      pendingClosure: _pending('RELEASED', legacy: true),
    );
  });

  test('PENDING FINALIZING CANCELLED恢复及核对均不清业务，取消可忘记', () async {
    for (final state in ['UNKNOWN', 'PENDING', 'FINALIZING', 'CANCELLED']) {
      final h = _Harness();
      await h.seed(state);
      final flows = h.makeFlows();
      await flows.restorePending();
      expect(h.cleaned, isEmpty, reason: state);
      h.api.result = state == 'CANCELLED'
          ? const ClosureStatus(state: ClosureState.cancelled)
          : state == 'FINALIZING'
          ? ClosureStatus(
              state: ClosureState.finalizing,
              dueAt: _now.add(const Duration(days: 7)),
            )
          : ClosureStatus(
              state: ClosureState.pending,
              dueAt: _now.add(const Duration(days: 7)),
            );
      await flows.reconcileClosure();
      expect(h.cleaned, isEmpty, reason: 'reconcile $state');
      if (state == 'CANCELLED') {
        await flows.forgetClosureStatus();
        expect((await h.store.read()).pendingClosure, isNull);
      }
      flows.dispose();
    }
  });

  test('CLOSED_RELEASE_PENDING权威核对后清原账号，保留后来账号会话', () async {
    final h = _Harness();
    await h.seed('PENDING');
    await h.login(_laterAccount);
    final flows = h.makeFlows();
    h.api.result = const ClosureStatus(
      state: ClosureState.closedReleasePending,
    );
    await flows.reconcileClosure();
    final state = await h.store.read();
    expect(state.pendingClosure!['state'], 'CLOSED_RELEASE_PENDING');
    expect(state.pendingClosure!['originalAccountId'], _originalAccount);
    expect(state.session!.accountId, _laterAccount);
    expect(h.cleaned, [_originalAccount]);
    expect(h.api.queries.single.keys.toSet(), {'closureId', 'statusSecret'});
    await flows.forgetClosureStatus();
    expect((await h.store.read()).pendingClosure, isNotNull);
    flows.dispose();
  });

  test('RELEASED权威核对触发原账号清理，释放回执不丢且当前账号不变', () async {
    final h = _Harness();
    await h.seed('PENDING');
    await h.login(_laterAccount);
    h.api.result = ClosureStatus(
      state: ClosureState.released,
      releaseReceipt: _bytes(120, 4),
    );
    final flows = h.makeFlows();
    await flows.reconcileClosure();
    final state = await h.store.read();
    expect(state.pendingClosure!['state'], 'RELEASED');
    expect(state.pendingClosure!['releaseReceipt'], _bytes(120, 4));
    expect(state.session!.accountId, _laterAccount);
    expect(h.cleaned, [_originalAccount]);
    flows.dispose();
  });

  test('清理失败保留CLOSED标识，重启restorePending重试原账号', () async {
    final h = _Harness();
    await h.seed('PENDING');
    await h.login(_laterAccount);
    h.failCleanup = true;
    h.api.result = const ClosureStatus(
      state: ClosureState.closedReleasePending,
    );
    final first = h.makeFlows();
    await first.reconcileClosure();
    expect(first.errorMessage, isNotNull);
    expect(
      (await h.store.read()).pendingClosure!['state'],
      'CLOSED_RELEASE_PENDING',
    );
    first.dispose();
    h.failCleanup = false;
    final restartedStore = AuthStore(h.vault);
    final restarted = h.makeFlows(storage: restartedStore);
    await restarted.restorePending();
    expect(restarted.errorMessage, isNull);
    expect(h.cleaned, [_originalAccount, _originalAccount]);
    expect((await restartedStore.read()).session!.accountId, _laterAccount);
    expect(
      (await restartedStore.read()).pendingClosure!['state'],
      'CLOSED_RELEASE_PENDING',
    );
    restarted.dispose();
  });

  test('forget清理故障不得删除RELEASED标识，重试成功才去标识', () async {
    final h = _Harness();
    await h.seed('RELEASED');
    await h.login(_laterAccount);
    h.failCleanup = true;
    final flows = h.makeFlows();
    await flows.forgetClosureStatus();
    expect(flows.errorMessage, isNotNull);
    expect((await h.store.read()).pendingClosure!['state'], 'RELEASED');
    h.failCleanup = false;
    await flows.forgetClosureStatus();
    expect((await h.store.read()).pendingClosure, isNull);
    expect(h.cleaned, [_originalAccount, _originalAccount]);
    expect((await h.store.read()).session!.accountId, _laterAccount);
    flows.dispose();
  });

  test('重启后直接forget也必须先读持久标识并成功清理', () async {
    final h = _Harness();
    await h.seed('RELEASED');
    await h.login(_laterAccount);
    final freshStore = AuthStore(h.vault);
    expect(freshStore.current, isNull);
    h.failCleanup = true;
    final flows = h.makeFlows(storage: freshStore);
    await flows.forgetClosureStatus();
    expect(h.cleaned, [_originalAccount]);
    expect((await freshStore.read()).pendingClosure!['state'], 'RELEASED');
    h.failCleanup = false;
    await flows.forgetClosureStatus();
    expect((await freshStore.read()).pendingClosure, isNull);
    expect((await freshStore.read()).session!.accountId, _laterAccount);
    flows.dispose();
  });

  test('清理完成前不得忘记标识；vault写失败仍保留可重试标识', () async {
    final h = _Harness();
    await h.seed('RELEASED');
    final flows = h.makeFlows();
    h.cleanupGate = Completer<void>();
    final forget = flows.forgetClosureStatus();
    for (var i = 0; i < 50 && h.cleaned.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(h.cleaned, [_originalAccount]);
    expect((await h.store.read()).pendingClosure, isNotNull);
    h.vault.failWrite = true;
    h.cleanupGate!.complete();
    await forget;
    h.vault.failWrite = false;
    expect((await h.store.read()).pendingClosure!['state'], 'RELEASED');
    await flows.forgetClosureStatus();
    expect((await h.store.read()).pendingClosure, isNull);
    flows.dispose();
  });

  test('legacy闭号缺owner不猜后来账号，恢复及forget不调用清理', () async {
    final h = _Harness();
    await h.seed('RELEASED', legacy: true);
    await h.login(_laterAccount);
    final flows = h.makeFlows();
    await flows.restorePending();
    await flows.forgetClosureStatus();
    expect(h.cleaned, isEmpty);
    expect((await h.store.read()).session!.accountId, _laterAccount);
    expect((await h.store.read()).pendingClosure, isNull);
    flows.dispose();
  });

  test('迟到forget不能删除等待期间换入的另一闭号标识', () async {
    final h = _Harness();
    await h.seed('RELEASED');
    final flows = h.makeFlows();
    h.cleanupGate = Completer<void>();
    final forget = flows.forgetClosureStatus();
    for (var i = 0; i < 50 && h.cleaned.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final replacement = {
      ..._pending('RELEASED', owner: _laterAccount),
      'closureId': _bytes(32, 17),
    };
    await h.store.update(
      (state) => state.copyWith(pendingClosure: replacement),
    );
    h.cleanupGate!.complete();
    await forget;
    expect((await h.store.read()).pendingClosure!['closureId'], _bytes(32, 17));
    expect(
      (await h.store.read()).pendingClosure!['originalAccountId'],
      _laterAccount,
    );
    expect(h.cleaned, [_originalAccount]);
    expect(flows.errorMessage, isNotNull);
    flows.dispose();
  });
}
