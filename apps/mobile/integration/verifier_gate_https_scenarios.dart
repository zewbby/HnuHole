import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/http_auth_api.dart';

/// R05 uses real V/C handlers and SQL, with independent signed Gate clocks.
/// The private control API only injects faults; public requests use shipped code.
Future<void> verifyVerifierGateHttpsScenarios({
  required HttpAuthApi api,
  required String communityToken,
  required Future<Map<String, dynamic>> Function(String, Map<String, String>) fixture,
}) async {
  const email = 'synthetic-mobile-v-gate@hainanu.edu.cn';
  final installation = AuthCrypto.randomEncoded(16);
  final requestKey = AuthCrypto.randomEncoded(32);
  final requested = await api.requestOtp(email: email,
    installationId: installation, idempotencyKey: requestKey);
  final mail = await fixture('otp', {'email': email});
  final bootstrap = await AuthCrypto.newBootstrapKey();
  final confirmationKey = AuthCrypto.randomEncoded(32);
  Future<OtpConfirmation> confirm() => api.confirmOtp(
    flowId: requested.flowId, otp: mail['code'] as String,
    slotId: bootstrap.slotId, bootstrapPublicKey: bootstrap.publicKey,
    installationId: installation, idempotencyKey: confirmationKey);

  await fixture('freeze-verifier', {});
  expect((await api.currentSession(communityToken)).accountId, isNotEmpty);
  await expectLater(confirm(), throwsA(isA<AuthFailure>()
    .having((e) => e.statusCode, 'frozen V status', 503)));
  await expectLater(api.otpRequestResult(installationId: installation,
    idempotencyKey: requestKey), throwsA(isA<AuthFailure>()
    .having((e) => e.statusCode, 'frozen V result status', 503)));
  await expectLater(api.requestOtp(email: 'synthetic-mobile-v-blocked@hainanu.edu.cn',
    installationId: AuthCrypto.randomEncoded(16),
    idempotencyKey: AuthCrypto.randomEncoded(32)), throwsA(isA<AuthFailure>()
    .having((e) => e.statusCode, 'frozen V request status', 503)));

  await fixture('recover-verifier', {});
  expect((await api.currentSession(communityToken)).accountId, isNotEmpty);
  await expectLater(confirm(), throwsA(isA<AuthFailure>()
    .having((e) => e.code, 'old V generation', 'OTP_EXPIRED')));
  final freshInstallation = AuthCrypto.randomEncoded(16);
  // Use a distinct synthetic address so this recovery assertion does not
  // bypass the previous address's independent resend cooldown.
  const freshEmail = 'synthetic-mobile-v-fresh@hainanu.edu.cn';
  final fresh = await api.requestOtp(email: freshEmail,
    installationId: freshInstallation,
    idempotencyKey: AuthCrypto.randomEncoded(32));
  final freshMail = await fixture('otp', {'email': freshEmail});
  final freshBootstrap = await AuthCrypto.newBootstrapKey();
  final qualified = await api.confirmOtp(flowId: fresh.flowId,
    otp: freshMail['code'] as String, slotId: freshBootstrap.slotId,
    bootstrapPublicKey: freshBootstrap.publicKey,
    installationId: freshInstallation,
    idempotencyKey: AuthCrypto.randomEncoded(32));
  expect(qualified.registrationTicket, isNotEmpty);
}
