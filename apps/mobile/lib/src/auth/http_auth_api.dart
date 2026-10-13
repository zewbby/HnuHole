import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_api.dart';
import 'auth_crypto.dart';
import 'auth_models.dart';
import 'credential_management_api.dart';
import '../identity/identity_api.dart';

/// Fixed HTTPS origins, no redirects, cookies, telemetry or cross-party headers.
/// The caller owns durable original keys; this transport never retries a POST.
class HttpAuthApi
    implements
        AuthApi,
        CredentialManagementApi,
        PasskeyRecoveryApi,
        IdentityApi {
  HttpAuthApi({
    required this.communityBaseUri,
    required this.verifierBaseUri,
    HttpClient? client,
    this.timeout = const Duration(seconds: 12),
    this.maxResponseBytes = 32768,
    this.passkeyRpId,
  }) : _client = client ?? HttpClient() {
    _validateOrigin(communityBaseUri);
    _validateOrigin(verifierBaseUri);
    if (passkeyRpId != null &&
        (passkeyRpId!.length > 253 ||
            !RegExp(
              r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
            ).hasMatch(passkeyRpId!) ||
            passkeyRpId!.split('.').any((label) => label.length > 63) ||
            InternetAddress.tryParse(passkeyRpId!) != null)) {
      throw ArgumentError('An explicit canonical DNS Passkey RP is required');
    }
    if (communityBaseUri.origin == verifierBaseUri.origin ||
        timeout <= Duration.zero ||
        maxResponseBytes < 1024 ||
        maxResponseBytes > 65536) {
      throw ArgumentError(
        'Independent HTTPS origins and bounded transport limits required',
      );
    }
    _client.connectionTimeout = timeout;
  }

  final Uri communityBaseUri;
  final Uri verifierBaseUri;
  final Duration timeout;
  final int maxResponseBytes;

  /// Optional application-pinned RP, independent of the HTTPS API transport.
  /// A server response can never select or expand this configured authority.
  final String? passkeyRpId;
  final HttpClient _client;

  static void _validateOrigin(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError('A fixed HTTPS origin is required');
    }
  }

  void close() => _client.close(force: true);

  @override
  Future<IdentityDirectory> identities(String sessionToken) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/identities',
      headers: _capability('Bearer', sessionToken),
      expected: {200},
      allowNull: true,
    );
    return _model(() {
      final m = _record(
        r.body,
        {'identities', 'createdCount', 'nextCreateAt', 'serverTime'},
        nullable: {'nextCreateAt'},
      );
      final items = m['identities'];
      if (items is! List || items.length > 3) {
        throw const FormatException('Invalid identity list');
      }
      final ids = <String>{}, names = <String>{};
      var originals = 0;
      final serverTime = _date(m, 'serverTime');
      final identities = items
          .map((raw) {
            final item = _record(
              raw,
              {
                'id',
                'nickname',
                'avatar',
                'isOriginal',
                'createdAt',
                'renameAvailableAt',
              },
              nullable: {'renameAvailableAt'},
            );
            final id = _identityId(_text(item, 'id'));
            final nickname = _text(item, 'nickname', maxLength: 512);
            if (utf8.encode(nickname).length > 512) {
              throw const FormatException('Invalid identity nickname size');
            }
            final original = item['isOriginal'];
            final created = _date(item, 'createdAt');
            if (original is! bool ||
                item['avatar'] != 'default-v1' ||
                !ids.add(id) ||
                !names.add(nickname) ||
                created.isAfter(serverTime)) {
              throw const FormatException('Invalid identity record');
            }
            if (original) originals++;
            return ManagedIdentity(
              id: id,
              nickname: nickname,
              avatar: 'default-v1',
              isOriginal: original,
              createdAt: created,
              renameAvailableAt: item['renameAvailableAt'] == null
                  ? null
                  : _date(item, 'renameAvailableAt'),
            );
          })
          .toList(growable: false);
      final count = _integer(m, 'createdCount', identities.length, 2147483647);
      if (originals > 1 ||
          (count == 0) != identities.isEmpty ||
          (count < 3 && m['nextCreateAt'] != null)) {
        throw const FormatException('Invalid identity lifecycle metadata');
      }
      return IdentityDirectory(
        identities: List.unmodifiable(identities),
        createdCount: count,
        serverTime: serverTime,
        nextCreateAt: m['nextCreateAt'] == null
            ? null
            : _date(m, 'nextCreateAt'),
        sessionExpiresAt: _managementExpiry(r),
      );
    });
  }

  @override
  Future<IdentityChangeOutcome> changeIdentity({
    required String sessionToken,
    required String idempotencyKey,
    required IdentityOperation operation,
    String? identityId,
    String? nickname,
  }) async {
    if ((operation == IdentityOperation.create) != (identityId == null) ||
        (operation == IdentityOperation.delete) != (nickname == null) ||
        nickname != null &&
            (nickname.isEmpty || utf8.encode(nickname).length > 512)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
    if (identityId != null) {
      try {
        _identityId(identityId);
      } on FormatException {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'CLIENT_INPUT_INVALID',
        );
      }
    }
    final r = await _send(
      false,
      switch (operation) {
        IdentityOperation.create => 'POST',
        IdentityOperation.rename => 'PATCH',
        IdentityOperation.delete => 'DELETE',
      },
      identityId == null
          ? '/api/v1/identities'
          : '/api/v1/identities/$identityId',
      headers: {
        ..._capability('Bearer', sessionToken),
        'Idempotency-Key': _bytes(idempotencyKey, 16),
      },
      body: nickname == null ? null : {'nickname': nickname},
      expected: {200},
      allowNull: true,
    );
    final outcome = _model(() => _identityOutcome(r));
    if (!outcome.committed ||
        outcome.operation != operation ||
        identityId != null && outcome.identityId != identityId) {
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    }
    return outcome;
  }

  @override
  Future<IdentityChangeOutcome> identityChangeResult({
    required String sessionToken,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/identity-change-result',
      headers: {
        ..._capability('Bearer', sessionToken),
        'Idempotency-Key': _bytes(idempotencyKey, 16),
      },
      expected: {200},
      allowNull: true,
    );
    return _model(() => _identityOutcome(r));
  }

  static String _identityId(String id) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('Invalid identity ID');
    }
    return id;
  }

  IdentityChangeOutcome _identityOutcome(_Reply r) {
    final m = _record(
      r.body,
      {'state', 'operation', 'identityId', 'errorCode'},
      nullable: {'operation', 'identityId', 'errorCode'},
    );
    if (m['state'] == 'NOT_FOUND' &&
        m['operation'] == null &&
        m['identityId'] == null &&
        m['errorCode'] == null) {
      return IdentityChangeOutcome(
        committed: false,
        sessionExpiresAt: _managementExpiry(r),
      );
    }
    if (m['state'] != 'COMMITTED' && m['state'] != 'REJECTED') {
      throw const FormatException('Invalid identity outcome');
    }
    final operation = switch (m['operation']) {
      'CREATE' => IdentityOperation.create,
      'RENAME' => IdentityOperation.rename,
      'DELETE' => IdentityOperation.delete,
      _ => throw const FormatException('Invalid identity operation'),
    };
    if (m['state'] == 'REJECTED' &&
        m['identityId'] == null &&
        _identityRejections.contains(m['errorCode'])) {
      return IdentityChangeOutcome(
        committed: false,
        operation: operation,
        errorCode: m['errorCode'] as String,
        sessionExpiresAt: _managementExpiry(r),
      );
    }
    if (m['state'] != 'COMMITTED' || m['errorCode'] != null) {
      throw const FormatException('Invalid identity outcome metadata');
    }
    return IdentityChangeOutcome(
      committed: true,
      operation: operation,
      identityId: _identityId(_text(m, 'identityId')),
      sessionExpiresAt: _managementExpiry(r),
    );
  }

  static const _identityRejections = {
    'IDENTITY_INVALID_NAME',
    'IDENTITY_DUPLICATE_NAME',
    'IDENTITY_LIMIT',
    'IDENTITY_CREATE_COOLDOWN',
    'IDENTITY_RENAME_COOLDOWN',
    'IDENTITY_LAST_REQUIRED',
    'IDENTITY_NOT_FOUND',
  };

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  }) async {
    _usernameInput(username);
    _passwordInput(password);
    final response = await _send(
      false,
      'POST',
      '/api/v1/auth/sessions',
      body: {
        'username': username,
        'password': password,
        'installationId': _bytes(installationId, 16),
      },
      headers: _keyHeader(idempotencyKey),
      expected: {201},
    );
    return _model(() => _session(response));
  }

  @override
  Future<CurrentSession> currentSession(String sessionToken) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/auth/session',
      headers: _capability('Bearer', sessionToken),
      expected: {200},
    );
    return _model(() {
      final m = _record(r.body, {'accountId', 'username', 'expiresAt'});
      final expiry = _date(m, 'expiresAt');
      _sessionExpiry(r, expiry);
      return CurrentSession(
        accountId: _account(m),
        username: _username(m),
        expiresAt: expiry,
      );
    });
  }

  @override
  Future<DateTime> renewSession(String sessionToken) async {
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/session-renewals',
      headers: _capability('Bearer', sessionToken),
      expected: {200},
    );
    return _model(() {
      final expiry = _date(_record(r.body, {'expiresAt'}), 'expiresAt');
      _sessionExpiry(r, expiry);
      return expiry;
    });
  }

  @override
  Future<void> revokeSession(String revocationSecret) async {
    await _send(
      false,
      'POST',
      '/api/v1/auth/session-revocations',
      headers: _capability('SessionRevoke', revocationSecret),
      expected: {204},
    );
  }

  @override
  Future<OtpRequestAccepted> requestOtp({
    required String email,
    required String installationId,
    required String idempotencyKey,
  }) async {
    if (email.length > 254 ||
        !RegExp(r'^[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@hainanu\.edu\.cn$')
            .hasMatch(email)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
    final r = await _send(
      true,
      'POST',
      '/api/v1/eligibility/otp-requests',
      body: {'email': email},
      headers: _verifierHeaders(installationId, idempotencyKey),
      expected: {202},
    );
    return _model(() {
      final m = _record(r.body, {'flowId', 'retryAfterSeconds'});
      return OtpRequestAccepted(
        flowId: _encoded(m, 'flowId', 32),
        retryAfterSeconds: _integer(m, 'retryAfterSeconds', 0, 60),
      );
    });
  }

  @override
  Future<OtpRequestResult> otpRequestResult({
    required String installationId,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      true,
      'GET',
      '/api/v1/eligibility/otp-request-result',
      headers: {
        'V-Installation-ID': _bytes(installationId, 16),
        ..._capability('OtpRequestResult', idempotencyKey),
      },
      expected: {200, 202},
    );
    return _model(() {
      final m = _record(
        r.body,
        {'state', 'retryAfterSeconds'},
        optional: {'flowId'},
      );
      final state = _text(m, 'state');
      if (r.status == 202 && state == 'PENDING' && !m.containsKey('flowId')) {
        return OtpRequestResult(
          state: OtpRequestState.pending,
          retryAfterSeconds: _integer(m, 'retryAfterSeconds', 1, 60),
        );
      }
      if (r.status == 200 && state == 'ACCEPTED') {
        return OtpRequestResult(
          state: OtpRequestState.accepted,
          flowId: _encoded(m, 'flowId', 32),
          retryAfterSeconds: _integer(m, 'retryAfterSeconds', 0, 60),
        );
      }
      if (r.status == 200 && state == 'NOT_SENT' && !m.containsKey('flowId')) {
        return OtpRequestResult(
          state: OtpRequestState.notSent,
          retryAfterSeconds: _integer(m, 'retryAfterSeconds', 0, 60),
        );
      }
      throw const FormatException('Invalid operation state');
    });
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
    if (!RegExp(r'^\d{6}$').hasMatch(otp) ||
        AuthCrypto.slotId(_bytes(bootstrapPublicKey, 32)) !=
            _bytes(slotId, 32)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
    final r = await _send(
      true,
      'POST',
      '/api/v1/eligibility/otp-confirmations',
      body: {
        'flowId': _bytes(flowId, 32),
        'otp': otp,
        'slotId': slotId,
        'bootstrapPublicKey': bootstrapPublicKey,
        if (releaseReceipt != null)
          'releaseReceipt': _bytes(releaseReceipt, 120),
      },
      headers: _verifierHeaders(installationId, idempotencyKey),
      expected: {200, 202},
    );
    return _model(() {
      if (r.status == 200) {
        final m = _record(r.body, {'registrationTicket'});
        final wire = _encoded(m, 'registrationTicket', 156);
        final ticket = AuthCrypto.parseRegistrationTicket(wire);
        if (ticket.slotId != slotId ||
            ticket.bootstrapPublicKey != bootstrapPublicKey) {
          throw const FormatException('Ticket local binding mismatch');
        }
        return OtpConfirmation(
          state: OtpConfirmationState.ticketAvailable,
          registrationTicket: wire,
        );
      }
      final m = _record(r.body, {'state', 'retryAfterSeconds'});
      final state = _confirmationState(_text(m, 'state'));
      if (state != OtpConfirmationState.confirmationPending &&
          state != OtpConfirmationState.retirementPending) {
        throw const FormatException('Invalid confirmation state');
      }
      return OtpConfirmation(
        state: state,
        retryAfterSeconds: _integer(m, 'retryAfterSeconds', 1, 60),
      );
    });
  }

  @override
  Future<OtpConfirmationResult> otpConfirmationResult({
    required String flowId,
    required String installationId,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      true,
      'GET',
      '/api/v1/eligibility/otp-confirmation-result',
      headers: {
        'V-Installation-ID': _bytes(installationId, 16),
        'OTP-Flow-ID': _bytes(flowId, 32),
        ..._capability('OtpConfirmationResult', idempotencyKey),
      },
      expected: {200, 202},
    );
    return _model(() {
      final m = _record(r.body, {'state'}, optional: {'retryAfterSeconds'});
      final state = _confirmationState(_text(m, 'state'));
      final pending =
          state == OtpConfirmationState.pending ||
          state == OtpConfirmationState.confirmationPending ||
          state == OtpConfirmationState.retirementPending;
      if (pending != (r.status == 202) ||
          pending != m.containsKey('retryAfterSeconds')) {
        throw const FormatException('Invalid confirmation status');
      }
      return OtpConfirmationResult(
        state: state,
        retryAfterSeconds: pending
            ? _integer(m, 'retryAfterSeconds', 1, 60)
            : null,
      );
    });
  }

  @override
  Future<RegistrationIntent> createRegistrationIntent({
    required String registrationTicket,
    required String username,
    required String password,
    required String installationId,
  }) async {
    _usernameInput(username);
    _passwordInput(password);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/registration-intents',
      body: {
        'registrationTicket': _bytes(registrationTicket, 156),
        'username': username,
        'password': password,
        'installationId': _bytes(installationId, 16),
      },
      expected: {201},
    );
    return _model(() {
      final m = _record(r.body, {
        'intentId',
        'challenge',
        'expiresAt',
        'recoveryCode',
      });
      return RegistrationIntent(
        intentId: _encoded(m, 'intentId', 32),
        challenge: _encoded(m, 'challenge', 32),
        expiresAt: _date(m, 'expiresAt'),
        recoveryCode: _recoveryCode(m, 'recoveryCode'),
      );
    });
  }

  @override
  Future<AuthSession> commitRegistration({
    required String intentId,
    required String bootstrapSignature,
    required String recoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    _recoveryInput(recoveryCodeConfirmation);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/registrations',
      body: {
        'intentId': _bytes(intentId, 32),
        'bootstrapSignature': _bytes(bootstrapSignature, 64),
        'recoveryCodeConfirmation': recoveryCodeConfirmation,
      },
      headers: _keyHeader(idempotencyKey),
      expected: {201},
    );
    return _model(() => _session(r));
  }

  @override
  Future<PasswordResetIntent> createCodeResetIntent(String recoveryCode) async {
    _recoveryInput(recoveryCode);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/recovery-code-reset-intents',
      body: {'recoveryCode': recoveryCode},
      expected: {201},
    );
    return _model(() {
      final m = _record(r.body, {
        'resetIntentId',
        'expiresAt',
        'username',
        'newRecoveryCode',
      });
      return PasswordResetIntent(
        resetIntentId: _encoded(m, 'resetIntentId', 32),
        expiresAt: _date(m, 'expiresAt'),
        username: _username(m),
        newRecoveryCode: _recoveryCode(m, 'newRecoveryCode'),
      );
    });
  }

  @override
  Future<void> commitPasswordReset({
    required String resetIntentId,
    required String newPassword,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    _passwordInput(newPassword);
    _recoveryInput(newRecoveryCodeConfirmation);
    await _send(
      false,
      'POST',
      '/api/v1/auth/password-resets',
      body: {
        'resetIntentId': _bytes(resetIntentId, 32),
        'newPassword': newPassword,
        'newRecoveryCodeConfirmation': newRecoveryCodeConfirmation,
      },
      headers: _keyHeader(idempotencyKey),
      expected: {204},
    );
  }

  @override
  Future<PasswordResetResult> passwordResetResult({
    required String resetIntentId,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/auth/password-reset-result',
      headers: {
        'Reset-Intent-ID': _bytes(resetIntentId, 32),
        ..._capability('ResetResult', idempotencyKey),
      },
      expected: {200, 202},
    );
    return _model(() {
      final state = _text(_record(r.body, {'state'}), 'state');
      if (r.status == 202 && state == 'PENDING') {
        return PasswordResetResult.pending;
      }
      if (r.status == 200 && state == 'COMMITTED') {
        return PasswordResetResult.committed;
      }
      if (r.status == 200 && state == 'NOT_COMMITTED') {
        return PasswordResetResult.notCommitted;
      }
      throw const FormatException('Invalid reset result');
    });
  }

  @override
  Future<ClosureAccepted> requestClosure({
    required String sessionToken,
    required String password,
    required String closureId,
    required String statusDigest,
  }) async {
    _passwordInput(password);
    final r = await _send(
      false,
      'POST',
      '/api/v1/account-closures',
      body: {
        'password': password,
        'closureId': _bytes(closureId, 32),
        'statusDigest': _bytes(statusDigest, 32),
      },
      headers: _capability('Bearer', sessionToken),
      expected: {202},
    );
    return _model(() {
      final m = _record(r.body, {'closureId', 'dueAt'});
      if (_encoded(m, 'closureId', 32) != closureId) {
        throw const FormatException('Closure binding mismatch');
      }
      return ClosureAccepted(closureId: closureId, dueAt: _date(m, 'dueAt'));
    });
  }

  @override
  Future<ClosureStatus> closureStatus({
    required String closureId,
    required String statusSecret,
  }) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/account-closures/${_bytes(closureId, 32)}',
      headers: _capability('ClosureStatus', statusSecret),
      expected: {200},
    );
    return _model(() {
      final m = _record(
        r.body,
        {'state'},
        optional: {'dueAt', 'releaseReceipt'},
      );
      switch (_text(m, 'state')) {
        case 'PENDING':
        case 'FINALIZING':
          if (m.containsKey('releaseReceipt')) {
            throw const FormatException('Invalid closure fields');
          }
          return ClosureStatus(
            state: m['state'] == 'PENDING'
                ? ClosureState.pending
                : ClosureState.finalizing,
            dueAt: _date(m, 'dueAt'),
          );
        case 'CANCELLED':
          if (m.length != 1) {
            throw const FormatException('Invalid closure fields');
          }
          return const ClosureStatus(state: ClosureState.cancelled);
        case 'CLOSED_RELEASE_PENDING':
        case 'RELEASED':
          if (m.containsKey('dueAt')) {
            throw const FormatException('Invalid closure fields');
          }
          final receipt = m.containsKey('releaseReceipt')
              ? _encoded(m, 'releaseReceipt', 120)
              : null;
          if (m['state'] == 'RELEASED' && receipt == null) {
            throw const FormatException('Missing release receipt');
          }
          return ClosureStatus(
            state: m['state'] == 'RELEASED'
                ? ClosureState.released
                : ClosureState.closedReleasePending,
            releaseReceipt: receipt,
          );
        default:
          throw const FormatException('Invalid closure state');
      }
    });
  }

  @override
  Future<DeviceDirectory> devices(String sessionToken) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/auth/devices',
      headers: _capability('Bearer', sessionToken),
      expected: {200},
    );
    return _model(() {
      final m = _record(r.body, {'current'}, optional: {'lastReplaced'});
      final current = _record(m['current'], {'role', 'signedInAt'});
      if (current['role'] != 'CURRENT') {
        throw const FormatException('Invalid current device role');
      }
      DateTime? signedIn, replaced;
      if (m.containsKey('lastReplaced')) {
        final recent = _record(m['lastReplaced'], {
          'role',
          'signedInAt',
          'replacedAt',
        });
        if (recent['role'] != 'REPLACED') {
          throw const FormatException('Invalid replaced device role');
        }
        signedIn = _date(recent, 'signedInAt');
        replaced = _date(recent, 'replacedAt');
        if (replaced.isBefore(signedIn)) {
          throw const FormatException('Invalid replaced device times');
        }
      }
      return DeviceDirectory(
        currentSignedInAt: _date(current, 'signedInAt'),
        lastReplacedSignedInAt: signedIn,
        lastReplacedAt: replaced,
        sessionExpiresAt: _managementExpiry(r),
      );
    });
  }

  @override
  Future<RecoveryCredentialSummary> recoveryCredentials(
    String sessionToken,
  ) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/auth/recovery-credentials',
      headers: _capability('Bearer', sessionToken),
      expected: {200},
    );
    return _model(() {
      final m = _record(r.body, {'recoveryCodeAvailable', 'passkeys'});
      if (m['recoveryCodeAvailable'] != true ||
          m['passkeys'] is! List ||
          (m['passkeys'] as List).length > 10) {
        throw const FormatException('Invalid recovery credential list');
      }
      final ids = <String>{};
      final passkeys = (m['passkeys'] as List)
          .map((value) {
            final p = _record(value, {
              'credentialId',
              'createdAt',
              'backupEligible',
              'backedUp',
            });
            final id = _variableBytes(p, 'credentialId', 1023);
            if (!ids.add(id) ||
                p['backupEligible'] is! bool ||
                p['backedUp'] is! bool ||
                (p['backedUp'] == true && p['backupEligible'] == false)) {
              throw const FormatException('Invalid recovery credential');
            }
            return PasskeySummary(
              credentialId: id,
              createdAt: _date(p, 'createdAt'),
              backupEligible: p['backupEligible'] as bool,
              backedUp: p['backedUp'] as bool,
            );
          })
          .toList(growable: false);
      return RecoveryCredentialSummary(
        passkeys: List.unmodifiable(passkeys),
        sessionExpiresAt: _managementExpiry(r),
      );
    });
  }

  @override
  Future<RecoveryCodeRotation> createRecoveryCodeRotation({
    required String sessionToken,
    required String password,
  }) async {
    _passwordInput(password);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/recovery-code-rotations',
      body: {'password': password},
      headers: _capability('Bearer', sessionToken),
      expected: {201},
    );
    return _model(() {
      final m = _record(r.body, {
        'rotationIntentId',
        'expiresAt',
        'newRecoveryCode',
      });
      return RecoveryCodeRotation(
        rotationIntentId: _encoded(m, 'rotationIntentId', 32),
        expiresAt: _date(m, 'expiresAt'),
        newRecoveryCode: _recoveryCode(m, 'newRecoveryCode'),
        sessionExpiresAt: _managementExpiry(r),
      );
    });
  }

  @override
  Future<DateTime> confirmRecoveryCodeRotation({
    required String sessionToken,
    required String rotationIntentId,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    _recoveryInput(newRecoveryCodeConfirmation);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/recovery-code-rotations/${_bytes(rotationIntentId, 32)}/confirmations',
      body: {'newRecoveryCodeConfirmation': newRecoveryCodeConfirmation},
      headers: {
        ..._capability('Bearer', sessionToken),
        ..._keyHeader(idempotencyKey),
      },
      expected: {204},
    );
    return _model(() => _managementExpiry(r));
  }

  @override
  Future<PasskeyRemovalIntent> createPasskeyRemovalIntent({
    required String sessionToken,
    required String credentialId,
    required String password,
  }) async {
    _passwordInput(password);
    _bytes(credentialId, null, maxBytes: 1023);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/passkey-removal-intents',
      body: {'credentialId': credentialId, 'password': password},
      headers: _capability('Bearer', sessionToken),
      expected: {201},
    );
    return _model(() {
      final m = _record(r.body, {'removalIntentId', 'expiresAt'});
      return PasskeyRemovalIntent(
        removalIntentId: _encoded(m, 'removalIntentId', 32),
        expiresAt: _date(m, 'expiresAt'),
        sessionExpiresAt: _managementExpiry(r),
      );
    });
  }

  @override
  Future<DateTime> removePasskey({
    required String sessionToken,
    required String credentialId,
    required String removalIntentId,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      false,
      'DELETE',
      '/api/v1/auth/passkeys/${_bytes(credentialId, null, maxBytes: 1023)}',
      headers: {
        ..._capability('Bearer', sessionToken),
        ..._keyHeader(idempotencyKey),
        'Credential-Change-ID': _bytes(removalIntentId, 32),
      },
      expected: {204},
    );
    return _model(() => _managementExpiry(r));
  }

  @override
  Future<PasskeyOptions> createPasskeyCreationOptions({
    required String sessionToken,
    required String password,
  }) async {
    _passwordInput(password);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/passkey-options',
      headers: _capability('Bearer', sessionToken),
      body: {'password': password},
      expected: {200},
    );
    return _model(() => _passkeyOptions(r, creation: true));
  }

  @override
  Future<DateTime> registerPasskey({
    required String sessionToken,
    required String challengeId,
    required Map<String, dynamic> attestation,
    required String idempotencyKey,
  }) async {
    _nativeCredential(attestation, creation: true);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/passkeys',
      headers: {
        ..._capability('Bearer', sessionToken),
        ..._keyHeader(idempotencyKey),
      },
      body: {
        'challengeId': _bytes(challengeId, 32),
        'webauthnAttestation': attestation,
      },
      maxRequestBytes: 32768,
      expected: {204},
    );
    return _model(() => _managementExpiry(r));
  }

  @override
  Future<CredentialChangeOutcome> credentialChangeResult({
    required String sessionToken,
    required String changeId,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      false,
      'GET',
      '/api/v1/auth/credential-change-result',
      headers: {
        ..._capability('Bearer', sessionToken),
        ..._keyHeader(idempotencyKey),
        'Credential-Change-ID': _bytes(changeId, 32),
      },
      expected: {200},
    );
    return _model(() {
      final m = _record(r.body, {'state'});
      final state = switch (_text(m, 'state')) {
        'PENDING' => CredentialChangeState.pending,
        'COMMITTED' => CredentialChangeState.committed,
        'NOT_COMMITTED' => CredentialChangeState.notCommitted,
        _ => throw const FormatException('Invalid credential change state'),
      };
      return CredentialChangeOutcome(
        state: state,
        sessionExpiresAt: _managementExpiry(r),
      );
    });
  }

  @override
  Future<PasskeyOptions> createPasskeyResetOptions() async {
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/passkey-reset-options',
      body: {},
      expected: {200},
    );
    return _model(() => _passkeyOptions(r, creation: false));
  }

  @override
  Future<PasswordResetIntent> createPasskeyResetIntent({
    required String challengeId,
    required Map<String, dynamic> assertion,
  }) async {
    _nativeCredential(assertion, creation: false);
    final r = await _send(
      false,
      'POST',
      '/api/v1/auth/passkey-reset-intents',
      body: {
        'challengeId': _bytes(challengeId, 32),
        'webauthnAssertion': assertion,
      },
      maxRequestBytes: 32768,
      expected: {201},
    );
    return _model(() {
      final m = _record(r.body, {
        'resetIntentId',
        'expiresAt',
        'username',
        'newRecoveryCode',
      });
      return PasswordResetIntent(
        resetIntentId: _encoded(m, 'resetIntentId', 32),
        expiresAt: _date(m, 'expiresAt'),
        username: _username(m),
        newRecoveryCode: _recoveryCode(m, 'newRecoveryCode'),
      );
    });
  }

  Map<String, String> _keyHeader(String key) => {
    'Idempotency-Key': _bytes(key, 32),
  };
  Map<String, String> _capability(String scheme, String value) => {
    'Authorization': '$scheme ${_bytes(value, 32)}',
  };
  Map<String, String> _verifierHeaders(String installation, String key) => {
    'V-Installation-ID': _bytes(installation, 16),
    ..._keyHeader(key),
  };

  Future<_Reply> _send(
    bool verifier,
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, String> headers = const {},
    int maxRequestBytes = 8192,
    bool allowNull = false,
    required Set<int> expected,
  }) async {
    HttpClientRequest? active;
    int? responseStatus;
    var expired = false;
    try {
      return await (() async {
        final origin = verifier ? verifierBaseUri : communityBaseUri;
        final request = await _client.openUrl(method, origin.resolve(path));
        active = request;
        if (expired) {
          request.abort();
          throw const AuthFailure(kind: AuthFailureKind.timeout);
        }
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.persistentConnection = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
        if (body != null) {
          final bytes = utf8.encode(jsonEncode(body));
          if (bytes.length > maxRequestBytes) {
            throw const AuthFailure(
              kind: AuthFailureKind.rejected,
              code: 'CLIENT_INPUT_INVALID',
            );
          }
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json; charset=utf-8',
          );
          request.contentLength = bytes.length;
          request.add(bytes);
        }
        final response = await request.close();
        responseStatus = response.statusCode;
        final bytes = <int>[];
        if (response.contentLength > maxResponseBytes) {
          throw const FormatException('Oversized response');
        }
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const FormatException('Oversized response');
          }
          bytes.addAll(chunk);
        }
        final status = response.statusCode;
        final requestId = response.headers.value('X-Request-ID');
        if (requestId == null) {
          throw const FormatException('Missing authentication request ID');
        }
        AuthCrypto.decode(requestId, bytes: 16);
        final noStore = response.headers.value(HttpHeaders.cacheControlHeader);
        if (noStore == null ||
            !noStore
                .split(',')
                .any((part) => part.trim().toLowerCase() == 'no-store')) {
          throw const FormatException('Missing authentication cache policy');
        }
        Object? payload;
        if (status == 204) {
          if (bytes.isNotEmpty) {
            throw const FormatException('Unexpected response body');
          }
        } else {
          if (response.headers.contentType?.mimeType != 'application/json' ||
              (response.headers.contentType?.charset != null &&
                  response.headers.contentType?.charset?.toLowerCase() !=
                      'utf-8')) {
            throw const FormatException('Invalid authentication response type');
          }
          payload = _StrictJson(
            utf8.decode(bytes, allowMalformed: false),
            allowNull: allowNull,
          ).decode();
        }
        if (!expected.contains(status)) {
          throw _httpFailure(status, payload);
        }
        return _Reply(
          status,
          payload,
          response.headers.value('Session-Expires-At'),
        );
      })().timeout(timeout);
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      expired = true;
      active?.abort();
      throw const AuthFailure(kind: AuthFailureKind.timeout);
    } on FormatException {
      active?.abort();
      if (responseStatus == 401 || responseStatus == 503) {
        throw AuthFailure(
          kind: responseStatus == 401
              ? AuthFailureKind.unauthorized
              : AuthFailureKind.unavailable,
          statusCode: responseStatus,
        );
      }
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    } on SocketException {
      active?.abort();
      throw const AuthFailure(kind: AuthFailureKind.unknownOutcome);
    } on HttpException {
      active?.abort();
      throw const AuthFailure(kind: AuthFailureKind.unknownOutcome);
    } on HandshakeException {
      active?.abort();
      throw const AuthFailure(kind: AuthFailureKind.unknownOutcome);
    } on TlsException {
      active?.abort();
      throw const AuthFailure(kind: AuthFailureKind.unknownOutcome);
    }
  }

  AuthFailure _httpFailure(int status, Object? payload) {
    String? code;
    int? retry;
    var valid = false;
    try {
      final m = _record(payload, {'error', 'requestId'});
      _encoded(m, 'requestId', 16);
      final e = _record(m['error'], {'code', 'message'}, optional: {'details'});
      final value = _text(e, 'code');
      if (!_errorCodes.contains(value)) {
        throw const FormatException('Invalid error code');
      }
      _text(e, 'message', maxLength: 256);
      code = value;
      if (e.containsKey('details')) {
        final details = _record(
          e['details'],
          {},
          optional: {'retryAfterSeconds'},
        );
        if (details.containsKey('retryAfterSeconds')) {
          retry = _integer(details, 'retryAfterSeconds', 1, 999999);
        }
      }
      valid = true;
    } on FormatException {
      // A 401 still invalidates a bearer; malformed 503 remains unavailable.
    }
    if (!valid && status != 401 && status != 503) {
      return AuthFailure(
        kind: AuthFailureKind.invalidResponse,
        statusCode: status,
      );
    }
    return AuthFailure(
      kind: status == 401
          ? AuthFailureKind.unauthorized
          : status == 503
          ? AuthFailureKind.unavailable
          : status >= 500 || status >= 300 && status < 400
          ? AuthFailureKind.unknownOutcome
          : AuthFailureKind.rejected,
      statusCode: status,
      code: code,
      retryAfterSeconds: retry,
    );
  }

  static const _errorCodes = {
    'REQUEST_INVALID',
    'EMAIL_INVALID',
    'AUTHENTICATION_FAILED',
    'IDEMPOTENCY_KEY_REUSED',
    'IDEMPOTENCY_CONFLICT',
    'OTP_INVALID',
    'OTP_EXPIRED',
    'OTP_REPLACED',
    'OTP_FLOW_INVALID',
    'BOOTSTRAP_KEY_INVALID',
    'SLOT_BINDING_INVALID',
    'ELIGIBILITY_RESERVED',
    'RELEASE_RECEIPT_INVALID',
    'REVERIFY_REQUIRED',
    'RELEASE_RECONCILIATION_REQUIRED',
    'RETIREMENT_RECEIPT_INVALID',
    'RETIREMENT_RECONCILIATION_REQUIRED',
    'RATE_LIMITED',
    'RESULT_EXPIRED',
    'SERVICE_UNAVAILABLE',
    'MALFORMED_REQUEST',
    'SESSION_INVALID',
    'session_replaced',
    'ACCOUNT_UNAVAILABLE',
    'AUTHORIZATION_FAILED',
    'RESOURCE_NOT_FOUND',
    'OPERATION_PENDING',
    'INTENT_INVALID',
    'INTENT_EXPIRED',
    'CHALLENGE_INVALID',
    'CHALLENGE_EXPIRED',
    'CREDENTIAL_STATE_CHANGED',
    'CREDENTIAL_LIMIT_REACHED',
    'CREDENTIAL_ALREADY_REGISTERED',
    'RECOVERY_CODE_CONFIRMATION_FAILED',
    'PASSWORD_POLICY_FAILED',
    'REGISTRATION_TICKET_INVALID',
    'REGISTRATION_TICKET_EXPIRED',
    'REGISTRATION_TICKET_NOT_YET_VALID',
    'SLOT_UNAVAILABLE',
    'USERNAME_UNAVAILABLE',
    'REGISTRATION_COMMITTED_LOGIN_REQUIRED',
    'SESSION_CREATED_RETRY_LOGIN',
    'SLOT_NOT_RETIRABLE',
    'CLOSURE_STATUS_UNAVAILABLE',
    'PAYLOAD_TOO_LARGE',
    'UNSUPPORTED_MEDIA_TYPE',
    'IDENTITY_INVALID_NAME',
    'IDENTITY_DUPLICATE_NAME',
    'IDENTITY_LIMIT',
    'IDENTITY_CREATE_COOLDOWN',
    'IDENTITY_RENAME_COOLDOWN',
    'IDENTITY_LAST_REQUIRED',
    'IDENTITY_NOT_FOUND',
    'IDENTITY_CHANGE_CONFLICT',
  };

  T _model<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    }
  }

  AuthSession _session(_Reply response) {
    final m = _record(response.body, {
      'accountId',
      'sessionToken',
      'expiresAt',
    });
    final expiry = _date(m, 'expiresAt');
    _sessionExpiry(response, expiry);
    return AuthSession(
      accountId: _account(m),
      sessionToken: _encoded(m, 'sessionToken', 32),
      expiresAt: expiry,
    );
  }

  void _sessionExpiry(_Reply r, DateTime expiry) {
    if (r.sessionExpiry == null || _parseDate(r.sessionExpiry!) != expiry) {
      throw const FormatException('Session expiry header mismatch');
    }
  }

  DateTime _managementExpiry(_Reply r) {
    final value = r.sessionExpiry;
    if (value == null) {
      throw const FormatException('Missing session expiry metadata');
    }
    return _parseDate(value);
  }

  PasskeyOptions _passkeyOptions(_Reply r, {required bool creation}) {
    final m = _record(r.body, {'challengeId', 'expiresAt', 'publicKey'});
    final options = _record(
      m['publicKey'],
      creation
          ? {
              'challenge',
              'rp',
              'user',
              'pubKeyCredParams',
              'timeout',
              'excludeCredentials',
              'authenticatorSelection',
              'attestation',
            }
          : {'challenge', 'rpId', 'timeout', 'userVerification'},
    );
    _encoded(options, 'challenge', 32);
    if (options['timeout'] != 60000) {
      throw const FormatException('Invalid Passkey timeout');
    }
    if (creation) {
      final rp = _record(options['rp'], {'id', 'name'});
      _passkeyRp(_text(rp, 'id', maxLength: 253));
      final user = _record(options['user'], {'id', 'name', 'displayName'});
      final userId = _encoded(user, 'id', 32);
      final params = options['pubKeyCredParams'];
      if (rp['name'] != 'Hnuhole' ||
          user['name'] != userId ||
          user['displayName'] != 'Hnuhole account' ||
          params is! List ||
          params.length != 1) {
        throw const FormatException('Invalid Passkey account options');
      }
      final algorithm = _record(params.single, {'type', 'alg'});
      final selection = _record(options['authenticatorSelection'], {
        'residentKey',
        'requireResidentKey',
        'userVerification',
      });
      if (algorithm['type'] != 'public-key' ||
          algorithm['alg'] != -7 ||
          selection['residentKey'] != 'required' ||
          selection['requireResidentKey'] != true ||
          selection['userVerification'] != 'required' ||
          options['attestation'] != 'none') {
        throw const FormatException('Invalid Passkey security policy');
      }
      final exclusions = options['excludeCredentials'];
      if (exclusions is! List || exclusions.length > 10) {
        throw const FormatException('Invalid Passkey exclusion list');
      }
      final ids = <String>{};
      for (final value in exclusions) {
        final descriptor = _record(value, {'type', 'id'});
        if (descriptor['type'] != 'public-key' ||
            !ids.add(_variableBytes(descriptor, 'id', 1023))) {
          throw const FormatException('Invalid Passkey exclusion descriptor');
        }
      }
    } else {
      _passkeyRp(_text(options, 'rpId', maxLength: 253));
      if (options['userVerification'] != 'required') {
        throw const FormatException('Passkey verification is required');
      }
    }
    return PasskeyOptions(
      challengeId: _encoded(m, 'challengeId', 32),
      expiresAt: _date(m, 'expiresAt'),
      publicKey: _freezeJsonMap(options),
      sessionExpiresAt: creation ? _managementExpiry(r) : null,
    );
  }

  void _passkeyRp(String rp) {
    if (passkeyRpId != null) {
      if (rp != passkeyRpId) {
        throw const FormatException(
          'Passkey RP differs from the configured authority',
        );
      }
      return;
    }
    final host = communityBaseUri.host.toLowerCase();
    if (rp != rp.toLowerCase() ||
        !RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(rp) ||
        rp.contains('..') ||
        (host != rp && !host.endsWith('.$rp'))) {
      throw const FormatException('Passkey RP is outside the community origin');
    }
  }

  static Map<String, dynamic> _freezeJsonMap(Map<String, Object?> value) =>
      Map<String, dynamic>.unmodifiable(
        value.map(
          (key, item) => MapEntry(
            key,
            item is Map<String, Object?>
                ? _freezeJsonMap(item)
                : item is List
                ? List<Object?>.unmodifiable(
                    item.map(
                      (entry) => entry is Map<String, Object?>
                          ? _freezeJsonMap(entry)
                          : entry,
                    ),
                  )
                : item,
          ),
        ),
      );

  static void _nativeCredential(
    Map<String, dynamic> credential, {
    required bool creation,
  }) {
    try {
      final m = _record(credential, {
        'id',
        'rawId',
        'type',
        'response',
        'clientExtensionResults',
      });
      final id = _variableBytes(m, 'id', 1023);
      if (m['rawId'] != id || m['type'] != 'public-key') {
        throw const FormatException('Invalid native credential identity');
      }
      _record(m['clientExtensionResults'], {});
      final response = _record(
        m['response'],
        creation
            ? {'clientDataJSON', 'attestationObject'}
            : {
                'clientDataJSON',
                'authenticatorData',
                'signature',
                'userHandle',
              },
        optional: creation ? {'transports'} : {},
      );
      _variableBytes(response, 'clientDataJSON', 3072);
      if (creation) {
        _variableBytes(response, 'attestationObject', 4096);
        if (response.containsKey('transports')) {
          final transports = response['transports'];
          if (transports is! List ||
              transports.length > 5 ||
              transports.toSet().length != transports.length ||
              transports.any(
                (value) => !{
                  'usb',
                  'nfc',
                  'ble',
                  'internal',
                  'hybrid',
                }.contains(value),
              )) {
            throw const FormatException('Invalid native transports');
          }
        }
      } else {
        final authData = AuthCrypto.decode(
          _variableBytes(response, 'authenticatorData', 2048),
        );
        final signature = AuthCrypto.decode(
          _variableBytes(response, 'signature', 1024),
        );
        if (authData.length < 37 || signature.length < 8) {
          throw const FormatException('Invalid native assertion length');
        }
        _encoded(response, 'userHandle', 32);
      }
    } on FormatException {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }

  static Map<String, Object?> _record(
    Object? raw,
    Set<String> required, {
    Set<String> optional = const {},
    Set<String> nullable = const {},
  }) {
    if (raw is! Map<String, Object?> ||
        !required.every(raw.containsKey) ||
        raw.keys.any(
          (key) => !required.contains(key) && !optional.contains(key),
        ) ||
        raw.entries.any(
          (entry) => entry.value == null && !nullable.contains(entry.key),
        )) {
      throw const FormatException('Invalid response object');
    }
    return raw;
  }

  static String _text(
    Map<String, Object?> m,
    String key, {
    int maxLength = 2048,
  }) {
    final v = m[key];
    if (v is! String || v.isEmpty || v.length > maxLength) {
      throw const FormatException('Invalid response string');
    }
    return v;
  }

  static int _integer(Map<String, Object?> m, String key, int min, int max) {
    final v = m[key];
    if (v is! int || v < min || v > max) {
      throw const FormatException('Invalid response integer');
    }
    return v;
  }

  static String _encoded(Map<String, Object?> m, String key, int bytes) {
    final v = _text(m, key);
    AuthCrypto.decode(v, bytes: bytes);
    return v;
  }

  static String _variableBytes(
    Map<String, Object?> m,
    String key,
    int maxBytes,
  ) {
    // Protocol fields have byte limits; base64url text can legitimately exceed
    // the ordinary response-string limit. Keep the exact byte bound below.
    final v = _text(m, key, maxLength: (maxBytes * 4 + 2) ~/ 3);
    AuthCrypto.decode(v, maxBytes: maxBytes);
    return v;
  }

  static String _account(Map<String, Object?> m) {
    final v = _text(m, 'accountId');
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(v)) {
      throw const FormatException('Invalid account ID');
    }
    return v;
  }

  static String _username(Map<String, Object?> m) {
    final v = _text(m, 'username');
    if (!RegExp(r'^[a-z][a-z0-9_]{5,23}$').hasMatch(v)) {
      throw const FormatException('Invalid username');
    }
    return v;
  }

  static String _recoveryCode(Map<String, Object?> m, String key) {
    final v = _text(m, key);
    if (!RegExp(r'^[A-Z2-7]{25}[AEIMQUY4]$').hasMatch(v)) {
      throw const FormatException('Invalid recovery code');
    }
    return v;
  }

  static DateTime _date(Map<String, Object?> m, String key) =>
      _parseDate(_text(m, key));
  static DateTime _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$')
        .hasMatch(value)) {
      throw const FormatException('Invalid UTC date');
    }
    final parsed = DateTime.parse(value);
    if (parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
      throw const FormatException('Invalid UTC calendar date');
    }
    return parsed;
  }

  static OtpConfirmationState _confirmationState(String state) =>
      switch (state) {
        'TICKET_AVAILABLE' => OtpConfirmationState.ticketAvailable,
        'CONFIRMATION_PENDING' => OtpConfirmationState.confirmationPending,
        'RETIREMENT_PENDING' => OtpConfirmationState.retirementPending,
        'PENDING' => OtpConfirmationState.pending,
        'REVERIFY_REQUIRED' => OtpConfirmationState.reverifyRequired,
        'NOT_COMMITTED' => OtpConfirmationState.notCommitted,
        _ => throw const FormatException('Invalid confirmation state'),
      };
  static String _bytes(String value, int? count, {int? maxBytes}) {
    try {
      AuthCrypto.decode(value, bytes: count, maxBytes: maxBytes);
      return value;
    } on FormatException {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }

  static void _usernameInput(String value) {
    if (!RegExp(r'^[a-z][a-z0-9_]{5,23}$').hasMatch(value)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }

  static void _passwordInput(String value) {
    if (value.isEmpty ||
        value.runes.length > 512 ||
        utf8.encode(value).length > 2048) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }

  static void _recoveryInput(String value) {
    if (value.length < 26 ||
        value.length > 64 ||
        !RegExp(r'^[A-Za-z2-7 -]+$').hasMatch(value)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }
}

class _Reply {
  const _Reply(this.status, this.body, this.sessionExpiry);
  final int status;
  final Object? body;
  final String? sessionExpiry;
}

/// jsonDecode alone silently overwrites duplicate object keys. This bounded
/// reader rejects them before typed response validation and consumes all input.
class _StrictJson {
  _StrictJson(this.input, {this.allowNull = false});
  final bool allowNull;
  final String input;
  int at = 0;
  Object? decode() {
    final value = _value(0);
    _space();
    if (at != input.length) throw const FormatException('Trailing JSON data');
    return value;
  }

  void _space() {
    while (at < input.length && ' \t\r\n'.contains(input[at])) {
      at++;
    }
  }

  Object? _value(int depth) {
    if (depth > 16) throw const FormatException('JSON nesting too deep');
    _space();
    if (at >= input.length) throw const FormatException('Missing JSON value');
    final c = input[at];
    if (c == '{') {
      at++;
      _space();
      final result = <String, Object?>{};
      if (_consume('}')) return result;
      while (true) {
        _space();
        final key = _string();
        _space();
        if (!_consume(':') || result.containsKey(key)) {
          throw const FormatException('Invalid JSON key');
        }
        result[key] = _value(depth + 1);
        _space();
        if (_consume('}')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON object');
      }
    }
    if (c == '[') {
      at++;
      _space();
      final result = <Object?>[];
      if (_consume(']')) return result;
      while (true) {
        if (result.length >= 100) {
          throw const FormatException('JSON list too large');
        }
        result.add(_value(depth + 1));
        _space();
        if (_consume(']')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON array');
      }
    }
    if (c == '"') return _string();
    if (input.startsWith('true', at)) {
      at += 4;
      return true;
    }
    if (input.startsWith('false', at)) {
      at += 5;
      return false;
    }
    if (input.startsWith('null', at)) {
      if (allowNull) {
        at += 4;
        return null;
      }
      throw const FormatException('Null JSON value');
    }
    final match = RegExp(r'-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?')
        .matchAsPrefix(input, at);
    if (match == null) throw const FormatException('Invalid JSON value');
    at = match.end;
    final number = num.tryParse(match.group(0)!);
    if (number == null || !number.isFinite) {
      throw const FormatException('Invalid JSON number');
    }
    return number;
  }

  String _string() {
    if (at >= input.length || input[at] != '"') {
      throw const FormatException('Missing JSON string');
    }
    final start = at++;
    while (at < input.length) {
      final c = input[at++];
      if (c == '"') return jsonDecode(input.substring(start, at)) as String;
      if (c == '\\') {
        if (at >= input.length) {
          throw const FormatException('Incomplete JSON escape');
        }
        at++;
      }
    }
    throw const FormatException('Incomplete JSON string');
  }

  bool _consume(String value) {
    if (at < input.length && input[at] == value) {
      at++;
      return true;
    }
    return false;
  }
}
