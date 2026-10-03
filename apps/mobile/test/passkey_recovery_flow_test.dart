import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

String _bytes(int value) => AuthCrypto.encode(List<int>.filled(32, value));
final _expiry = DateTime.utc(2026, 11, 1);
const _code = 'AAAAAAAAAAAAAAAAAAAAAAAAAA';

class _Vault implements AuthVault {
  String? value;
  Completer<String?>? readBarrier;
  Completer<void>? readStarted;
  @override
  Future<String?> read() async {
    final wait = readBarrier;
    if (wait == null) return value;
    readBarrier = null;
    readStarted?.complete();
    return wait.future;
  }
  @override
  Future<void> write(String next) async => value = next;
}

class _Api implements AuthApi, PasskeyRecoveryApi {
  int proofs = 0, commits = 0;
  bool freeze = false, loseCommit = false;
  PasswordResetResult result = PasswordResetResult.pending;
  Completer<AuthSession>? loginBarrier;
  Completer<PasskeyOptions>? optionsBarrier;
  Completer<PasswordResetIntent>? proofBarrier;
  final loginStarted = Completer<void>(), optionsStarted = Completer<void>(), proofStarted = Completer<void>();
  @override
  Future<AuthSession> login({required String username, required String password,
      required String installationId, required String idempotencyKey}) async {
    loginStarted.complete();
    return loginBarrier!.future;
  }
  @override
  Future<CurrentSession> currentSession(String token) async => CurrentSession(
    accountId: '00000000-0000-4000-8000-000000000001', username: 'private_name', expiresAt: _expiry);
  @override
  Future<PasskeyOptions> createPasskeyResetOptions() async {
    if (freeze) throw const AuthFailure(kind: AuthFailureKind.unavailable, statusCode: 503);
    optionsStarted.complete();
    if (optionsBarrier != null) return optionsBarrier!.future;
    return PasskeyOptions(challengeId: _bytes(1), expiresAt: _expiry,
      publicKey: {'challenge': _bytes(2), 'rpId': 'rp.example.test',
        'timeout': 60000, 'userVerification': 'required'});
  }
  @override
  Future<PasswordResetIntent> createPasskeyResetIntent({required String challengeId,
      required Map<String, dynamic> assertion}) async {
    proofs++;
    proofStarted.complete();
    if (proofBarrier != null) return proofBarrier!.future;
    return PasswordResetIntent(resetIntentId: _bytes(3), expiresAt: _expiry,
      username: 'private_name', newRecoveryCode: _code);
  }
  @override
  Future<void> commitPasswordReset({required String resetIntentId,
    required String newPassword, required String newRecoveryCodeConfirmation,
    required String idempotencyKey}) async {
    commits++;
    if (loseCommit) throw const AuthFailure(kind: AuthFailureKind.timeout);
  }
  @override
  Future<PasswordResetResult> passwordResetResult({required String resetIntentId,
      required String idempotencyKey}) async => result;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Passkey implements CancellablePasskeyClient {
  int gets = 0, cancels = 0;
  final started = Completer<void>();
  Completer<Map<String, dynamic>>? barrier;
  @override
  Future<Map<String, dynamic>> get(Map<String, dynamic> options) async {
    gets++;
    if (!started.isCompleted) started.complete();
    expect(options.containsKey('allowCredentials'), isFalse);
    expect(options.containsKey('username'), isFalse);
    return barrier == null ? {'type': 'public-key'} : barrier!.future;
  }
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> options) async => throw UnimplementedError();
  @override
  Future<void> cancel() async { cancels++; }
}

class _Channels implements ChannelRepository {
  @override
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken}) async =>
      ChannelDirectoryResult(expiresAt: _expiry, channels: [
        for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
          Channel(id: 'channel-$i', code: ChannelDirectory.requiredCodes[i],
            name: ChannelDirectory.requiredCodes[i], initiallyVisible: i < 5, displayOrder: i),
      ]);
}

void main() {
  late _Vault vault;
  late AuthStore store;
  late _Api api;
  late _Passkey passkey;
  late AuthFlows flows;
  AuthSessionController? sessions;
  ChannelDirectoryController? directory;
  int adopted = 0;
  AuthFlows makeFlows() => AuthFlows(api: api, store: store,
    passkeyApi: api, passkey: passkey, clearCommunityAccess: () {},
    sessionAuthorityVersion: () => sessions?.authorityVersion ?? 0, sessionAuthority: sessions,
    acceptRegistrationSession: (_) async { adopted++; });
  setUp(() async {
    adopted = 0;
    sessions = null; directory = null;
    vault = _Vault(); store = AuthStore(vault); api = _Api(); passkey = _Passkey();
    await store.read(); flows = makeFlows();
  });
  tearDown(() { flows.dispose(); sessions?.dispose(); directory?.dispose(); store.dispose(); });

  test('discoverable proof enters hidden/full-code reset without automatic login', () async {
    await flows.beginPasskeyReset();
    expect(flows.status, AuthFlowStatus.resetCodeShown);
    expect(flows.resetUsername, 'private_name');
    expect(flows.recoveryCode, _code);
    expect(adopted, 0);
    flows.hideRecoveryCode();
    expect(flows.recoveryCode, isNull);
    await flows.commitReset('fresh long password for recovery', _code);
    expect(flows.status, AuthFlowStatus.resetCommitted);
    expect(api.commits, 1);
    expect(store.current?.session, isNull);
    expect(vault.value, isNot(contains(_code)));
    expect(vault.value, isNot(contains('fresh long password')));
    expect(vault.value, isNot(contains('public-key')));
    expect(adopted, 0);
  });

  test('closing a native ceremony suppresses its late assertion', () async {
    passkey.barrier = Completer<Map<String, dynamic>>();
    final work = flows.beginPasskeyReset();
    await passkey.started.future.timeout(const Duration(seconds: 2));
    flows.cancelPasskeyRecovery();
    passkey.barrier!.complete({'type': 'public-key'});
    await work;
    expect(api.proofs, 0); expect(passkey.cancels, 1);
    expect(flows.recoveryCode, isNull); expect(flows.busy, isFalse);
  });

  test('closing recovery while the first secure read is blocked prevents all later work', () async {
    final release = Completer<String?>();
    vault.readBarrier = release;
    vault.readStarted = Completer<void>();
    final work = flows.beginPasskeyReset();
    await vault.readStarted!.future.timeout(const Duration(seconds: 2));
    flows.cancelPasskeyRecovery();
    expect(flows.busy, isFalse);
    expect(passkey.cancels, 0); // The workflow owns no native sheet yet.
    release.complete(vault.value);
    await work;
    expect(api.optionsStarted.isCompleted, isFalse);
    expect(passkey.gets, 0);
    expect(api.proofs, 0);
    expect(flows.recoveryCode, isNull);
    expect(store.current!.pendingReset, isNull);
  });

  test('closing recovery during the initial busy notification prevents its first request', () async {
    void closeOnBusy() {
      if (flows.busy) flows.cancelPasskeyRecovery();
    }
    flows.addListener(closeOnBusy);
    await flows.beginPasskeyReset();
    flows.removeListener(closeOnBusy);
    expect(flows.busy, isFalse);
    expect(api.optionsStarted.isCompleted, isFalse);
    expect(passkey.gets, 0);
    expect(passkey.cancels, 0);
    expect(api.proofs, 0);
    expect(flows.recoveryCode, isNull);
  });

  test('first secure read failure releases workflow ownership without cancelling a foreign sheet', () async {
    final release = Completer<String?>();
    vault.readBarrier = release;
    vault.readStarted = Completer<void>();
    final work = flows.beginPasskeyReset();
    await vault.readStarted!.future.timeout(const Duration(seconds: 2));
    release.completeError(const AuthStorageFailure());
    await work;
    expect(flows.busy, isFalse);
    expect(api.optionsStarted.isCompleted, isFalse);
    expect(passkey.gets, 0);
    var notifications = 0;
    flows.addListener(() { notifications++; });
    flows.cancelPasskeyRecovery();
    expect(notifications, 0); // finally already cleared recovery ownership.
    expect(passkey.cancels, 0);
    expect(flows.recoveryCode, isNull);
  });

  test('late native assertion cannot publish after a different session appears', () async {
    passkey.barrier = Completer<Map<String, dynamic>>();
    final work = flows.beginPasskeyReset();
    await passkey.started.future.timeout(const Duration(seconds: 2));
    await store.update((s) => s.copyWith(session: SessionRecord(token: _bytes(4),
      accountId: '00000000-0000-4000-8000-000000000001', expiresAt: _expiry)));
    passkey.barrier!.complete({'type': 'public-key'});
    await work;
    expect(api.proofs, 0); expect(flows.recoveryCode, isNull);
    expect(store.current!.session!.token, _bytes(4));
  });

  test('Gate failure does not invoke a native credential provider', () async {
    api.freeze = true;
    await flows.beginPasskeyReset();
    expect(passkey.gets, 0); expect(api.proofs, 0);
    expect(flows.recoveryCode, isNull); expect(flows.error, isNotNull);
  });

  test('lost Passkey reset commit survives controller restart and queries original result', () async {
    await flows.beginPasskeyReset(); flows.hideRecoveryCode(); api.loseCommit = true;
    await flows.commitReset('fresh long password for recovery', _code);
    expect(flows.status, AuthFlowStatus.resetUnknown);
    final key = store.current!.pendingReset!['key'];
    flows.dispose(); flows = makeFlows();
    await flows.restorePending(); api.result = PasswordResetResult.committed;
    await flows.reconcileReset();
    expect(flows.status, AuthFlowStatus.resetCommitted);
    expect(store.current!.pendingReset!['key'], key);
    expect(api.proofs, 1); expect(api.commits, 1); expect(adopted, 0);
  });

  test('starting a new login invalidates a native response before the new token exists', () async {
    directory = ChannelDirectoryController(repository: _Channels());
    sessions = AuthSessionController(api: api, store: store, directory: directory!);
    await sessions!.start(); flows.dispose(); flows = makeFlows();
    passkey.barrier = Completer<Map<String, dynamic>>();
    final recovery = flows.beginPasskeyReset();
    await passkey.started.future.timeout(const Duration(seconds: 2));
    api.loginBarrier = Completer<AuthSession>();
    final login = sessions!.login('private_name', 'correct long password');
    await api.loginStarted.future.timeout(const Duration(seconds: 2));
    expect(store.current!.session, isNull);
    passkey.barrier!.complete({'type': 'public-key'}); await recovery;
    expect(api.proofs, 0); expect(flows.recoveryCode, isNull);
    api.loginBarrier!.complete(AuthSession(accountId: '00000000-0000-4000-8000-000000000001',
      sessionToken: _bytes(8), expiresAt: _expiry));
    await login;
    expect(sessions!.isAuthenticated, isTrue);
  });

  test('cancelling while options wait does not cancel a different owners native sheet', () async {
    api.optionsBarrier = Completer<PasskeyOptions>();
    final recovery = flows.beginPasskeyReset();
    await api.optionsStarted.future.timeout(const Duration(seconds: 2));
    flows.cancelPasskeyRecovery();
    api.optionsBarrier!.complete(PasskeyOptions(challengeId: _bytes(1), expiresAt: _expiry,
      publicKey: {'challenge': _bytes(2), 'rpId': 'rp.example.test'}));
    await recovery;
    expect(passkey.gets, 0); expect(passkey.cancels, 0); expect(api.proofs, 0);
  });

  test('late proof HTTP response cannot reveal code after the recovery route closes', () async {
    api.proofBarrier = Completer<PasswordResetIntent>();
    final recovery = flows.beginPasskeyReset();
    await api.proofStarted.future.timeout(const Duration(seconds: 2));
    flows.cancelPasskeyRecovery();
    api.proofBarrier!.complete(PasswordResetIntent(resetIntentId: _bytes(3), expiresAt: _expiry,
      username: 'private_name', newRecoveryCode: _code));
    await recovery;
    expect(flows.recoveryCode, isNull); expect(flows.resetUsername, isNull);
    expect(passkey.cancels, 0); expect(store.current!.pendingReset, isNull);
  });
}
