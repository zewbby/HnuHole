import 'auth_models.dart';

/// Explicit foreground management. Final submissions are never retried by the
/// transport; their durable owner retains the original intent and request key.
abstract interface class CredentialManagementApi {
  Future<DeviceDirectory> devices(String sessionToken);
  Future<RecoveryCredentialSummary> recoveryCredentials(String sessionToken);
  Future<RecoveryCodeRotation> createRecoveryCodeRotation({
    required String sessionToken,
    required String password,
  });
  Future<DateTime> confirmRecoveryCodeRotation({
    required String sessionToken,
    required String rotationIntentId,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  });
  Future<PasskeyOptions> createPasskeyCreationOptions({
    required String sessionToken,
    required String password,
  });
  Future<DateTime> registerPasskey({
    required String sessionToken,
    required String challengeId,
    required Map<String, dynamic> attestation,
    required String idempotencyKey,
  });
  Future<PasskeyRemovalIntent> createPasskeyRemovalIntent({
    required String sessionToken,
    required String credentialId,
    required String password,
  });
  Future<DateTime> removePasskey({
    required String sessionToken,
    required String credentialId,
    required String removalIntentId,
    required String idempotencyKey,
  });
  Future<CredentialChangeOutcome> credentialChangeResult({
    required String sessionToken,
    required String changeId,
    required String idempotencyKey,
  });
}

/// Recovering with a Passkey establishes a restricted reset intent; it never
/// signs in and never supplies any username, email or allowCredentials hint.
abstract interface class PasskeyRecoveryApi {
  Future<PasskeyOptions> createPasskeyResetOptions();
  Future<PasswordResetIntent> createPasskeyResetIntent({
    required String challengeId,
    required Map<String, dynamic> assertion,
  });
}
