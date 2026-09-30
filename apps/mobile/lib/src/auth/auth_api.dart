import 'auth_models.dart';

/// C and V are independent boundaries. Installation IDs and original request
/// keys are supplied explicitly so their durable owners control retries.
abstract interface class AuthApi {
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  });
  Future<CurrentSession> currentSession(String sessionToken);
  Future<DateTime> renewSession(String sessionToken);
  Future<void> revokeSession(String revocationSecret);
  Future<OtpRequestAccepted> requestOtp({
    required String email,
    required String installationId,
    required String idempotencyKey,
  });
  Future<OtpRequestResult> otpRequestResult({
    required String installationId,
    required String idempotencyKey,
  });
  Future<OtpConfirmation> confirmOtp({
    required String flowId,
    required String otp,
    required String slotId,
    required String bootstrapPublicKey,
    required String installationId,
    required String idempotencyKey,
    String? releaseReceipt,
  });
  Future<OtpConfirmationResult> otpConfirmationResult({
    required String flowId,
    required String installationId,
    required String idempotencyKey,
  });
  Future<RegistrationIntent> createRegistrationIntent({
    required String registrationTicket,
    required String username,
    required String password,
    required String installationId,
  });
  Future<AuthSession> commitRegistration({
    required String intentId,
    required String bootstrapSignature,
    required String recoveryCodeConfirmation,
    required String idempotencyKey,
  });
  Future<PasswordResetIntent> createCodeResetIntent(String recoveryCode);
  Future<void> commitPasswordReset({
    required String resetIntentId,
    required String newPassword,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  });
  Future<PasswordResetResult> passwordResetResult({
    required String resetIntentId,
    required String idempotencyKey,
  });
  Future<ClosureAccepted> requestClosure({
    required String sessionToken,
    required String password,
    required String closureId,
    required String statusDigest,
  });
  Future<ClosureStatus> closureStatus({
    required String closureId,
    required String statusSecret,
  });
}
