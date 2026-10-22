import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_api.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_flows.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';

import 'auth_flows_test.dart' as f;

class EmailApi extends f.Api implements EmailLoginApi {
  final sends = <Map<String, String>>[],
      confirms = <Map<String, String>>[],
      sessions = <Map<String, String>>[];
  bool sendTimeout = false,
      confirmTimeout = false,
      sessionTimeout = false,
      unregistered = false;
  String? sessionError;
  Future<AuthSession> Function()? onCreate;
  bool revokeTimeout = false;
  final revoked = <String>[];
  @override
  Future<void> revokeSession(String secret) async {
    revoked.add(secret);
    if (revokeTimeout) throw const AuthFailure(kind: AuthFailureKind.timeout);
  }

  @override
  Future<OtpRequestAccepted> requestEmailLoginOtp({
    required String email,
    required String installationId,
    required String idempotencyKey,
  }) async {
    sends.add({'email': email, 'id': installationId, 'key': idempotencyKey});
    if (sendTimeout) throw const AuthFailure(kind: AuthFailureKind.timeout);
    return OtpRequestAccepted(flowId: f.bytes(32, 4), retryAfterSeconds: 60);
  }

  @override
  Future<String?> confirmEmailLoginOtp({
    required String flowId,
    required String otp,
    required String binding,
    required String installationId,
    required String idempotencyKey,
  }) async {
    confirms.add({
      'flow': flowId,
      'otp': otp,
      'binding': binding,
      'id': installationId,
      'key': idempotencyKey,
    });
    if (confirmTimeout) throw const AuthFailure(kind: AuthFailureKind.timeout);
    return unregistered ? null : f.bytes(227, 5);
  }

  @override
  Future<AuthSession> createEmailSession({
    required String proof,
    required String installationId,
    required String idempotencyKey,
  }) async {
    if (onCreate != null) return onCreate!();
    sessions.add({'proof': proof, 'id': installationId, 'key': idempotencyKey});
    if (sessionTimeout) throw const AuthFailure(kind: AuthFailureKind.timeout);
    if (sessionError != null) {
      throw AuthFailure(kind: AuthFailureKind.rejected, code: sessionError);
    }
    return AuthSession(
      accountId: f.session.accountId,
      sessionToken: f.session.token,
      expiresAt: f.session.expiresAt,
    );
  }
}

class EmailHarness {
  final vault = f.Vault(), api = EmailApi();
  late final store = AuthStore(vault);
  int adopted = 0;
  int authority = 0;
  AuthFlows make() => AuthFlows(
    api: api,
    store: store,
    clock: () => f.now,
    sessionAuthorityVersion: () => authority,
    clearCommunityAccess: () {},
    acceptRegistrationSession: (session) async {
      adopted++;
      await store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            token: session.sessionToken,
            accountId: session.accountId,
            expiresAt: session.expiresAt,
          ),
        ),
      );
    },
  );
}

void main() {
  test(
    'late C success keeps durable revocation when immediate revoke times out',
    () async {
      final h = EmailHarness();
      final flow = h.make();
      await flow.requestEmailLogin('owned@hainanu.edu.cn');
      final ready = Completer<void>(), reply = Completer<AuthSession>();
      h.api.onCreate = () {
        ready.complete();
        return reply.future;
      };
      h.api.revokeTimeout = true;
      final pending = flow.completeEmailLogin('123456');
      await ready.future;
      h.authority++;
      reply.complete(
        AuthSession(
          accountId: f.session.accountId,
          sessionToken: f.session.token,
          expiresAt: f.session.expiresAt,
        ),
      );
      await pending;
      expect(h.adopted, 0);
      expect(h.store.current!.logouts.length, 1);
      expect(h.api.revoked.length, 1);
      final restarted = AuthStore(h.vault);
      final state = await restarted.read();
      expect(state.logouts.single.revocationSecret, isNotNull);
      expect(state.session, isNull);
    },
  );

  test(
    'unknown send resumes original key and installation across restart',
    () async {
      final h = EmailHarness();
      h.api.sendTimeout = true;
      final a = h.make();
      await a.requestEmailLogin('owned@hainanu.edu.cn');
      final old = h.api.sends.single;
      h.api.sendTimeout = false;
      await h.make().requestEmailLogin('owned@hainanu.edu.cn');
      expect(h.api.sends.last, old);
      expect(h.api.otpRequests, isEmpty);
      await h.make().requestEmailLogin('owned@hainanu.edu.cn');
      expect(h.api.sends.length, 2);
    },
  );
  test(
    'confirmation timeout preserves exact code and original key securely',
    () async {
      final h = EmailHarness();
      final a = h.make();
      await a.requestEmailLogin('owned@hainanu.edu.cn');
      h.api.confirmTimeout = true;
      await a.completeEmailLogin('123456');
      final old = h.api.confirms.single;
      h.api.confirmTimeout = false;
      await h.make().completeEmailLogin('654321');
      expect(h.api.confirms.last, old);
      expect(h.adopted, 1);
      expect(h.store.current!.emailLogin, isNull);
      expect(h.vault.value, isNot(contains('123456')));
    },
  );
  test(
    'unknown C submission resumes same proof and key without confirming twice',
    () async {
      final h = EmailHarness();
      final a = h.make();
      await a.requestEmailLogin('owned@hainanu.edu.cn');
      h.api.sessionTimeout = true;
      await a.completeEmailLogin('123456');
      final old = h.api.sessions.single;
      h.api.sessionTimeout = false;
      await h.make().completeEmailLogin('');
      expect(h.api.sessions.last, old);
      expect(h.api.confirms.length, 1);
      expect(h.adopted, 1);
    },
  );
  test(
    'unregistered verification never silently creates account or session',
    () async {
      final h = EmailHarness();
      h.api.unregistered = true;
      final a = h.make();
      await a.requestEmailLogin('owned@hainanu.edu.cn');
      await a.completeEmailLogin('123456');
      expect(a.emailUnregistered, isTrue);
      expect(h.api.sessions, isEmpty);
      expect(h.api.registrationCreates, isEmpty);
      expect(h.adopted, 0);
      await a.clearEmailLogin();
      expect(h.store.current!.emailLogin, isNull);
    },
  );
  test('native storage failure prevents sending or adopting', () async {
    final h = EmailHarness();
    h.vault.failWrite = true;
    await h.make().requestEmailLogin('owned@hainanu.edu.cn');
    expect(h.api.sends, isEmpty);
    expect(h.adopted, 0);
  });
  test('created-session replay requires explicit fresh verification', () async {
    final h = EmailHarness();
    h.api.sessionError = 'SESSION_CREATED_RETRY_LOGIN';
    final a = h.make();
    await a.requestEmailLogin('owned@hainanu.edu.cn');
    await a.completeEmailLogin('123456');
    expect(h.store.current!.emailLogin, isNull);
    expect(h.adopted, 0);
    expect(a.errorMessage, contains('重新发送验证码'));
  });
}
