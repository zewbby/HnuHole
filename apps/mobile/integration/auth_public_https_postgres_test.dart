import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_flows.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_session_controller.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/auth/http_auth_api.dart';
import 'package:hnuhole_mobile/src/channels/channel.dart';
import 'package:hnuhole_mobile/src/channels/channel_repository.dart';
import 'package:hnuhole_mobile/src/navigation/channel_directory_controller.dart';

/// Only the native persistence port is replaced. Every authentication request
/// traverses the shipped Dart transport, real Go TLS handler, and two real DBs.
/// This does not certify Keychain/Keystore durability or business directories.
class _LabVault implements AuthVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

class _UnavailableBusinessDirectory implements ChannelRepository {
  @override
  Future<List<Channel>> loadChannels({required String sessionToken}) async =>
      throw const ChannelRepositoryException(
        message: 'Business API is outside the isolated authentication lab.',
        statusCode: 503,
      );
}

void main() {
  final configPath = Platform.environment['AUTHLAB_MOBILE_CONFIG'];
  if (configPath == null) {
    test(
      'real public C/V HTTPS/PostgreSQL runner required',
      () {},
      skip: 'Run services/api/authlab/run-mobile-isolated.sh',
    );
    return;
  }
  test(
    'real C/V TLS signup, takeover, revoke, reset, closure and Gate faults',
    () async {
      final config = jsonDecode(
        File(configPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(config['caPath'] as String);
      final api = HttpAuthApi(
        communityBaseUri: Uri.parse(config['communityOrigin'] as String),
        verifierBaseUri: Uri.parse(config['verifierOrigin'] as String),
        client: HttpClient(context: trust),
        timeout: const Duration(seconds: 20),
      );
      final control = HttpClient(context: trust);
      addTearDown(() {
        api.close();
        control.close(force: true);
      });
      Future<Map<String, dynamic>> fixture(
        String action, [
        Map<String, String> body = const {},
      ]) async {
        final request = await control.postUrl(
          Uri.parse(config['controlOrigin'] as String).resolve('/$action'),
        );
        request.followRedirects = false;
        request.headers.set(
          'Authorization',
          'LabControl ${config['controlToken']}',
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        expect(
          response.statusCode,
          200,
          reason: 'Private fixture $action failed',
        );
        return jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
      }

      final vault = _LabVault();
      var store = AuthStore(vault, scope: 'isolated-real-CV-test');
      var directory = ChannelDirectoryController(
        repository: _UnavailableBusinessDirectory(),
      );
      var sessions = AuthSessionController(
        api: api,
        store: store,
        directory: directory,
      );
      var clientClock = DateTime.now().toUtc();
      AuthFlows flowsForCurrentStore() => AuthFlows(
        api: api,
        store: store,
        acceptRegistrationSession: sessions.acceptSession,
        clearCommunityAccess: sessions.clearCommunityAccess,
        clock: () => clientClock,
      );
      var flows = flowsForCurrentStore();
      addTearDown(() {
        flows.dispose();
        sessions.dispose();
        directory.dispose();
        store.dispose();
      });
      Future<void> restartClient() async {
        flows.dispose();
        sessions.dispose();
        directory.dispose();
        store.dispose();
        store = AuthStore(vault, scope: 'isolated-real-CV-test');
        directory = ChannelDirectoryController(
          repository: _UnavailableBusinessDirectory(),
        );
        sessions = AuthSessionController(
          api: api,
          store: store,
          directory: directory,
        );
        flows = flowsForCurrentStore();
        await sessions.start();
        await flows.restorePending();
      }

      const email = 'synthetic-mobile@hainanu.edu.cn';
      const username = 'synthetic_mobile';
      const password = 'isolated mobile long password 2026!';
      const resetPassword = 'isolated mobile changed password 2026!';
      await sessions.start();
      expect(sessions.status, AuthStatus.signedOut);
      await fixture('drop-next', {'path': '/api/v1/eligibility/otp-requests'});
      await flows.requestOtp(email);
      expect(flows.status, AuthFlowStatus.otpRequestUnknown);
      final originalOtpKey = store.current!.registration!['request']['key'];
      clientClock = clientClock.add(const Duration(seconds: 41));
      await restartClient();
      expect(flows.status, AuthFlowStatus.otpRequestUnknown);
      await flows.reconcileOtpRequest();
      expect(flows.status, AuthFlowStatus.otpRequested);
      expect(store.current!.registration!['request']['key'], originalOtpKey);
      final mail = await fixture('otp', {'email': email});
      expect(mail['mailCalls'], 1);
      await flows.confirmOtp(mail['code'] as String);
      expect(flows.status, AuthFlowStatus.eligibilityReady);
      final slot = store.current!.registration!['slotId'] as String;
      await flows.createRegistration(username, password);
      expect(flows.status, AuthFlowStatus.registrationCodeShown);
      final originalCode = flows.recoveryCode!;
      flows.hideRecoveryCode();
      expect(flows.recoveryCode, isNull);
      await flows.commitRegistration(originalCode);
      expect(flows.status, AuthFlowStatus.registrationComplete);
      expect(sessions.isAuthenticated, isTrue);
      expect(store.current!.registration, isNull);
      final signupToken = store.current!.session!.token;
      final expiry = await api.renewSession(signupToken);
      expect(expiry.isBefore(store.current!.session!.expiresAt), isFalse);

      final secondSession = await api.login(
        username: username,
        password: password,
        installationId: AuthCrypto.randomEncoded(16),
        idempotencyKey: AuthCrypto.randomEncoded(32),
      );
      await expectLater(
        api.currentSession(signupToken),
        throwsA(
          isA<AuthFailure>().having((e) => e.code, 'code', 'session_replaced'),
        ),
      );
      await sessions.retry();
      expect(sessions.status, AuthStatus.signedOut);
      expect(store.current!.session, isNull);
      await sessions.acceptSession(secondSession);
      expect(sessions.isAuthenticated, isTrue);

      await fixture('drop-next', {'path': '/api/v1/auth/session-revocations'});
      await sessions.logout();
      expect(store.current!.session, isNull);
      expect(store.current!.logouts, hasLength(1));
      expect(store.current!.logouts.single.revocationSecret, isNotNull);
      await restartClient();
      await sessions.retryPendingLogout();
      expect(store.current!.logouts, isEmpty);
      expect(sessions.status, AuthStatus.signedOut);
      await expectLater(
        api.currentSession(secondSession.sessionToken),
        throwsA(isA<AuthFailure>().having((e) => e.unauthorized, '401', true)),
      );

      await sessions.login(username, password);
      expect(sessions.isAuthenticated, isTrue);
      final beforeFreezeToken = store.current!.session!.token;
      await fixture('freeze');
      await sessions.retry();
      expect(sessions.status, AuthStatus.unavailable);
      expect(store.current!.session!.token == beforeFreezeToken, isTrue);
      expect(directory.channels, isEmpty);
      await fixture('recover');
      await sessions.retry();
      expect(sessions.status, AuthStatus.signedOut);
      expect(store.current!.session, isNull);
      await sessions.login(username, password);
      expect(sessions.isAuthenticated, isTrue);

      await flows.beginCodeReset(originalCode);
      expect(flows.status, AuthFlowStatus.resetCodeShown);
      final newCode = flows.recoveryCode!;
      flows.hideRecoveryCode();
      await fixture('drop-next', {'path': '/api/v1/auth/password-resets'});
      await flows.commitReset(resetPassword, newCode);
      expect(flows.status, AuthFlowStatus.resetUnknown);
      final resetKey = store.current!.pendingReset!['key'];
      await restartClient();
      expect(sessions.isAuthenticated, isFalse);
      expect(flows.status, AuthFlowStatus.resetUnknown);
      expect(store.current!.pendingReset!['key'], resetKey);
      await flows.reconcileReset();
      expect(flows.status, AuthFlowStatus.resetCommitted);
      expect(sessions.isAuthenticated, isFalse);
      expect(store.current!.session, isNull);
      await flows.acknowledgeResetResult();
      await sessions.login(username, password);
      expect(sessions.isAuthenticated, isFalse);
      await sessions.login(username, resetPassword);
      expect(sessions.isAuthenticated, isTrue);

      await fixture('drop-next', {'path': '/api/v1/account-closures'});
      await flows.requestClosure(resetPassword);
      expect(flows.status, AuthFlowStatus.closureUnknown);
      final closureId = store.current!.pendingClosure!['closureId'];
      final closureSecret = store.current!.pendingClosure!['statusSecret'];
      expect(sessions.isAuthenticated, isFalse);
      await restartClient();
      expect(flows.status, AuthFlowStatus.closureUnknown);
      await flows.reconcileClosure();
      expect(flows.status, AuthFlowStatus.closurePending);
      expect(store.current!.pendingClosure!['originalBearer'], isNull);
      expect(store.current!.pendingClosure!['closureId'], closureId);
      expect(store.current!.pendingClosure!['statusSecret'], closureSecret);
      await sessions.login(username, resetPassword);
      expect(sessions.isAuthenticated, isTrue);
      await flows.reconcileClosure();
      expect(flows.status, AuthFlowStatus.closureCancelled);
      await flows.forgetClosureStatus();
      await flows.requestClosure(resetPassword);
      expect(flows.status, AuthFlowStatus.closurePending);
      await fixture('finalize');
      await flows.reconcileClosure();
      expect(flows.status, AuthFlowStatus.closureClosedReleasePending);
      await fixture('deliver-release', {'slotId': slot});
      await flows.reconcileClosure();
      expect(flows.status, AuthFlowStatus.closureReleased);
      expect(flows.closureStatus!.releaseReceipt, isNotEmpty);
      expect(sessions.isAuthenticated, isFalse);
      await sessions.login(username, resetPassword);
      expect(sessions.isAuthenticated, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
