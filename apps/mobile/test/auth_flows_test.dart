import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_api.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_flows.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';

String bytes(int n, [int value = 1]) =>
    AuthCrypto.encode(List<int>.filled(n, value));
final now = DateTime.utc(2026, 9, 30, 9);
final session = SessionRecord(
  token: bytes(32, 10),
  accountId: '00000000-0000-0000-0000-000000000001',
  expiresAt: now.add(const Duration(days: 30)),
);

class Vault implements AuthVault {
  String? value;
  bool failWrite = false;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    writes++;
    if (failWrite) throw const AuthStorageFailure();
    value = next;
  }
}

class Api implements AuthApi {
  PasswordResetResult resetResult = PasswordResetResult.pending;
  AuthFailure? resetResultFailure;
  Future<void> Function()? onCommitReset;
  Future<ClosureAccepted> Function(String id)? onClosure;
  Future<ClosureStatus> Function()? onClosureStatus;
  Future<OtpRequestAccepted> Function()? onOtp;
  AuthFailure? otpResultFailure;
  Future<AuthSession> Function()? onRegistration;
  final resetCommits = <Map<String, String>>[];
  final closureRequests = <Map<String, String>>[];
  final closureQueries = <Map<String, String>>[];
  final otpRequests = <Map<String, String>>[];
  final confirmations = <Map<String, String>>[];
  final registrationCreates = <Map<String, String>>[];
  final registrations = <Map<String, String>>[];
  String? ticket;
  int proofCalls = 0;
  @override
  Future<PasswordResetIntent> createCodeResetIntent(String recoveryCode) async {
    proofCalls++;
    return PasswordResetIntent(
      resetIntentId: bytes(32, 11),
      expiresAt: now.add(const Duration(minutes: 10)),
      username: 'private_user',
      newRecoveryCode: 'AAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
  }

  @override
  Future<void> commitPasswordReset({
    required String resetIntentId,
    required String newPassword,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    resetCommits.add({'intentId': resetIntentId, 'key': idempotencyKey});
    await onCommitReset?.call();
  }

  @override
  Future<PasswordResetResult> passwordResetResult({
    required String resetIntentId,
    required String idempotencyKey,
  }) async {
    if (resetResultFailure != null) throw resetResultFailure!;
    return resetResult;
  }

  @override
  Future<ClosureAccepted> requestClosure({
    required String sessionToken,
    required String password,
    required String closureId,
    required String statusDigest,
  }) async {
    closureRequests.add({
      'id': closureId,
      'digest': statusDigest,
      'token': sessionToken,
    });
    return onClosure != null
        ? await onClosure!(closureId)
        : ClosureAccepted(
            closureId: closureId,
            dueAt: now.add(const Duration(days: 7)),
          );
  }

  @override
  Future<ClosureStatus> closureStatus({
    required String closureId,
    required String statusSecret,
  }) async {
    closureQueries.add({'id': closureId, 'secret': statusSecret});
    return onClosureStatus != null
        ? await onClosureStatus!()
        : ClosureStatus(
            state: ClosureState.pending,
            dueAt: now.add(const Duration(days: 7)),
          );
  }

  @override
  Future<OtpRequestAccepted> requestOtp({
    required String email,
    required String installationId,
    required String idempotencyKey,
  }) async {
    otpRequests.add({
      'email': email,
      'installationId': installationId,
      'key': idempotencyKey,
    });
    return onOtp != null
        ? await onOtp!()
        : OtpRequestAccepted(flowId: bytes(32, 12), retryAfterSeconds: 60);
  }

  @override
  Future<OtpRequestResult> otpRequestResult({
    required String installationId,
    required String idempotencyKey,
  }) async {
    if (otpResultFailure != null) throw otpResultFailure!;
    return const OtpRequestResult(
      state: OtpRequestState.pending,
      retryAfterSeconds: 20,
    );
  }

  @override
  Future<OtpConfirmation> confirmOtp({
    required String flowId,
    required String otp,
    required String slotId,
    required String bootstrapPublicKey,
    required String installationId,
    required String idempotencyKey,
    String? releaseReceipt,
  }) async {
    confirmations.add({
      'flowId': flowId,
      'otp': otp,
      'slotId': slotId,
      'publicKey': bootstrapPublicKey,
      'installationId': installationId,
      'key': idempotencyKey,
    });
    return OtpConfirmation(
      state: OtpConfirmationState.ticketAvailable,
      registrationTicket: ticket,
    );
  }

  @override
  Future<OtpConfirmationResult> otpConfirmationResult({
    required String flowId,
    required String installationId,
    required String idempotencyKey,
  }) async => const OtpConfirmationResult(state: OtpConfirmationState.pending);
  @override
  Future<RegistrationIntent> createRegistrationIntent({
    required String registrationTicket,
    required String username,
    required String password,
    required String installationId,
  }) async {
    registrationCreates.add({
      'ticket': registrationTicket,
      'username': username,
      'password': password,
      'installationId': installationId,
    });
    return RegistrationIntent(
      intentId: bytes(32, 13),
      challenge: bytes(32, 14),
      expiresAt: now.add(const Duration(minutes: 10)),
      recoveryCode: 'BBBBBBBBBBBBBBBBBBBBBBBBBA',
    );
  }

  @override
  Future<AuthSession> commitRegistration({
    required String intentId,
    required String bootstrapSignature,
    required String recoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    registrations.add({
      'intentId': intentId,
      'signature': bootstrapSignature,
      'key': idempotencyKey,
    });
    return onRegistration != null
        ? await onRegistration!()
        : AuthSession(
            accountId: session.accountId,
            sessionToken: session.token,
            expiresAt: session.expiresAt,
          );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  Harness() {
    store = AuthStore(vault);
    flows = makeFlows();
  }
  final vault = Vault();
  final api = Api();
  late final AuthStore store;
  late final AuthFlows flows;
  DateTime clock = now;
  int adopted = 0;
  int cleared = 0;
  AuthFlows makeFlows() => AuthFlows(
    api: api,
    store: store,
    clock: () => clock,
    clearCommunityAccess: () => cleared++,
    acceptRegistrationSession: (result) async {
      adopted++;
      await store.update(
        (old) => old.copyWith(
          session: SessionRecord(
            token: result.sessionToken,
            accountId: result.accountId,
            expiresAt: result.expiresAt,
          ),
        ),
      );
    },
  );
  Future<void> login() => store.update((old) => old.copyWith(session: session));
  Future<void> reset() async {
    await flows.beginCodeReset('OLD RECOVERY INPUT');
    flows.hideRecoveryCode();
  }

  Future<void> eligibility() async {
    await flows.requestOtp('Exact+Alias@hainanu.edu.cn');
    final registration = (await store.read()).registration!;
    final wire = Uint8List(156);
    wire.setAll(0, [...ascii.encode('HNUHOLE/REGISTER/V2'), 0]);
    ByteData.sublistView(wire).setUint32(20, 1);
    ByteData.sublistView(wire)
        .setUint32(24, now.millisecondsSinceEpoch ~/ 1800000);
    wire.setAll(
      28,
      AuthCrypto.decode(registration['slotId'] as String, bytes: 32),
    );
    wire.setAll(
      60,
      AuthCrypto.decode(registration['publicKey'] as String, bytes: 32),
    );
    api.ticket = AuthCrypto.encode(wire);
    await flows.confirmOtp('123456');
  }
}

void main() {
  test('code must be hidden before full confirmation and raw input is never stored', () async {
    final h = Harness();
    await h.flows.beginCodeReset('OLD RECOVERY INPUT');
    expect(h.flows.recoveryCode, isNotNull);
    await h.flows.commitReset('secret password', 'confirmation');
    expect(h.api.resetCommits, isEmpty);
    expect(h.flows.error?.code, 'HIDE_CODE_FIRST');
    h.flows.hideRecoveryCode();
    expect(h.flows.recoveryCode, isNull);
    await h.flows.commitReset('secret password', 'confirmation');
    expect(h.flows.status, AuthFlowStatus.resetCommitted);
    expect(h.vault.value, isNot(contains('secret password')));
    expect(h.vault.value, isNot(contains('confirmation')));
    expect(h.vault.value, isNot(contains('OLD RECOVERY INPUT')));
    expect(h.adopted, 0);
  });

  test('failure to durably write reset anchor prevents HTTP commit', () async {
    final h = Harness();
    await h.login();
    await h.reset();
    h.vault.failWrite = true;
    await h.flows.commitReset('secret password', 'confirmation');
    expect(h.api.resetCommits, isEmpty);
    expect(h.store.current, isNull);
    h.vault.failWrite = false;
    expect((await h.store.read()).session?.token, session.token);
  });

  test(
    'unknown reset survives restart and 404 PENDING 410 never mean uncommitted',
    () async {
      final h = Harness();
      await h.login();
      await h.reset();
      h.api.onCommitReset = () async {
        throw const AuthFailure(kind: AuthFailureKind.timeout);
      };
      await h.flows.commitReset('secret password', 'confirmation');
      final original = Map<String, dynamic>.from(
        (await h.store.read()).pendingReset!,
      );
      final resumed = h.makeFlows();
      await resumed.restorePending();
      expect(resumed.status, AuthFlowStatus.resetUnknown);
      expect(resumed.recoveryCode, isNull);
      h.api.resetResultFailure = const AuthFailure(
        kind: AuthFailureKind.rejected,
        statusCode: 404,
      );
      await resumed.reconcileReset();
      expect((await h.store.read()).pendingReset!['key'], original['key']);
      expect(resumed.status, AuthFlowStatus.resetUnknown);
      h.api.resetResultFailure = null;
      await resumed.reconcileReset();
      expect(resumed.status, AuthFlowStatus.resetUnknown);
      h.api.resetResultFailure = const AuthFailure(
        kind: AuthFailureKind.rejected,
        statusCode: 410,
        code: 'RESULT_EXPIRED',
      );
      await resumed.reconcileReset();
      expect((await h.store.read()).pendingReset!['state'], 'EXPIRED');
      await resumed.acknowledgeResetResult();
      expect((await h.store.read()).pendingReset, isNotNull);
      await resumed.beginCodeReset('different proof');
      expect(h.api.proofCalls, 1);
      expect(h.adopted, 0);
    },
  );

  test(
    'committed reset preserves closure and clears only its original token',
    () async {
      final h = Harness();
      await h.login();
      final closureSecret = bytes(32, 20);
      await h.store.update(
        (old) => old.copyWith(
          pendingClosure: {
            'v': 1,
            'closureId': bytes(32, 21),
            'statusSecret': closureSecret,
            'statusDigest': AuthCrypto.closureStatusDigest(closureSecret),
            'state': 'PENDING',
            'dueAt': now.add(const Duration(days: 7)).toIso8601String(),
          },
        ),
      );
      await h.reset();
      await h.flows.commitReset('secret password', 'confirmation');
      final stored = await h.store.read();
      expect(stored.pendingClosure!['state'], 'PENDING');
      expect(stored.session, isNull);
      expect(
        stored.logouts.single.revocationSecret,
        AuthCrypto.revocationSecret(session.token),
      );
      expect(h.adopted, 0);
    },
  );

  test(
    'late reset reply never clears a newer explicit password session',
    () async {
      final h = Harness();
      await h.login();
      await h.reset();
      final completer = Completer<void>();
      h.api.onCommitReset = () => completer.future;
      final commit = h.flows.commitReset('secret password', 'confirmation');
      await until(() => h.api.resetCommits.isNotEmpty);
      final newSession = SessionRecord(
        token: bytes(32, 30),
        accountId: session.accountId,
        expiresAt: session.expiresAt,
      );
      await h.store.update((old) => old.copyWith(session: newSession));
      completer.complete();
      await commit;
      expect((await h.store.read()).session?.token, newSession.token);
      expect((await h.store.read()).logouts, isEmpty);
    },
  );

  test('remote reset success followed by storage failure remains safely reconcilable', () async {
    final h = Harness();
    await h.reset();
    h.api.onCommitReset = () async {
      h.vault.failWrite = true;
    };
    await h.flows.commitReset('secret password', 'confirmation');
    expect(h.flows.status, AuthFlowStatus.resetUnknown);
    h.vault.failWrite = false;
    final resumed = h.makeFlows();
    await resumed.restorePending();
    h.api.resetResult = PasswordResetResult.committed;
    await resumed.reconcileReset();
    expect(resumed.status, AuthFlowStatus.resetCommitted);
    expect((await h.store.read()).pendingReset!['state'], 'COMMITTED');
  });

  test('closure secure-store failure cannot revoke local authority or submit request', () async {
    final h = Harness();
    await h.login();
    h.vault.failWrite = true;
    await h.flows.requestClosure('secret password');
    expect(h.api.closureRequests, isEmpty);
    h.vault.failWrite = false;
    expect((await h.store.read()).session?.token, session.token);
    expect((await h.store.read()).pendingClosure, isNull);
  });

  test(
    'closure unknown and early 404 retain original ID secret and exact retry',
    () async {
      final h = Harness();
      await h.login();
      h.api.onClosure = (_) async {
        throw const AuthFailure(kind: AuthFailureKind.timeout);
      };
      await h.flows.requestClosure('secret password');
      final original = Map<String, dynamic>.from(
        (await h.store.read()).pendingClosure!,
      );
      expect((await h.store.read()).session, isNull);
      expect(original['originalBearer'], session.token);
      final resumed = h.makeFlows();
      await resumed.restorePending();
      h.api.onClosureStatus = () async {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          statusCode: 404,
        );
      };
      await resumed.reconcileClosure();
      expect((await h.store.read()).pendingClosure, original);
      expect(resumed.status, AuthFlowStatus.closureUnknown);
      await resumed.requestClosure('new request');
      expect(h.api.closureRequests.length, 1);
      await resumed.retryClosure('secret password');
      expect(h.api.closureRequests[1], h.api.closureRequests[0]);
      expect(h.api.closureQueries.single['secret'], original['statusSecret']);
      await resumed.forgetClosureStatus();
      expect((await h.store.read()).pendingClosure, original);
    },
  );

  test('accepted closure drops temporary Bearer and terminal capability stays until explicit disposal', () async {
    final h = Harness();
    await h.login();
    await h.flows.requestClosure('secret password');
    final pending = (await h.store.read()).pendingClosure!;
    expect(pending.containsKey('originalBearer'), isFalse);
    expect(h.flows.status, AuthFlowStatus.closurePending);
    await h.flows.forgetClosureStatus();
    expect((await h.store.read()).pendingClosure, isNotNull);
    h.api.onClosureStatus = () async =>
        const ClosureStatus(state: ClosureState.cancelled);
    await h.flows.reconcileClosure();
    expect(
      (await h.store.read()).pendingClosure!['statusSecret'],
      pending['statusSecret'],
    );
    await h.flows.forgetClosureStatus();
    expect((await h.store.read()).pendingClosure, isNull);
  });

  test(
    'late closure response preserves a newer explicit password session',
    () async {
      final h = Harness();
      await h.login();
      final reply = Completer<ClosureAccepted>();
      h.api.onClosure = (_) => reply.future;
      final operation = h.flows.requestClosure('secret password');
      await until(() => h.api.closureRequests.isNotEmpty);
      final newSession = SessionRecord(
        token: bytes(32, 30),
        accountId: session.accountId,
        expiresAt: session.expiresAt,
      );
      await h.store.update((old) => old.copyWith(session: newSession));
      reply.complete(
        ClosureAccepted(
          closureId: h.api.closureRequests.single['id']!,
          dueAt: now.add(const Duration(days: 7)),
        ),
      );
      await operation;
      expect((await h.store.read()).session?.token, newSession.token);
    },
  );

  test('disposed reset controller cannot install a late result and restart queries original anchor', () async {
    final h = Harness();
    await h.reset();
    final reply = Completer<void>();
    h.api.onCommitReset = () => reply.future;
    final operation = h.flows.commitReset('secret password', 'confirmation');
    await until(() => h.api.resetCommits.isNotEmpty);
    h.flows.dispose();
    reply.complete();
    await operation;
    expect((await h.store.read()).pendingReset!['state'], 'UNKNOWN');
    final resumed = h.makeFlows();
    h.api.resetResult = PasswordResetResult.committed;
    await resumed.reconcileReset();
    expect(resumed.status, AuthFlowStatus.resetCommitted);
  });

  test(
    'OTP unknown retries use exact original key and separate installations',
    () async {
      final h = Harness();
      h.api.onOtp = () async {
        throw const AuthFailure(kind: AuthFailureKind.timeout);
      };
      await h.flows.requestOtp('Exact+Alias@hainanu.edu.cn');
      final first = (await h.store.read()).registration!;
      h.flows.resetFlow();
      await h.flows.requestOtp('other@hainanu.edu.cn');
      expect(h.api.otpRequests.length, 1);
      await h.flows.requestOtp('Exact+Alias@hainanu.edu.cn');
      expect(h.api.otpRequests.length, 2);
      expect(h.api.otpRequests[0], h.api.otpRequests[1]);
      expect((await h.store.read()).registration!['seed'], first['seed']);
      expect(
        (await h.store.read()).cInstallationId,
        isNot((await h.store.read()).vInstallationId),
      );
      await h.flows.reconcileOtpRequest();
      expect(h.flows.error?.code, 'OTP_QUERY_WAIT');
      h.clock = now.add(const Duration(seconds: 40));
      await h.flows.reconcileOtpRequest();
      expect(h.flows.status, AuthFlowStatus.otpRequestUnknown);
      expect(h.flows.otpWaitUntil, now.add(const Duration(seconds: 60)));
    },
  );

  test('registration sends C only eligibility and PoP, hides code and erases bootstrap after session persistence', () async {
    final h = Harness();
    await h.eligibility();
    expect(h.flows.status, AuthFlowStatus.eligibilityReady);
    await h.flows.createRegistration('Private_User', 'secret password');
    expect(h.flows.recoveryCode, isNotNull);
    await h.flows.commitRegistration('confirmation');
    expect(h.api.registrations, isEmpty);
    h.flows.hideRecoveryCode();
    expect(h.flows.recoveryCode, isNull);
    await h.flows.commitRegistration('confirmation');
    expect(h.flows.status, AuthFlowStatus.registrationComplete);
    expect(h.adopted, 1);
    expect((await h.store.read()).registration, isNull);
    expect(h.api.registrationCreates.single.keys.toSet(), {
      'ticket',
      'username',
      'password',
      'installationId',
    });
    expect(h.api.registrationCreates.single['username'], 'private_user');
    expect(
      h.api.registrationCreates.single['installationId'],
      (await h.store.read()).cInstallationId,
    );
    expect(h.api.registrationCreates.single.values, isNot(contains('123456')));
    expect(h.vault.value, isNot(contains('Exact+Alias')));
    expect(h.vault.value, isNot(contains('secret password')));
  });

  test(
    'lost registration response keeps anchor and cannot replay with a new key',
    () async {
      final h = Harness();
      await h.eligibility();
      await h.flows.createRegistration('private_user', 'secret password');
      h.flows.hideRecoveryCode();
      h.api.onRegistration = () async {
        throw const AuthFailure(kind: AuthFailureKind.timeout);
      };
      await h.flows.commitRegistration('confirmation');
      final anchor = (await h.store.read()).registration!['commit'];
      final resumed = h.makeFlows();
      await resumed.restorePending();
      expect(resumed.status, AuthFlowStatus.registrationUnknown);
      await resumed.commitRegistration('different');
      await resumed.createRegistration('other_user', 'new password');
      expect(h.api.registrations.length, 1);
      expect((await h.store.read()).registration!['commit'], anchor);
      expect(h.adopted, 0);
    },
  );

  test('expired OTP only exits on explicit action without automatic resend or new bootstrap', () async {
    final h = Harness();
    h.api.onOtp = () async {
      throw const AuthFailure(kind: AuthFailureKind.timeout);
    };
    await h.flows.requestOtp('Exact@hainanu.edu.cn');
    final seed = (await h.store.read()).registration!['seed'];
    h.clock = now.add(const Duration(minutes: 10));
    h.api.otpResultFailure = const AuthFailure(
      kind: AuthFailureKind.rejected,
      statusCode: 410,
      code: 'RESULT_EXPIRED',
    );
    await h.flows.reconcileOtpRequest();
    expect(h.api.otpRequests.length, 1);
    expect((await h.store.read()).registration!['request']['state'], 'EXPIRED');
    await h.flows.abandonExpiredOtpOperation();
    expect(h.api.otpRequests.length, 1);
    expect((await h.store.read()).registration!['seed'], seed);
    await h.flows.requestOtp('Exact@hainanu.edu.cn');
    expect(h.api.otpRequests.length, 2);
    expect(h.api.otpRequests[0]['key'], isNot(h.api.otpRequests[1]['key']));
  });

  test('secure workflow codec rejects malformed records before session authority is read', () async {
    final secret = bytes(32, 20);
    final validReset = <String, dynamic>{
      'v': 1,
      'intentId': bytes(32, 11),
      'key': bytes(32, 12),
      'state': 'UNKNOWN',
    };
    final validClosure = <String, dynamic>{
      'v': 1,
      'closureId': bytes(32, 21),
      'statusSecret': secret,
      'statusDigest': AuthCrypto.closureStatusDigest(secret),
      'state': 'PENDING',
      'dueAt': now.add(const Duration(days: 7)).toIso8601String(),
    };
    final invalid = <AuthState>[
      AuthState(session: session, pendingReset: {...validReset, 'v': 2}),
      AuthState(session: session, pendingReset: {...validReset, 'v': 1.0}),
      AuthState(
        session: session,
        pendingReset: {...validReset, 'state': 'SAFE_TO_LOGIN'},
      ),
      AuthState(
        session: session,
        pendingReset: {...validReset, 'key': '${bytes(32)}='},
      ),
      AuthState(
        session: session,
        pendingReset: {...validReset, 'intentId': bytes(16)},
      ),
      AuthState(
        session: session,
        pendingReset: {...validReset, 'password': 'forbidden'},
      ),
      AuthState(
        session: session,
        pendingClosure: {...validClosure, 'statusDigest': bytes(32, 99)},
      ),
      AuthState(
        session: session,
        pendingClosure: {...validClosure, 'originalBearer': session.token},
      ),
      AuthState(
        session: session,
        pendingClosure: {...validClosure, 'dueAt': '2026-09-30T24:00:00Z'},
      ),
      AuthState(
        session: session,
        pendingClosure: {...validClosure, 'dueAt': '2026-09-30T09:00:00+08:00'},
      ),
      AuthState(
        session: session,
        pendingClosure: {...validClosure, 'state': 'CANCELLED'},
      ),
      AuthState(
        session: session,
        pendingClosure: {...validClosure, 'state': 'RELEASED'},
      ),
    ];
    for (final state in invalid) {
      final vault = Vault()
        ..value = jsonEncode(state.toJson('hnuhole.isolated.auth.v1'));
      final store = AuthStore(vault);
      await expectLater(store.read(), throwsA(isA<AuthStorageFailure>()));
      expect(store.current, isNull);
    }
  });

  test(
    'two workflow controllers cannot create parallel reset commits',
    () async {
      final h = Harness();
      final other = h.makeFlows();
      await h.reset();
      await other.beginCodeReset('OLD RECOVERY INPUT');
      other.hideRecoveryCode();
      final reply = Completer<void>();
      h.api.onCommitReset = () => reply.future;
      final first = h.flows.commitReset('password', 'confirmation');
      await until(() => h.api.resetCommits.isNotEmpty);
      await other.commitReset('other password', 'confirmation');
      expect(h.api.resetCommits.length, 1);
      expect(
        (await h.store.read()).pendingReset!['key'],
        h.api.resetCommits.single['key'],
      );
      reply.complete();
      await first;
    },
  );

  test(
    'closure state never regresses and its accepted deadline cannot move',
    () async {
      final h = Harness();
      await h.login();
      await h.flows.requestClosure('secret password');
      h.api.onClosureStatus = () async => ClosureStatus(
        state: ClosureState.pending,
        dueAt: now.add(const Duration(days: 8)),
      );
      await h.flows.reconcileClosure();
      expect(
        (await h.store.read()).pendingClosure!['dueAt'],
        now.add(const Duration(days: 7)).toIso8601String(),
      );
      h.api.onClosureStatus = () async =>
          const ClosureStatus(state: ClosureState.cancelled);
      await h.flows.reconcileClosure();
      h.api.onClosureStatus = () async => ClosureStatus(
        state: ClosureState.pending,
        dueAt: now.add(const Duration(days: 7)),
      );
      await h.flows.reconcileClosure();
      expect((await h.store.read()).pendingClosure!['state'], 'CANCELLED');
      expect(h.flows.status, AuthFlowStatus.closureCancelled);
    },
  );

  test('definite registration rejection allows a new intent without freeing the original slot', () async {
    final h = Harness();
    await h.eligibility();
    final bootstrap = (await h.store.read()).registration!['seed'];
    await h.flows.createRegistration('private_user', 'secret password');
    h.flows.hideRecoveryCode();
    h.api.onRegistration = () async {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        statusCode: 422,
        code: 'INTENT_INVALID',
      );
    };
    await h.flows.commitRegistration('wrong full code');
    expect((await h.store.read()).registration!['commit'], isNull);
    expect((await h.store.read()).registration!['seed'], bootstrap);
    expect(h.flows.status, AuthFlowStatus.eligibilityReady);
    await h.flows.createRegistration('private_user', 'secret password');
    expect(h.api.registrationCreates.length, 2);
    expect(h.api.otpRequests.length, 1);
  });
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 100 && !predicate(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Operation did not reach expected barrier',
  );
}
