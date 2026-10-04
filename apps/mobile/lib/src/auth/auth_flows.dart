import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

import 'auth_api.dart';
import 'auth_crypto.dart';
import 'auth_models.dart';
import 'auth_store.dart';
import 'credential_management_api.dart';
import 'auth_state_codec.dart';

enum AuthFlowStatus {
  idle,
  otpRequested,
  otpRequestUnknown,
  otpConfirmationPending,
  eligibilityReady,
  registrationCodeShown,
  registrationCodeConfirmation,
  registrationUnknown,
  registrationComplete,
  resetCodeShown,
  resetCodeConfirmation,
  resetUnknown,
  resetCommitted,
  resetNotCommitted,
  closureUnknown,
  closurePending,
  closureCancelled,
  closureFinalizing,
  closureClosedReleasePending,
  closureReleased,
  failure,
}

/// Owns credential workflows, never ordinary password login. A received OTP or
/// reset result cannot become community authority. Secrets needed for retry are
/// kept only in the atomic system-secure store; displayed codes/passwords are
/// ephemeral and never serialized.
class AuthFlows extends ChangeNotifier {
  AuthFlows({
    required this._api,
    required this._store,
    required this._acceptRegistrationSession,
    required this._clearCommunityAccess,
    this._passkeyApi,
    this._passkey,
    int Function()? sessionAuthorityVersion,
    this._sessionAuthority,
    DateTime Function()? clock,
  }) : _sessionAuthorityVersion = sessionAuthorityVersion ?? (() => 0),
       _clock = clock ?? DateTime.now {
    _sessionAuthority?.addListener(_sessionAuthorityChanged);
  }

  final AuthApi _api;
  final AuthStore _store;
  final PasskeyRecoveryApi? _passkeyApi;
  final PasskeyClient? _passkey;
  bool get supportsPasskeyRecovery => _passkeyApi != null && _passkey != null;
  bool _passkeyRecoveryActive = false;
  int? _passkeyAuthorityVersion, _nativeRecoveryEpoch;
  final int Function() _sessionAuthorityVersion;
  final Listenable? _sessionAuthority;
  void _sessionAuthorityChanged() {
    if (_passkeyRecoveryActive && _passkeyAuthorityVersion != _sessionAuthorityVersion()) {
      cancelPasskeyRecovery();
    }
  }
  final Future<void> Function(AuthSession) _acceptRegistrationSession;
  final void Function() _clearCommunityAccess;
  final DateTime Function() _clock;
  AuthFlowStatus _status = AuthFlowStatus.idle;
  AuthFailure? _error;
  String? _errorMessage;
  String? _recoveryCode;
  String? _username;
  RegistrationIntent? _registrationIntent;
  PasswordResetIntent? _resetIntent;
  ClosureStatus? _closureStatus;
  DateTime? _otpWaitUntil;
  String? _originalOtp;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;

  AuthFlowStatus get status => _status;
  AuthFailure? get error => _error;
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;
  String? get recoveryCode => _recoveryCode;
  String? get username => _username;
  String? get resetUsername => _username;
  DateTime? get otpWaitUntil => _otpWaitUntil;
  ClosureStatus? get closureStatus => _closureStatus;

  /// Reconstitutes only pending authority checks, never codes or a session.
  Future<void> restorePending() => _run((epoch) async {
    final state = await _store.read();
    if (!_current(epoch)) {
      return;
    }
    _validateState(state);
    final reset = state.pendingReset;
    final closure = state.pendingClosure;
    if (reset != null) {
      _status = _resetStatus(reset['state'] as String);
      return;
    }
    if (closure != null) {
      _restoreClosure(closure);
      return;
    }
    final registration = state.registration;
    if (registration == null) {
      return;
    }
    final request = _map(registration['request']);
    if (request != null) {
      _otpWaitUntil = DateTime.parse(request['waitUntil'] as String);
    }
    if (registration['commit'] != null) {
      _status = AuthFlowStatus.registrationUnknown;
    } else if (registration['ticket'] != null) {
      _status = AuthFlowStatus.eligibilityReady;
    } else if (registration['confirmation'] != null) {
      _status = AuthFlowStatus.otpConfirmationPending;
    } else if (request?['flowId'] != null) {
      _status = AuthFlowStatus.otpRequested;
    } else if (request != null) {
      _status = AuthFlowStatus.otpRequestUnknown;
    }
  });

  Future<void> requestOtp(String email) => _run((epoch) async {
    if (!RegExp(r'^[^\s@]+@hainanu\.edu\.cn$').hasMatch(email)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'EMAIL_INVALID',
      );
    }
    var state = await _store.read();
    _validateState(state);
    _requireNoOtherPending(state);
    var registration = state.registration;
    if (registration == null) {
      final bootstrap = await AuthCrypto.newBootstrapKey();
      if (!_current(epoch)) {
        return;
      }
      state = await _store.update((latest) {
        _requireNoOtherPending(latest);
        if (latest.registration != null) {
          return latest;
        }
        return latest.copyWith(
          cInstallationId:
              latest.cInstallationId ?? AuthCrypto.randomEncoded(16),
          vInstallationId:
              latest.vInstallationId ?? AuthCrypto.randomEncoded(16),
          registration: <String, dynamic>{
            'v': 1,
            'seed': bootstrap.seed,
            'publicKey': bootstrap.publicKey,
            'slotId': bootstrap.slotId,
          },
        );
      });
      registration = state.registration!;
    }
    if (registration['commit'] != null ||
        registration['confirmation'] != null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'PENDING_CHECK_REQUIRED',
      );
    }
    var request = _map(registration['request']);
    if (request != null && request['state'] == 'UNKNOWN') {
      if (request['email'] != email) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
    } else {
      if (request != null &&
          _clock().isBefore(DateTime.parse(request['waitUntil'] as String))) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'OTP_WAIT',
        );
      }
      final requestedAt = _clock().toUtc();
      request = <String, dynamic>{
        'email': email,
        'key': AuthCrypto.randomEncoded(32),
        'state': 'UNKNOWN',
        'requestedAt': requestedAt.toIso8601String(),
        'waitUntil': requestedAt
            .add(const Duration(seconds: 60))
            .toIso8601String(),
      };
      final next = Map<String, dynamic>.from(registration)
        ..['request'] = request
        ..remove('ticket');
      state = await _store.update((latest) {
        _requireSameRegistration(latest, registration!);
        return latest.copyWith(registration: next);
      });
    }
    if (!_current(epoch)) {
      return;
    }
    _otpWaitUntil = DateTime.parse(request['waitUntil'] as String);
    _status = AuthFlowStatus.otpRequestUnknown;
    _notify();
    final key = request['key'] as String;
    final accepted = await _callOtp(
      () => _api.requestOtp(
        email: email,
        installationId: state.vInstallationId!,
        idempotencyKey: key,
      ),
      key: key,
      epoch: epoch,
    );
    if (!_current(epoch)) {
      return;
    }
    await _acceptOtpRequest(key, accepted.flowId, accepted.retryAfterSeconds);
    _status = AuthFlowStatus.otpRequested;
  });

  /// At forty seconds, query the original key. Pending requests may be retried
  /// by requestOtp with the same exact email, installation ID and original key.
  Future<void> reconcileOtpRequest() => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    final request = _map(state.registration?['request']);
    if (request == null) {
      throw const FormatException('No OTP operation');
    }
    if (_clock().isBefore(
      DateTime.parse(request['requestedAt'] as String)
          .add(const Duration(seconds: 40)),
    )) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'OTP_QUERY_WAIT',
      );
    }
    final key = request['key'] as String;
    final result = await _callOtp(
      () => _api.otpRequestResult(
        installationId: state.vInstallationId!,
        idempotencyKey: key,
      ),
      key: key,
      epoch: epoch,
    );
    if (!_current(epoch)) {
      return;
    }
    switch (result.state) {
      case OtpRequestState.accepted:
        await _acceptOtpRequest(key, result.flowId!, result.retryAfterSeconds);
        _status = AuthFlowStatus.otpRequested;
      case OtpRequestState.notSent:
        await _store.update((latest) {
          final registration = latest.registration;
          if (_map(registration?['request'])?['key'] != key) {
            return latest;
          }
          final next = Map<String, dynamic>.from(registration!)
            ..remove('request');
          return latest.copyWith(registration: next);
        });
        _otpWaitUntil = null;
        _status = AuthFlowStatus.idle;
      case OtpRequestState.pending:
        _status = AuthFlowStatus.otpRequestUnknown;
    }
  });

  Future<void> confirmOtp(String otp, {String? releaseReceipt}) => _run((
    epoch,
  ) async {
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'OTP_INVALID',
      );
    }
    var state = await _store.read();
    _validateState(state);
    _requireNoOtherPending(state);
    final registration = state.registration;
    final request = _map(registration?['request']);
    if (registration == null ||
        request?['flowId'] == null ||
        registration['commit'] != null) {
      throw const FormatException('No OTP flow');
    }
    var confirmation = _map(registration['confirmation']);
    if (confirmation == null) {
      confirmation = <String, dynamic>{
        'key': AuthCrypto.randomEncoded(32),
        'flowId': request!['flowId'],
        if (releaseReceipt != null) 'releaseReceipt': releaseReceipt,
      };
      final next = Map<String, dynamic>.from(registration)
        ..['confirmation'] = confirmation;
      state = await _store.update((latest) {
        _requireSameRegistration(latest, registration);
        return latest.copyWith(registration: next);
      });
      _originalOtp = otp;
    } else {
      if (confirmation['expired'] == true) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
      if ((_originalOtp != null && _originalOtp != otp) ||
          (releaseReceipt != null &&
              confirmation['releaseReceipt'] != releaseReceipt)) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
      // Restart deliberately requires the original OTP to be entered again.
      // V's keyed binding remains authoritative; no fast OTP hash is stored.
      _originalOtp = otp;
    }
    if (!_current(epoch)) {
      return;
    }
    _status = AuthFlowStatus.otpConfirmationPending;
    _notify();
    final fixedConfirmation = confirmation;
    final result = await _callOtp(
      () => _api.confirmOtp(
        flowId: fixedConfirmation['flowId'] as String,
        otp: otp,
        slotId: registration['slotId'] as String,
        bootstrapPublicKey: registration['publicKey'] as String,
        installationId: state.vInstallationId!,
        idempotencyKey: fixedConfirmation['key'] as String,
        releaseReceipt: fixedConfirmation['releaseReceipt'] as String?,
      ),
      key: fixedConfirmation['key'] as String,
      confirmation: true,
      epoch: epoch,
    );
    if (!_current(epoch)) {
      return;
    }
    if (result.registrationTicket != null) {
      final ticket = AuthCrypto.parseRegistrationTicket(
        result.registrationTicket!,
      );
      if (ticket.slotId != registration['slotId'] ||
          ticket.bootstrapPublicKey != registration['publicKey']) {
        throw const FormatException('Ticket binding mismatch');
      }
      await _store.update((latest) {
        if (_map(latest.registration?['confirmation'])?['key'] !=
            fixedConfirmation['key']) {
          return latest;
        }
        final next = Map<String, dynamic>.from(latest.registration!)
          ..['ticket'] = result.registrationTicket
          ..remove('confirmation');
        return latest.copyWith(registration: next);
      });
      _originalOtp = null;
      _status = AuthFlowStatus.eligibilityReady;
    } else {
      _status = AuthFlowStatus.otpConfirmationPending;
    }
  });

  Future<void> reconcileOtpConfirmation() => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    final confirmation = _map(state.registration?['confirmation']);
    if (confirmation == null) {
      throw const FormatException('No confirmation operation');
    }
    final key = confirmation['key'] as String;
    final result = await _callOtp(
      () => _api.otpConfirmationResult(
        flowId: confirmation['flowId'] as String,
        installationId: state.vInstallationId!,
        idempotencyKey: key,
      ),
      key: key,
      confirmation: true,
      epoch: epoch,
    );
    if (!_current(epoch)) {
      return;
    }
    if (result.state == OtpConfirmationState.notCommitted ||
        result.state == OtpConfirmationState.reverifyRequired) {
      await _store.update((latest) {
        if (_map(latest.registration?['confirmation'])?['key'] != key) {
          return latest;
        }
        final next = Map<String, dynamic>.from(latest.registration!)
          ..remove('confirmation')
          ..remove('request')
          ..remove('ticket');
        return latest.copyWith(registration: next);
      });
      _originalOtp = null;
      _status = AuthFlowStatus.idle;
    } else {
      // TICKET_AVAILABLE is not a ticket: original confirm POST is required
      // to receive it, within V's bounded window, without changing the key.
      _status = AuthFlowStatus.otpConfirmationPending;
    }
  });

  /// RESULT_EXPIRED permits an explicit exit from the expired V operation. It
  /// does not prove NOT_SENT or trigger a new message. The original bootstrap
  /// slot is retained and the next user request is still subject to V budgets.
  Future<void> abandonExpiredOtpOperation() => _run((epoch) async {
    await _store.update((latest) {
      final registration = latest.registration;
      if (registration == null ||
          registration['commit'] != null ||
          (_map(registration['request'])?['state'] != 'EXPIRED' &&
              _map(registration['confirmation'])?['expired'] != true)) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
      final next = Map<String, dynamic>.from(registration)
        ..remove('request')
        ..remove('confirmation')
        ..remove('ticket');
      return latest.copyWith(registration: next);
    });
    if (!_current(epoch)) return;
    _originalOtp = null;
    _otpWaitUntil = null;
    _status = AuthFlowStatus.idle;
  });

  Future<void> createRegistration(String username, String password) => _run((
    epoch,
  ) async {
    final state = await _store.read();
    _validateState(state);
    _requireNoOtherPending(state);
    final registration = state.registration;
    if (registration?['ticket'] == null || registration?['commit'] != null) {
      throw const FormatException('No current eligibility');
    }
    final result = await _api.createRegistrationIntent(
      registrationTicket: registration!['ticket'] as String,
      username: username.toLowerCase(),
      password: password,
      installationId: state.cInstallationId!,
    );
    if (!_current(epoch)) {
      return;
    }
    _requireSameRegistration(await _store.read(), registration);
    _registrationIntent = result;
    _username = username.toLowerCase();
    _recoveryCode = result.recoveryCode;
    _status = AuthFlowStatus.registrationCodeShown;
  });

  /// Drops the original code before accepting confirmation. Neither the store
  /// nor any debug/error representation can recover this once hidden.
  void hideRecoveryCode() {
    if (_busy) {
      return;
    }
    if (_status == AuthFlowStatus.registrationCodeShown) {
      _status = AuthFlowStatus.registrationCodeConfirmation;
    } else if (_status == AuthFlowStatus.resetCodeShown) {
      _status = AuthFlowStatus.resetCodeConfirmation;
    } else {
      return;
    }
    _recoveryCode = null;
    final registration = _registrationIntent;
    if (registration != null) {
      _registrationIntent = RegistrationIntent(
        intentId: registration.intentId,
        challenge: registration.challenge,
        expiresAt: registration.expiresAt,
        recoveryCode: '',
      );
    }
    final reset = _resetIntent;
    if (reset != null) {
      _resetIntent = PasswordResetIntent(
        resetIntentId: reset.resetIntentId,
        expiresAt: reset.expiresAt,
        username: reset.username,
        newRecoveryCode: '',
      );
    }
    _notify();
  }

  Future<void> commitRegistration(String confirmation) => _run((epoch) async {
    if (_status != AuthFlowStatus.registrationCodeConfirmation ||
        _registrationIntent == null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'HIDE_CODE_FIRST',
      );
    }
    final intent = _registrationIntent!;
    var state = await _store.read();
    _validateState(state);
    _requireNoOtherPending(state);
    final registration = state.registration;
    if (registration == null ||
        registration['ticket'] == null ||
        registration['commit'] != null) {
      throw const FormatException('No current eligibility');
    }
    final key = AuthCrypto.randomEncoded(32);
    final signature = await AuthCrypto.signBootstrap(
      seed: registration['seed'] as String,
      registrationTicket: registration['ticket'] as String,
      intentId: intent.intentId,
      challenge: intent.challenge,
    );
    if (!_current(epoch)) {
      return;
    }
    final next = Map<String, dynamic>.from(registration)
      ..['commit'] = <String, dynamic>{'intentId': intent.intentId, 'key': key};
    state = await _store.update((latest) {
      _requireNoOtherPending(latest);
      _requireSameRegistration(latest, registration);
      if (latest.registration?['commit'] != null) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
      return latest.copyWith(registration: next);
    });
    if (!_current(epoch)) {
      return;
    }
    _status = AuthFlowStatus.registrationUnknown;
    _notify();
    late AuthSession session;
    try {
      session = await _api.commitRegistration(
        intentId: intent.intentId,
        bootstrapSignature: signature,
        recoveryCodeConfirmation: confirmation,
        idempotencyKey: key,
      );
    } on AuthFailure catch (failure) {
      // These complete C responses reject this first submission before
      // registration. Unknown/replay/tombstone results retain the anchor.
      const rejectedBeforeCommit = {
        'INTENT_INVALID',
        'USERNAME_UNAVAILABLE',
        'CHALLENGE_INVALID',
        'REGISTRATION_TICKET_EXPIRED',
        'REGISTRATION_TICKET_NOT_YET_VALID',
        'REGISTRATION_TICKET_INVALID',
        'REQUEST_INVALID',
        'RATE_LIMITED',
      };
      if (_current(epoch) &&
          !failure.uncertain &&
          !failure.resultsExpired &&
          rejectedBeforeCommit.contains(failure.code)) {
        await _store.update((latest) {
          if (_map(latest.registration?['commit'])?['key'] != key) {
            return latest;
          }
          final next = Map<String, dynamic>.from(latest.registration!)
            ..remove('commit');
          return latest.copyWith(registration: next);
        });
        _registrationIntent = null;
        _status = AuthFlowStatus.eligibilityReady;
      }
      rethrow;
    }
    if (!_current(epoch)) {
      return;
    }
    if (_map((await _store.read()).registration?['commit'])?['key'] != key) {
      return;
    }
    await _acceptRegistrationSession(session);
    if (!_current(epoch)) {
      return;
    }
    await _store.update(
      (latest) => _map(latest.registration?['commit'])?['key'] == key
          ? latest.copyWith(clearRegistration: true)
          : latest,
    );
    _registrationIntent = null;
    _recoveryCode = null;
    _username = null;
    _status = AuthFlowStatus.registrationComplete;
  });

  Future<void> beginCodeReset(String recoveryCode) => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    if (state.pendingReset != null || state.registration?['commit'] != null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'PENDING_CHECK_REQUIRED',
      );
    }
    final result = await _api.createCodeResetIntent(recoveryCode);
    if (!_current(epoch)) {
      return;
    }
    _resetIntent = result;
    _username = result.username;
    _recoveryCode = result.newRecoveryCode;
    _status = AuthFlowStatus.resetCodeShown;
  });

  /// A discoverable assertion only creates the existing restricted reset
  /// intent. It never logs in, cancels closure, or bypasses full new-code input.
  Future<void> beginPasskeyReset() {
    if (_busy || _disposed) return Future<void>.value();
    // Route/session cancellation owns the entire workflow, including a blocked
    // first secure-store read and the initial busy notification. Ownership of a
    // native sheet starts only at get.
    _passkeyRecoveryActive = true;
    _passkeyAuthorityVersion = _sessionAuthorityVersion();
    return _run((epoch) async {
      if (!_current(epoch)) return;
      final authorityVersion = _passkeyAuthorityVersion!;
      try {
        final recovery = _passkeyApi;
        final client = _passkey;
        if (recovery == null || client == null) {
          throw const AuthFailure(kind: AuthFailureKind.rejected,
              code: 'PASSKEY_UNAVAILABLE');
        }
        final original = await _store.read();
        if (!_current(epoch) || _sessionAuthorityVersion() != authorityVersion) return;
        _validateState(original);
        if (original.pendingReset != null || original.registration?['commit'] != null) {
          throw const AuthFailure(kind: AuthFailureKind.rejected,
              code: 'PENDING_CHECK_REQUIRED');
        }
        Future<bool> current() async {
          if (!_current(epoch) || _sessionAuthorityVersion() != authorityVersion) return false;
          final latest = await _store.read();
          return _current(epoch) && _sessionAuthorityVersion() == authorityVersion &&
              latest.session?.token == original.session?.token &&
              latest.pendingReset == null &&
              latest.registration?['commit'] == null &&
              jsonEncode(latest.logouts.map((e) => e.toJson()).toList()) ==
                  jsonEncode(original.logouts.map((e) => e.toJson()).toList()) &&
              jsonEncode(latest.pendingClosure) == jsonEncode(original.pendingClosure);
        }
        if (!await current()) return;
        if (!_current(epoch) || _sessionAuthorityVersion() != authorityVersion) return;
        final options = await recovery.createPasskeyResetOptions();
        if (!await current()) return;
        if (!_current(epoch) || _sessionAuthorityVersion() != authorityVersion) return;
        _nativeRecoveryEpoch = epoch;
        late Map<String, dynamic> assertion;
        try {
          assertion = await client.get(options.publicKey);
        } finally {
          if (_nativeRecoveryEpoch == epoch) _nativeRecoveryEpoch = null;
        }
        if (!await current()) return;
        if (!_current(epoch) || _sessionAuthorityVersion() != authorityVersion) return;
        final result = await recovery.createPasskeyResetIntent(
            challengeId: options.challengeId, assertion: assertion);
        if (!await current()) return;
        if (!_current(epoch) || _sessionAuthorityVersion() != authorityVersion) return;
        _resetIntent = result;
        _username = result.username;
        _recoveryCode = result.newRecoveryCode;
        _status = AuthFlowStatus.resetCodeShown;
      } on PasskeyFailure catch (failure) {
        if (!_current(epoch)) return;
        _errorMessage = failure.code == 'PASSKEY_CANCELLED'
            ? '已取消 Passkey 验证。你仍可使用恢复码。'
            : '系统 Passkey 暂不可用，请重试或使用恢复码。';
      } finally {
        if (_current(epoch)) {
          _passkeyRecoveryActive = false;
          _passkeyAuthorityVersion = null;
        }
      }
    });
  }

  /// Closing a route invalidates only the in-flight native ceremony; durable
  /// reset/registration commits remain owned by their original result records.
  void cancelPasskeyRecovery() {
    if (!_passkeyRecoveryActive) return;
    final ownedSheet = _nativeRecoveryEpoch == _epoch;
    _epoch++;
    _busy = false;
    _passkeyRecoveryActive = false;
    _passkeyAuthorityVersion = null;
    _nativeRecoveryEpoch = null;
    final client = _passkey;
    if (ownedSheet && client is CancellablePasskeyClient) {
      unawaited(client.cancel().catchError((Object _) {}));
    }
    _notify();
  }

  Future<void> commitReset(String newPassword, String confirmation) =>
      _run((epoch) async {
        if (_status != AuthFlowStatus.resetCodeConfirmation ||
            _resetIntent == null) {
          throw const AuthFailure(
            kind: AuthFailureKind.rejected,
            code: 'HIDE_CODE_FIRST',
          );
        }
        final intent = _resetIntent!;
        final key = AuthCrypto.randomEncoded(32);
        await _store.update((latest) {
          if (latest.pendingReset != null) {
            throw const AuthFailure(
              kind: AuthFailureKind.rejected,
              code: 'PENDING_CHECK_REQUIRED',
            );
          }
          return latest.copyWith(
            pendingReset: <String, dynamic>{
              'v': 1,
              'intentId': intent.resetIntentId,
              'key': key,
              'state': 'UNKNOWN',
              if (latest.session != null)
                'originalTokenDigest': _tokenDigest(latest.session!.token),
            },
          );
        });
        if (!_current(epoch)) {
          return;
        }
        _clearCommunityAccess();
        _status = AuthFlowStatus.resetUnknown;
        _notify();
        await _api.commitPasswordReset(
          resetIntentId: intent.resetIntentId,
          newPassword: newPassword,
          newRecoveryCodeConfirmation: confirmation,
          idempotencyKey: key,
        );
        if (!_current(epoch)) {
          return;
        }
        await _recordResetResult(key, PasswordResetResult.committed);
        _resetIntent = null;
        _status = AuthFlowStatus.resetCommitted;
      });

  Future<void> reconcileReset() => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    final pending = state.pendingReset;
    if (pending == null) {
      throw const FormatException('No reset result operation');
    }
    _status = _resetStatus(pending['state'] as String);
    if (pending['state'] == 'COMMITTED' ||
        pending['state'] == 'NOT_COMMITTED') {
      return;
    }
    final key = pending['key'] as String;
    try {
      final result = await _api.passwordResetResult(
        resetIntentId: pending['intentId'] as String,
        idempotencyKey: key,
      );
      if (!_current(epoch)) {
        return;
      }
      await _recordResetResult(key, result);
      _status = switch (result) {
        PasswordResetResult.committed => AuthFlowStatus.resetCommitted,
        PasswordResetResult.notCommitted => AuthFlowStatus.resetNotCommitted,
        PasswordResetResult.pending => AuthFlowStatus.resetUnknown,
      };
    } on AuthFailure catch (failure) {
      if (!_current(epoch)) {
        return;
      }
      if (failure.resultsExpired) {
        await _store.update(
          (latest) => latest.pendingReset?['key'] == key
              ? latest.copyWith(
                  pendingReset: Map<String, dynamic>.from(latest.pendingReset!)
                    ..['state'] = 'EXPIRED',
                )
              : latest,
        );
      }
      // 404, timeout, PENDING and 410 never establish NOT_COMMITTED.
      _status = AuthFlowStatus.resetUnknown;
      rethrow;
    }
  });

  /// Explicit acknowledgement is allowed only after a persistent conclusion.
  Future<void> acknowledgeResetResult() => _run((epoch) async {
    await _store.update((latest) {
      final pending = latest.pendingReset;
      if (pending == null) {
        return latest;
      }
      if (pending['state'] != 'COMMITTED' &&
          pending['state'] != 'NOT_COMMITTED') {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
      return latest.copyWith(clearPendingReset: true);
    });
    if (_current(epoch)) _status = AuthFlowStatus.idle;
  });

  Future<void> requestClosure(String password) => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    if (state.pendingClosure != null ||
        state.pendingReset != null ||
        state.session == null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'PENDING_CHECK_REQUIRED',
      );
    }
    final token = state.session!.token;
    final id = AuthCrypto.randomEncoded(32);
    final secret = AuthCrypto.randomEncoded(32);
    final digest = AuthCrypto.closureStatusDigest(secret);
    await _store.update((latest) {
      if (latest.pendingClosure != null ||
          latest.pendingReset != null ||
          latest.session?.token != token) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'CREDENTIAL_STATE_CHANGED',
        );
      }
      return latest.copyWith(
        clearSession: true,
        pendingClosure: <String, dynamic>{
          'v': 1,
          'closureId': id,
          'statusSecret': secret,
          'statusDigest': digest,
          'originalBearer': token,
          'state': 'UNKNOWN',
        },
      );
    });
    if (!_current(epoch)) {
      return;
    }
    _clearCommunityAccess();
    _status = AuthFlowStatus.closureUnknown;
    _notify();
    final result = await _api.requestClosure(
      sessionToken: token,
      password: password,
      closureId: id,
      statusDigest: digest,
    );
    if (!_current(epoch)) {
      return;
    }
    if (result.closureId != id) {
      throw const FormatException('Closure ID mismatch');
    }
    await _recordClosure(
      id,
      ClosureStatus(state: ClosureState.pending, dueAt: result.dueAt),
    );
    _closureStatus = ClosureStatus(
      state: ClosureState.pending,
      dueAt: result.dueAt,
    );
    _status = AuthFlowStatus.closurePending;
  });

  /// Retry must use exactly the original capability and ID. A 401 is followed
  /// by status lookup; no historical Bearer authentication bypass is attempted.
  Future<void> retryClosure(String password) => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    final pending = state.pendingClosure;
    if (pending == null ||
        pending['state'] != 'UNKNOWN' ||
        pending['originalBearer'] == null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'PENDING_CHECK_REQUIRED',
      );
    }
    final id = pending['closureId'] as String;
    final accepted = await _api.requestClosure(
      sessionToken: pending['originalBearer'] as String,
      password: password,
      closureId: id,
      statusDigest: pending['statusDigest'] as String,
    );
    if (!_current(epoch)) {
      return;
    }
    if (accepted.closureId != id) {
      throw const FormatException('Closure ID mismatch');
    }
    final status = ClosureStatus(
      state: ClosureState.pending,
      dueAt: accepted.dueAt,
    );
    await _recordClosure(id, status);
    _closureStatus = status;
    _status = AuthFlowStatus.closurePending;
  });

  Future<void> reconcileClosure() => _run((epoch) async {
    final state = await _store.read();
    _validateState(state);
    final pending = state.pendingClosure;
    if (pending == null) {
      throw const FormatException('No closure status operation');
    }
    final id = pending['closureId'] as String;
    final result = await _api.closureStatus(
      closureId: id,
      statusSecret: pending['statusSecret'] as String,
    );
    if (!_current(epoch)) {
      return;
    }
    await _recordClosure(id, result);
    _closureStatus = result;
    _status = _closureFlowStatus(result.state);
  });

  Future<void> forgetClosureStatus() => _run((epoch) async {
    await _store.update((latest) {
      final pending = latest.pendingClosure;
      if (pending == null) {
        return latest;
      }
      if (pending['state'] != 'CANCELLED' && pending['state'] != 'RELEASED') {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'PENDING_CHECK_REQUIRED',
        );
      }
      return latest.copyWith(clearPendingClosure: true);
    });
    if (_current(epoch)) {
      _closureStatus = null;
      _status = AuthFlowStatus.idle;
    }
  });

  /// Returning to login clears UI memory only. It cannot erase unresolved
  /// durable operations or convert an unknown result into a new submission.
  void resetFlow() {
    if (_busy) {
      return;
    }
    _epoch++;
    _registrationIntent = null;
    _resetIntent = null;
    _recoveryCode = null;
    _originalOtp = null;
    _username = null;
    _error = null;
    _errorMessage = null;
    _status = AuthFlowStatus.idle;
    _notify();
  }

  Future<void> _acceptOtpRequest(String key, String flow, int wait) async {
    await _store.update((latest) {
      final request = _map(latest.registration?['request']);
      if (request?['key'] != key) {
        return latest;
      }
      final deadline = _clock().toUtc().add(Duration(seconds: wait));
      final changed = Map<String, dynamic>.from(request!)
        ..['state'] = 'ACCEPTED'
        ..['flowId'] = flow
        ..['waitUntil'] = deadline.toIso8601String();
      final next = Map<String, dynamic>.from(latest.registration!)
        ..['request'] = changed;
      _otpWaitUntil = deadline;
      return latest.copyWith(registration: next);
    });
  }

  Future<T> _callOtp<T>(
    Future<T> Function() call, {
    required String key,
    required int epoch,
    bool confirmation = false,
  }) async {
    try {
      return await call();
    } on AuthFailure catch (failure) {
      if (failure.resultsExpired && _current(epoch)) {
        await _store.update((latest) {
          final registration = latest.registration;
          if (registration == null) return latest;
          final operation = _map(
            registration[confirmation ? 'confirmation' : 'request'],
          );
          if (operation?['key'] != key) return latest;
          final changed = Map<String, dynamic>.from(operation!);
          if (confirmation) {
            changed['expired'] = true;
          } else {
            changed['state'] = 'EXPIRED';
          }
          final next = Map<String, dynamic>.from(registration)
            ..[confirmation ? 'confirmation' : 'request'] = changed;
          return latest.copyWith(registration: next);
        });
      }
      rethrow;
    }
  }

  Future<void> _recordResetResult(
    String key,
    PasswordResetResult result,
  ) async {
    await _store.update((latest) {
      final pending = latest.pendingReset;
      if (pending?['key'] != key) {
        return latest;
      }
      if (pending!['state'] == 'COMMITTED' ||
          pending['state'] == 'NOT_COMMITTED') {
        return latest;
      }
      if (result == PasswordResetResult.pending) {
        return latest;
      }
      final next = Map<String, dynamic>.from(pending)
        ..['state'] = result == PasswordResetResult.committed
            ? 'COMMITTED'
            : 'NOT_COMMITTED';
      final session = latest.session;
      if (result == PasswordResetResult.committed &&
          session != null &&
          next['originalTokenDigest'] == _tokenDigest(session.token)) {
        final digest = _tokenDigest(session.token);
        final tasks = List<LogoutTask>.from(latest.logouts);
        if (!tasks.any((task) => task.tokenDigest == digest)) {
          tasks.add(
            LogoutTask(
              tokenDigest: digest,
              revocationSecret: AuthCrypto.revocationSecret(session.token),
            ),
          );
        }
        return latest.copyWith(
          pendingReset: next,
          clearSession: true,
          logouts: tasks,
        );
      }
      return latest.copyWith(pendingReset: next);
    });
  }

  Future<void> _recordClosure(String id, ClosureStatus status) async {
    await _store.update((latest) {
      final pending = latest.pendingClosure;
      if (pending?['closureId'] != id) {
        return latest;
      }
      final oldState = pending!['state'];
      final nextState = _closureStateName(status.state);
      final allowed = <String, Set<String>>{
        'UNKNOWN': {
          'PENDING',
          'FINALIZING',
          'CANCELLED',
          'CLOSED_RELEASE_PENDING',
          'RELEASED',
        },
        'PENDING': {
          'PENDING',
          'FINALIZING',
          'CANCELLED',
          'CLOSED_RELEASE_PENDING',
          'RELEASED',
        },
        'FINALIZING': {'FINALIZING', 'CLOSED_RELEASE_PENDING', 'RELEASED'},
        'CANCELLED': {'CANCELLED'},
        'CLOSED_RELEASE_PENDING': {'CLOSED_RELEASE_PENDING', 'RELEASED'},
        'RELEASED': {'RELEASED'},
      };
      if (!(allowed[oldState]?.contains(nextState) ?? false)) {
        throw const FormatException('Closure state regression');
      }
      if (pending['dueAt'] != null &&
          status.dueAt != null &&
          DateTime.parse(pending['dueAt'] as String) != status.dueAt) {
        throw const FormatException('Closure deadline changed');
      }
      final next = Map<String, dynamic>.from(pending)
        ..['state'] = _closureStateName(status.state)
        ..remove('originalBearer')
        ..remove('dueAt')
        ..remove('releaseReceipt');
      if (status.dueAt != null) {
        next['dueAt'] = status.dueAt!.toUtc().toIso8601String();
      }
      if (status.releaseReceipt != null) {
        next['releaseReceipt'] = status.releaseReceipt;
      }
      return latest.copyWith(pendingClosure: next);
    });
  }

  void _restoreClosure(Map<String, dynamic> pending) {
    final state = pending['state'] as String;
    if (state == 'UNKNOWN') {
      _status = AuthFlowStatus.closureUnknown;
      return;
    }
    final parsed = ClosureState.values.firstWhere(
      (value) => _closureStateName(value) == state,
    );
    _closureStatus = ClosureStatus(
      state: parsed,
      dueAt: pending['dueAt'] == null
          ? null
          : DateTime.parse(pending['dueAt'] as String),
      releaseReceipt: pending['releaseReceipt'] as String?,
    );
    _status = _closureFlowStatus(parsed);
  }

  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (_busy || _disposed) {
      return;
    }
    final epoch = ++_epoch;
    _busy = true;
    _error = null;
    _errorMessage = null;
    _notify();
    try {
      await action(epoch);
    } on AuthFailure catch (failure) {
      if (!_current(epoch)) {
        return;
      }
      _error = failure;
      _errorMessage = failure.resultsExpired
          ? '核对记录已过保留期，无法据此确认是否提交。请主动选择后续操作。'
          : failure.uncertain
          ? '结果未知，请保留原请求并核对。'
          : failure.code == 'HIDE_CODE_FIRST'
          ? '先隐藏原恢复码，再完整重输确认。'
          : failure.code == 'PENDING_CHECK_REQUIRED'
          ? '请先核对原操作，不能创建新的请求。'
          : failure.code == 'OTP_WAIT' || failure.code == 'OTP_QUERY_WAIT'
          ? '请等待倒计时结束。'
          : '操作未完成，请检查输入或核对原操作。';
    } on Object {
      if (!_current(epoch)) {
        return;
      }
      _errorMessage = '安全存储或响应验证失败，操作已停止；请重试核对。';
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _notify();
      }
    }
  }

  void _requireNoOtherPending(AuthState state) {
    if (state.pendingReset != null ||
        state.pendingClosure != null ||
        state.session != null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'PENDING_CHECK_REQUIRED',
      );
    }
  }

  void _requireSameRegistration(
    AuthState state,
    Map<String, dynamic> expected,
  ) {
    final current = state.registration;
    if (current == null ||
        current['seed'] != expected['seed'] ||
        _map(current['request'])?['key'] != _map(expected['request'])?['key'] ||
        _map(current['confirmation'])?['key'] !=
            _map(expected['confirmation'])?['key'] ||
        _map(current['commit'])?['key'] != _map(expected['commit'])?['key'] ||
        current['ticket'] != expected['ticket']) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'CREDENTIAL_STATE_CHANGED',
      );
    }
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value == null ? null : Map<String, dynamic>.from(value as Map);

  static String _tokenDigest(String token) => AuthCrypto.encode(
    hashes.sha256.convert(AuthCrypto.decode(token, bytes: 32)).bytes,
  );

  static AuthFlowStatus _resetStatus(String state) => switch (state) {
    'COMMITTED' => AuthFlowStatus.resetCommitted,
    'NOT_COMMITTED' => AuthFlowStatus.resetNotCommitted,
    _ => AuthFlowStatus.resetUnknown,
  };

  static AuthFlowStatus _closureFlowStatus(ClosureState state) =>
      switch (state) {
        ClosureState.pending => AuthFlowStatus.closurePending,
        ClosureState.finalizing => AuthFlowStatus.closureFinalizing,
        ClosureState.cancelled => AuthFlowStatus.closureCancelled,
        ClosureState.closedReleasePending =>
          AuthFlowStatus.closureClosedReleasePending,
        ClosureState.released => AuthFlowStatus.closureReleased,
      };

  static String _closureStateName(ClosureState state) => switch (state) {
    ClosureState.pending => 'PENDING',
    ClosureState.finalizing => 'FINALIZING',
    ClosureState.cancelled => 'CANCELLED',
    ClosureState.closedReleasePending => 'CLOSED_RELEASE_PENDING',
    ClosureState.released => 'RELEASED',
  };

  void _validateState(AuthState state) => AuthWorkflowCodec.validate(
    registration: state.registration,
    pendingReset: state.pendingReset,
    pendingClosure: state.pendingClosure,
    cInstallationId: state.cInstallationId,
    vInstallationId: state.vInstallationId,
  );

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    cancelPasskeyRecovery();
    _sessionAuthority?.removeListener(_sessionAuthorityChanged);
    _disposed = true;
    _epoch++;
    _recoveryCode = null;
    _registrationIntent = null;
    _resetIntent = null;
    _originalOtp = null;
    super.dispose();
  }
}
