/// Failures never retain request bodies, credentials or server messages.
enum AuthFailureKind {
  unauthorized,
  unavailable,
  timeout,
  unknownOutcome,
  rejected,
  invalidResponse,
}

class AuthFailure implements Exception {
  const AuthFailure({
    required this.kind,
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
  });

  final AuthFailureKind kind;
  final int? statusCode;
  final String? code;
  final int? retryAfterSeconds;
  String? get errorCode => code;
  bool get unauthorized => kind == AuthFailureKind.unauthorized;
  bool get resultsExpired => statusCode == 410 && code == 'RESULT_EXPIRED';
  bool get uncertain =>
      kind == AuthFailureKind.unavailable ||
      kind == AuthFailureKind.timeout ||
      kind == AuthFailureKind.unknownOutcome ||
      kind == AuthFailureKind.invalidResponse ||
      code == 'OPERATION_PENDING';

  @override
  String toString() => 'AuthFailure(${kind.name}, status: $statusCode)';
}

class AuthSession {
  const AuthSession({
    required this.accountId,
    required this.sessionToken,
    required this.expiresAt,
  });
  final String accountId;
  final String sessionToken;
  final DateTime expiresAt;
}

class CurrentSession {
  const CurrentSession({
    required this.accountId,
    required this.username,
    required this.expiresAt,
  });
  final String accountId;
  final String username;
  final DateTime expiresAt;
}

class OtpRequestAccepted {
  const OtpRequestAccepted({
    required this.flowId,
    required this.retryAfterSeconds,
  });
  final String flowId;
  final int retryAfterSeconds;
}

enum OtpRequestState { accepted, notSent, pending }

class OtpRequestResult {
  const OtpRequestResult({
    required this.state,
    required this.retryAfterSeconds,
    this.flowId,
  });
  final OtpRequestState state;
  final int retryAfterSeconds;
  final String? flowId;
}

enum OtpConfirmationState {
  ticketAvailable,
  confirmationPending,
  retirementPending,
  pending,
  reverifyRequired,
  notCommitted,
}

class OtpConfirmation {
  const OtpConfirmation({
    required this.state,
    this.registrationTicket,
    this.retryAfterSeconds,
  });
  final OtpConfirmationState state;
  final String? registrationTicket;
  final int? retryAfterSeconds;
}

class OtpConfirmationResult {
  const OtpConfirmationResult({required this.state, this.retryAfterSeconds});
  final OtpConfirmationState state;
  final int? retryAfterSeconds;
}

class RegistrationIntent {
  const RegistrationIntent({
    required this.intentId,
    required this.challenge,
    required this.expiresAt,
    required this.recoveryCode,
  });
  final String intentId;
  final String challenge;
  final DateTime expiresAt;
  final String recoveryCode;
}

class PasswordResetIntent {
  const PasswordResetIntent({
    required this.resetIntentId,
    required this.expiresAt,
    required this.username,
    required this.newRecoveryCode,
  });
  final String resetIntentId;
  final DateTime expiresAt;
  final String username;
  final String newRecoveryCode;
}

enum PasswordResetResult { committed, notCommitted, pending }

class ClosureAccepted {
  const ClosureAccepted({required this.closureId, required this.dueAt});
  final String closureId;
  final DateTime dueAt;
}

enum ClosureState {
  pending,
  finalizing,
  cancelled,
  closedReleasePending,
  released,
}

class ClosureStatus {
  const ClosureStatus({required this.state, this.dueAt, this.releaseReceipt});
  final ClosureState state;
  final DateTime? dueAt;
  final String? releaseReceipt;
}

class RecoveryCodeRotation {
  const RecoveryCodeRotation({
    required this.rotationIntentId,
    required this.expiresAt,
    required this.newRecoveryCode,
    this.sessionExpiresAt,
  });
  final String rotationIntentId;
  final DateTime expiresAt;
  final String newRecoveryCode;
  final DateTime? sessionExpiresAt;
}

class RecoveryCredentialSummary {
  const RecoveryCredentialSummary({required this.passkeys, this.sessionExpiresAt});
  final List<PasskeySummary> passkeys;
  final DateTime? sessionExpiresAt;
}

class PasskeySummary {
  const PasskeySummary({
    required this.credentialId,
    required this.createdAt,
    required this.backupEligible,
    required this.backedUp,
  });
  final String credentialId;
  final DateTime createdAt;
  final bool backupEligible;
  final bool backedUp;
}

class PasskeyRemovalIntent {
  const PasskeyRemovalIntent({
    required this.removalIntentId,
    required this.expiresAt,
    this.sessionExpiresAt,
  });
  final String removalIntentId;
  final DateTime expiresAt;
  final DateTime? sessionExpiresAt;
}

/// The server deliberately supplies no installation ID, token, IP or hardware.
class DeviceDirectory {
  const DeviceDirectory({
    required this.currentSignedInAt,
    required this.sessionExpiresAt,
    this.lastReplacedSignedInAt,
    this.lastReplacedAt,
  });
  final DateTime currentSignedInAt;
  final DateTime sessionExpiresAt;
  final DateTime? lastReplacedSignedInAt, lastReplacedAt;
}

class PasskeyOptions {
  const PasskeyOptions({
    required this.challengeId,
    required this.expiresAt,
    required this.publicKey,
    this.sessionExpiresAt,
  });
  final String challengeId;
  final DateTime expiresAt;
  final Map<String, dynamic> publicKey;
  // Discoverable recovery is unauthenticated and has no session metadata.
  final DateTime? sessionExpiresAt;
}

enum CredentialChangeState { pending, committed, notCommitted }

class CredentialChangeOutcome {
  const CredentialChangeOutcome({
    required this.state,
    required this.sessionExpiresAt,
  });
  final CredentialChangeState state;
  final DateTime sessionExpiresAt;
}
