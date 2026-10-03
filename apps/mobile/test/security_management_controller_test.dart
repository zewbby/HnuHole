import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/src/auth/auth_api.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_session_controller.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/auth/credential_management_api.dart';
import 'package:hnuhole_mobile/src/auth/security_management_controller.dart';
import 'package:hnuhole_mobile/src/channels/channel.dart';
import 'package:hnuhole_mobile/src/channels/channel_repository.dart';
import 'package:hnuhole_mobile/src/navigation/channel_directory_controller.dart';

String _wire(int size, int value) => AuthCrypto.encode(List<int>.filled(size, value));
final _token = _wire(32, 1), _newToken = _wire(32, 2), _intent = _wire(32, 3);
final _credential = _wire(16, 4);
const _account = '00000000-0000-0000-0000-000000000001';
const _code = 'AAAQEAYEAUDAOCAJBIFQYDIOB4';
final _expiry = DateTime.utc(2031, 1, 1), _renewed = DateTime.utc(2031, 1, 31);

/// This fake owns the atomic value boundary only. It provides no evidence of
/// Android Keystore, iOS Keychain, device restart or platform Passkey behavior.
class _Vault implements AuthVault {
  String? value;
  bool failNext = false, commitUnknown = false;
  String? failContaining;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failNext || (failContaining != null && next.contains(failContaining!))) {
      failNext = false;
      failContaining = null;
      if (commitUnknown) value = next;
      throw const AuthStorageFailure();
    }
    value = next;
  }
}

/// Injects cancellation between a checked asynchronous metadata result and its
/// consumer's continuation. The underlying store still performs durable writes.
class _MetadataBarrierSessions extends AuthSessionController {
  _MetadataBarrierSessions({required super.api, required super.store, required super.directory});
  void Function()? afterMetadata;
  @override
  Future<bool> persistSessionMetadata(
    String token, DateTime expiresAt, bool Function() isCurrent,
  ) async {
    final saved = await super.persistSessionMetadata(token, expiresAt, isCurrent);
    final cancel = afterMetadata;
    if (saved && cancel != null) {
      afterMetadata = null;
      scheduleMicrotask(cancel);
    }
    return saved;
  }
}

/// Places cancellation after _savePending computes its checked return value,
/// before the final caller resumes. This crosses the real AuthStore queue and
/// retains the original verified operation anchor; it is not a native test.
class _PendingBoundaryStore extends AuthStore {
  _PendingBoundaryStore(AuthVault vault) : super(vault);
  void Function()? afterPendingSaved;
  @override
  Future<AuthState> update(AuthState Function(AuthState) change) async {
    final state = await super.update(change);
    final cancel = afterPendingSaved;
    if (state.pendingCredentialChange?['state'] == 'UNKNOWN' && cancel != null) {
      afterPendingSaved = null;
      scheduleMicrotask(() => scheduleMicrotask(cancel));
    }
    return state;
  }
}

class _SessionApi implements AuthApi {
  @override
  Future<CurrentSession> currentSession(String token) async => CurrentSession(
    accountId: _account, username: 'private_user', expiresAt: _expiry,
  );
  @override
  Future<AuthSession> login({required String username, required String password,
    required String installationId, required String idempotencyKey}) async =>
      AuthSession(accountId: _account, sessionToken: _newToken, expiresAt: _expiry);
  @override
  Future<void> revokeSession(String secret) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused operation');
}

class _Channels implements ChannelRepository {
  @override
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken}) async =>
      ChannelDirectoryResult(expiresAt: _expiry, channels: [
        for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
          Channel(
            id: '00000000-0000-0000-0000-00000000000${i + 1}',
            code: ChannelDirectory.requiredCodes[i], name: 'Channel $i',
            initiallyVisible: i < 5, displayOrder: i + 1,
          ),
      ]);
}

class _Passkey implements CancellablePasskeyClient {
  int creates = 0;
  int cancellations = 0;
  final started = Completer<void>();
  Completer<Map<String, dynamic>>? wait;
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> options) async {
    creates++;
    if (!started.isCompleted) started.complete();
    return wait != null ? await wait!.future : {'ownedFakeAttestation': true};
  }
  @override
  Future<Map<String, dynamic>> get(Map<String, dynamic> options) async =>
      throw StateError('Recovery is owned by AuthFlows');
  @override
  Future<void> cancel() async { cancellations++; }
}

class _ManagementApi implements CredentialManagementApi {
  int deviceReads = 0, credentialReads = 0, rotations = 0, binds = 0, removals = 0;
  int confirms = 0;
  final submissions = <Map<String, String>>[], queries = <Map<String, String>>[];
  final started = Completer<void>();
  final deviceStarted = Completer<void>();
  final queryStarted = Completer<void>();
  Completer<DateTime>? commitWait;
  Completer<DeviceDirectory>? deviceWait;
  Completer<CredentialChangeOutcome>? queryWait;
  AuthFailure? failure, queryFailure;
  CredentialChangeState result = CredentialChangeState.pending;
  void Function()? beforeSubmit;
  @override
  Future<DeviceDirectory> devices(String token) async {
    deviceReads++;
    if (!deviceStarted.isCompleted) deviceStarted.complete();
    if (failure != null) throw failure!;
    return deviceWait != null ? await deviceWait!.future : DeviceDirectory(
      currentSignedInAt: DateTime.utc(2026, 10, 2),
      lastReplacedSignedInAt: DateTime.utc(2026, 10, 1),
      lastReplacedAt: DateTime.utc(2026, 10, 2), sessionExpiresAt: _renewed,
    );
  }
  @override
  Future<RecoveryCredentialSummary> recoveryCredentials(String token) async {
    credentialReads++;
    return RecoveryCredentialSummary(sessionExpiresAt: _renewed, passkeys: [
      PasskeySummary(credentialId: _credential, createdAt: DateTime.utc(2026, 10, 1),
        backupEligible: true, backedUp: false),
    ]);
  }
  @override
  Future<RecoveryCodeRotation> createRecoveryCodeRotation({
    required String sessionToken, required String password,
  }) async {
    rotations++;
    if (failure != null) throw failure!;
    return RecoveryCodeRotation(rotationIntentId: _intent,
      expiresAt: DateTime.utc(2031, 1, 1, 0, 10), newRecoveryCode: _code,
      sessionExpiresAt: _renewed);
  }
  @override
  Future<DateTime> confirmRecoveryCodeRotation({required String sessionToken,
    required String rotationIntentId, required String newRecoveryCodeConfirmation,
    required String idempotencyKey}) async {
    confirms++;
    return _submit(sessionToken, rotationIntentId, idempotencyKey);
  }
  @override
  Future<PasskeyOptions> createPasskeyCreationOptions({required String sessionToken,
    required String password}) async => PasskeyOptions(challengeId: _intent,
      expiresAt: DateTime.utc(2031, 1, 1, 0, 5), publicKey: const {'ownedFake': true},
      sessionExpiresAt: _renewed);
  @override
  Future<DateTime> registerPasskey({required String sessionToken,
    required String challengeId, required Map<String, dynamic> attestation,
    required String idempotencyKey}) async {
    binds++;
    return _submit(sessionToken, challengeId, idempotencyKey);
  }
  @override
  Future<PasskeyRemovalIntent> createPasskeyRemovalIntent({required String sessionToken,
    required String credentialId, required String password}) async =>
      PasskeyRemovalIntent(removalIntentId: _intent,
        expiresAt: DateTime.utc(2031, 1, 1, 0, 5), sessionExpiresAt: _renewed);
  @override
  Future<DateTime> removePasskey({required String sessionToken,
    required String credentialId, required String removalIntentId,
    required String idempotencyKey}) async {
    removals++;
    return _submit(sessionToken, removalIntentId, idempotencyKey);
  }
  Future<DateTime> _submit(String token, String intent, String key) async {
    beforeSubmit?.call();
    submissions.add({'token': token, 'intent': intent, 'key': key});
    if (!started.isCompleted) started.complete();
    if (failure != null) throw failure!;
    return commitWait != null ? await commitWait!.future : _renewed;
  }
  @override
  Future<CredentialChangeOutcome> credentialChangeResult({required String sessionToken,
    required String changeId, required String idempotencyKey}) async {
    queries.add({'token': sessionToken, 'intent': changeId, 'key': idempotencyKey});
    if (!queryStarted.isCompleted) queryStarted.complete();
    if (queryFailure != null) throw queryFailure!;
    return queryWait != null ? await queryWait!.future : CredentialChangeOutcome(
      state: result, sessionExpiresAt: _renewed,
    );
  }
}

Future<({_PendingBoundaryStore store, _MetadataBarrierSessions sessions,
  SecurityManagementController management, ChannelDirectoryController directory,
  _ManagementApi api, _Passkey passkey})> _setup(_Vault vault,
  {_ManagementApi? api, _Passkey? passkey, bool initialize = true}) async {
  final store = _PendingBoundaryStore(vault);
  if (initialize) {
    await store.update((_) => AuthState(session: SessionRecord(
      token: _token, accountId: _account, expiresAt: _expiry,
    )));
  }
  final directory = ChannelDirectoryController(repository: _Channels());
  final sessions = _MetadataBarrierSessions(api: _SessionApi(), store: store, directory: directory);
  await sessions.start();
  final managementApi = api ?? _ManagementApi(), native = passkey ?? _Passkey();
  final management = SecurityManagementController(
    api: managementApi, store: store, passkey: native, sessions: sessions,
  );
  addTearDown(management.dispose);
  addTearDown(sessions.dispose);
  addTearDown(directory.dispose);
  addTearDown(store.dispose);
  return (store: store, sessions: sessions, management: management,
    directory: directory, api: managementApi, passkey: native);
}

Future<void> _prepareRotation(SecurityManagementController controller) async {
  await controller.beginRecoveryCodeRotation('fresh password');
  controller.hideRecoveryCode();
}

void main() {
  test('device and credential data publish only after metadata is durable', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    var published = false;
    f.management.addListener(() {
      if (f.management.status != SecurityManagementStatus.ready) return;
      published = true;
      final persisted = AuthState.parse(jsonDecode(vault.value!), f.store.scope);
      expect(persisted.session!.expiresAt, _renewed);
    });
    await f.management.load();
    expect(published, isTrue);
    expect(f.management.devices!.lastReplacedAt, DateTime.utc(2026, 10, 2));
    expect(f.management.credentials!.passkeys.single.credentialId, _credential);
    expect(f.api.deviceReads, 1);
    expect(f.api.credentialReads, 1);
  });

  test('rotation requires hidden code and full confirmation before any final send', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    await f.management.beginRecoveryCodeRotation('fresh password');
    expect(f.management.recoveryCode, _code);
    await f.management.confirmRecoveryCodeRotation(_code);
    expect(f.api.confirms, 0);
    f.management.hideRecoveryCode();
    expect(f.management.recoveryCode, isNull);
    await f.management.confirmRecoveryCodeRotation(_code.substring(0, 10));
    expect(f.api.confirms, 0);
    expect(f.management.status, SecurityManagementStatus.rotationCodeConfirmation);
    await f.management.confirmRecoveryCodeRotation(_code);
    expect(f.api.confirms, 1);
    expect(f.management.status, SecurityManagementStatus.committed);
    expect(vault.value, isNot(contains(_code)));
    expect(vault.value, isNot(contains('fresh password')));
    expect(f.store.current!.pendingCredentialChange!['state'], 'COMMITTED');
    await f.management.acknowledgeResult();
    expect(f.store.current!.pendingCredentialChange, isNull);
    expect(f.management.status, SecurityManagementStatus.ready);
  });

  test('result anchor is verified before sending and contains no plaintext credentials', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    await _prepareRotation(f.management);
    f.api.beforeSubmit = () {
      final durable = AuthState.parse(jsonDecode(vault.value!), f.store.scope);
      final pending = durable.pendingCredentialChange!;
      expect(pending['intentId'], _intent);
      expect(pending['kind'], 'ROTATION');
      expect(pending['originalTokenDigest'], sessionTokenDigest(_token));
      expect(pending['state'], 'UNKNOWN');
      expect(vault.value, isNot(contains(_code)));
    };
    await f.management.confirmRecoveryCodeRotation(_code);
    expect(f.api.submissions.single['key'], f.store.current!.pendingCredentialChange!['key']);
  });

  test('lost final reply survives process recreation and queries original key without resending', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    await _prepareRotation(f.management);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.management.confirmRecoveryCodeRotation(_code);
    final original = Map<String, dynamic>.from(f.store.current!.pendingCredentialChange!);
    expect(f.management.status, SecurityManagementStatus.pending);
    final api = _ManagementApi()..result = CredentialChangeState.committed;
    final restarted = await _setup(vault, api: api, initialize: false);
    await restarted.management.load();
    expect(api.queries.single, {'token': _token, 'intent': _intent, 'key': original['key']});
    expect(api.confirms, 0);
    expect(restarted.management.recoveryCode, isNull);
    expect(restarted.management.status, SecurityManagementStatus.committed);
  });

  test('unknown secure write sends nothing and restart can reconcile the durable anchor', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    await _prepareRotation(f.management);
    vault.failContaining = '"kind":"ROTATION"';
    vault.commitUnknown = true;
    await f.management.confirmRecoveryCodeRotation(_code);
    expect(f.api.confirms, 0);
    expect(f.management.status, SecurityManagementStatus.storageFailure);
    expect(f.store.current, isNull);
    final api = _ManagementApi()..result = CredentialChangeState.notCommitted;
    final restarted = await _setup(vault, api: api, initialize: false);
    await restarted.management.load();
    expect(api.queries, hasLength(1));
    expect(api.confirms, 0);
    expect(restarted.management.status, SecurityManagementStatus.notCommitted);
  });

  test('failed metadata write hides all management data and does not grant authority', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    vault.failNext = true;
    await f.management.load();
    expect(f.management.devices, isNull);
    expect(f.management.credentials, isNull);
    expect(f.management.status, SecurityManagementStatus.storageFailure);
    expect(f.sessions.isAuthenticated, isFalse);
  });

  test('metadata completion cancellation prevents a subsequent credential read', () async {
    final f = await _setup(_Vault());
    f.sessions.afterMetadata = f.management.cancelEphemeral;
    await f.management.load();
    expect(f.api.deviceReads, 1);
    expect(f.api.credentialReads, 0);
    expect(f.management.devices, isNull);
    expect(f.management.credentials, isNull);
  });

  test('metadata completion cancellation prevents a new code from being published', () async {
    final f = await _setup(_Vault());
    f.sessions.afterMetadata = f.management.cancelEphemeral;
    await f.management.beginRecoveryCodeRotation('fresh password');
    expect(f.management.recoveryCode, isNull);
    expect(f.management.status, SecurityManagementStatus.ready);
    expect(f.api.confirms, 0);
  });

  test('metadata completion cancellation prevents launching the native provider', () async {
    final f = await _setup(_Vault());
    f.sessions.afterMetadata = f.management.cancelEphemeral;
    await f.management.bindPasskey('fresh password');
    expect(f.passkey.creates, 0);
    expect(f.api.binds, 0);
    expect(f.store.current!.pendingCredentialChange, isNull);
  });

  for (final kind in ['ROTATION', 'PASSKEY_REMOVAL', 'PASSKEY_BINDING']) {
    test('$kind cancellation between saved anchor and final continuation sends nothing', () async {
      final f = await _setup(_Vault());
      if (kind == 'ROTATION') await _prepareRotation(f.management);
      if (kind == 'PASSKEY_REMOVAL') {
        await f.management.beginPasskeyRemoval(_credential, 'fresh password');
      }
      f.store.afterPendingSaved = f.management.cancelEphemeral;
      if (kind == 'ROTATION') {
        await f.management.confirmRecoveryCodeRotation(_code);
      } else if (kind == 'PASSKEY_REMOVAL') {
        await f.management.confirmPasskeyRemoval();
      } else {
        await f.management.bindPasskey('fresh password');
      }
      expect(f.api.confirms, 0);
      expect(f.api.removals, 0);
      expect(f.api.binds, 0);
      expect(f.store.current!.pendingCredentialChange!['kind'], kind);
      expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
      expect(f.management.recoveryCode, isNull);
      expect(f.sessions.isAuthenticated, isTrue);
    });
  }

  test('synchronous pending listener cancellation prevents the final POST', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    void cancelOnPending() {
      if (f.management.status == SecurityManagementStatus.pending && f.management.busy) {
        f.management.cancelEphemeral();
      }
    }
    f.management.addListener(cancelOnPending);
    await f.management.confirmRecoveryCodeRotation(_code);
    f.management.removeListener(cancelOnPending);
    expect(f.api.confirms, 0);
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
    expect(f.sessions.isAuthenticated, isTrue);
  });

  test('Gate failure after send preserves pending key and bearer but suspends protected data', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    await _prepareRotation(f.management);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.unavailable,
      statusCode: 503, code: 'SERVICE_UNAVAILABLE');
    await f.management.confirmRecoveryCodeRotation(_code);
    expect(f.management.status, SecurityManagementStatus.unavailable);
    expect(f.store.current!.session!.token, _token);
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
    expect(f.sessions.isAuthenticated, isFalse);
    expect(f.directory.channels, isEmpty);
    f.api.failure = null;
    f.api.result = CredentialChangeState.committed;
    await f.sessions.retry();
    await f.management.load();
    expect(f.api.confirms, 1);
    expect(f.api.queries.single['key'], f.api.submissions.single['key']);
    expect(f.management.status, SecurityManagementStatus.committed);
  });

  test('fresh password denial keeps bearer and offers another explicit password proof', () async {
    final f = await _setup(_Vault());
    await f.management.load();
    f.api.failure = const AuthFailure(kind: AuthFailureKind.unauthorized,
      statusCode: 401, code: 'AUTHENTICATION_FAILED');
    await f.management.beginRecoveryCodeRotation('wrong password');
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.store.current!.session!.token, _token);
    expect(f.management.recoveryCode, isNull);
    expect(f.management.errorMessage, contains('密码复验失败'));
  });

  test('session replaced clears authority without treating pending mutation as committed', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.unauthorized,
      statusCode: 401, code: 'session_replaced');
    await f.management.confirmRecoveryCodeRotation(_code);
    await f.store.read();
    expect(f.sessions.isAuthenticated, isFalse);
    expect(f.management.devices, isNull);
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
  });

  test('late device reply after new login cannot publish or extend the new session', () async {
    final f = await _setup(_Vault());
    f.api.deviceWait = Completer<DeviceDirectory>();
    final request = f.management.load();
    await f.api.deviceStarted.future;
    await f.sessions.login('private_user', 'password');
    f.api.deviceWait!.complete(DeviceDirectory(
      currentSignedInAt: DateTime.utc(2026, 10, 2),
      sessionExpiresAt: DateTime.utc(2035),
    ));
    await request;
    expect(f.store.current!.session!.token, _newToken);
    expect(f.store.current!.session!.expiresAt, _expiry);
    expect(f.management.devices, isNull);
    expect(f.api.credentialReads, 0);
  });

  test('late successful commit after new login leaves old unknown anchor unchanged', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    f.api.commitWait = Completer<DateTime>();
    final request = f.management.confirmRecoveryCodeRotation(_code);
    await f.api.started.future;
    await f.sessions.login('private_user', 'password');
    f.api.commitWait!.complete(DateTime.utc(2035));
    await request;
    expect(f.store.current!.session!.expiresAt, _expiry);
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
    await f.management.load();
    expect(f.management.status, SecurityManagementStatus.previousSessionPending);
    expect(f.api.queries, isEmpty);
  });

  test('native callback after logout cannot send attestation or revive bearer', () async {
    final native = _Passkey()..wait = Completer<Map<String, dynamic>>();
    final f = await _setup(_Vault(), passkey: native);
    final request = f.management.bindPasskey('fresh password');
    await native.started.future;
    await f.sessions.logout();
    native.wait!.complete({'ownedFakeAttestation': true});
    await request;
    expect(f.api.binds, 0);
    expect(f.store.current!.session, isNull);
    expect(f.store.current!.pendingCredentialChange, isNull);
  });

  test('native callback after new login cannot bind against either session', () async {
    final native = _Passkey()..wait = Completer<Map<String, dynamic>>();
    final f = await _setup(_Vault(), passkey: native);
    final request = f.management.bindPasskey('fresh password');
    await native.started.future;
    await f.sessions.login('private_user', 'password');
    native.wait!.complete({'ownedFakeAttestation': true});
    await request;
    expect(f.api.binds, 0);
    expect(f.store.current!.session!.token, _newToken);
    expect(f.store.current!.pendingCredentialChange, isNull);
  });

  test('closing management route cancels its native sheet and fences late completion', () async {
    final native = _Passkey()..wait = Completer<Map<String, dynamic>>();
    final f = await _setup(_Vault(), passkey: native);
    final request = f.management.bindPasskey('fresh password');
    await native.started.future;
    f.management.cancelEphemeral();
    expect(native.cancellations, 1);
    native.wait!.complete({'ownedFakeAttestation': true});
    await request;
    expect(f.api.binds, 0);
    expect(f.store.current!.pendingCredentialChange, isNull);
    expect(f.sessions.isAuthenticated, isTrue);
  });

  test('closing route after final send retains original anchor for foreground reconciliation', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    f.api.commitWait = Completer<DateTime>();
    final request = f.management.confirmRecoveryCodeRotation(_code);
    await f.api.started.future;
    final originalKey = f.store.current!.pendingCredentialChange!['key'];
    f.management.cancelEphemeral();
    f.api.commitWait!.complete(_renewed);
    await request;
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
    expect(f.store.current!.pendingCredentialChange!['key'], originalKey);
    f.api.result = CredentialChangeState.committed;
    await f.management.load();
    expect(f.api.queries.single['key'], originalKey);
    expect(f.api.confirms, 1);
    expect(f.management.status, SecurityManagementStatus.committed);
  });

  test('removal requires password intent then explicit confirmation and retains recovery code', () async {
    final f = await _setup(_Vault());
    await f.management.load();
    await f.management.confirmPasskeyRemoval();
    expect(f.api.removals, 0);
    await f.management.beginPasskeyRemoval(_credential, 'fresh password');
    expect(f.management.status, SecurityManagementStatus.removalConfirmation);
    expect(f.api.removals, 0);
    await f.management.confirmPasskeyRemoval();
    expect(f.api.removals, 1);
    expect(f.store.current!.pendingCredentialChange!['credentialId'], _credential);
    expect(f.management.status, SecurityManagementStatus.committed);
    expect(f.store.current!.session!.token, _token);
  });

  test('binding process recreation queries original challenge and never reruns native ceremony', () async {
    final vault = _Vault();
    final f = await _setup(vault);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.unknownOutcome);
    await f.management.bindPasskey('fresh password');
    final original = f.api.submissions.single;
    expect(vault.value, isNot(contains('ownedFakeAttestation')));
    final restarted = await _setup(vault, initialize: false);
    await restarted.management.load();
    expect(restarted.api.queries.single, original);
    expect(restarted.api.binds, 0);
    expect(restarted.passkey.creates, 0);
    expect(restarted.management.status, SecurityManagementStatus.pending);
    await restarted.management.acknowledgeResult();
    expect(restarted.store.current!.pendingCredentialChange, isNotNull);
  });

  test('pending and malformed or conflicting result queries retain unknown original operation', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.management.confirmRecoveryCodeRotation(_code);
    final key = f.store.current!.pendingCredentialChange!['key'];
    f.api.failure = null;
    f.api.result = CredentialChangeState.pending;
    await f.management.reconcilePending();
    expect(f.management.status, SecurityManagementStatus.pending);
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
    for (final failure in const [
      AuthFailure(kind: AuthFailureKind.invalidResponse, statusCode: 202),
      AuthFailure(kind: AuthFailureKind.rejected,
        statusCode: 409, code: 'IDEMPOTENCY_CONFLICT'),
      AuthFailure(kind: AuthFailureKind.rejected,
        statusCode: 409, code: 'INTENT_INVALID'),
    ]) {
      f.api.queryFailure = failure;
      await f.management.reconcilePending();
      expect(f.management.status, SecurityManagementStatus.pending);
      expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
      expect(f.store.current!.pendingCredentialChange!['key'], key);
      await f.management.acknowledgeResult();
      expect(f.store.current!.pendingCredentialChange!['key'], key);
    }
    expect(f.api.confirms, 1);
    expect(f.management.recoveryCode, isNull);
  });

  test('late result query after password reset cannot persist success or data', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.management.confirmRecoveryCodeRotation(_code);
    f.api.failure = null;
    f.api.queryWait = Completer<CredentialChangeOutcome>();
    final query = f.management.reconcilePending();
    await f.api.queryStarted.future;
    await f.store.update((s) => s.copyWith(pendingReset: {
      'v': 1, 'intentId': _wire(32, 11), 'key': _wire(32, 12),
      'state': 'UNKNOWN', 'originalTokenDigest': sessionTokenDigest(_token),
    }));
    f.api.queryWait!.complete(CredentialChangeOutcome(
      state: CredentialChangeState.committed, sessionExpiresAt: DateTime.utc(2035),
    ));
    await query;
    expect(f.store.current!.pendingCredentialChange!['state'], 'UNKNOWN');
    expect(f.store.current!.session!.expiresAt, _renewed);
    expect(f.management.credentials, isNull);
  });

  test('result tombstone is unknown and only explicit abandon clears its local anchor', () async {
    final f = await _setup(_Vault());
    await _prepareRotation(f.management);
    f.api.failure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.management.confirmRecoveryCodeRotation(_code);
    f.api.queryFailure = const AuthFailure(kind: AuthFailureKind.rejected,
      statusCode: 410, code: 'RESULT_EXPIRED');
    await f.management.reconcilePending();
    expect(f.management.status, SecurityManagementStatus.resultExpired);
    expect(f.store.current!.pendingCredentialChange!['state'], 'EXPIRED');
    await f.management.acknowledgeResult();
    expect(f.store.current!.pendingCredentialChange, isNotNull);
    f.api.failure = null;
    await f.management.abandonPending();
    expect(f.store.current!.pendingCredentialChange, isNull);
    expect(f.management.status, SecurityManagementStatus.ready);
    expect(f.api.confirms, 1);
  });

  test('codec rejects secrets and unknown operation shapes in persisted credential change', () async {
    final pending = <String, dynamic>{'v': 1, 'kind': 'ROTATION', 'intentId': _intent,
      'key': _wire(32, 10), 'state': 'UNKNOWN', 'accountId': _account,
      'originalTokenDigest': sessionTokenDigest(_token)};
    for (final secret in ['password', 'newRecoveryCode', 'attestation', 'originalBearer']) {
      expect(() => AuthState.parse(AuthState(pendingCredentialChange: {
        ...pending, secret: 'must not be stored',
      }).toJson('test'), 'test'), throwsFormatException);
    }
    final old = const AuthState().toJson('test')..remove('pendingCredentialChange');
    expect(AuthState.parse(old, 'test').pendingCredentialChange, isNull);
  });
}
