import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

import 'auth_crypto.dart';
import 'auth_models.dart';
import 'auth_session_controller.dart';
import 'auth_store.dart';
import 'credential_management_api.dart';

enum SecurityManagementStatus {
  signedOut,
  loading,
  ready,
  rotationCodeShown,
  rotationCodeConfirmation,
  removalConfirmation,
  pending,
  committed,
  notCommitted,
  storageFailure,
  unavailable,
  resultExpired,
  previousSessionPending,
}

enum CredentialChangeKind { rotation, passkeyBinding, passkeyRemoval }

/// Owns explicit foreground credential operations. One original result anchor
/// is durably written before the final request. Passwords, new recovery codes
/// and native ceremony responses are never saved or retried automatically.
class SecurityManagementController extends ChangeNotifier {
  SecurityManagementController({
    required CredentialManagementApi api,
    required AuthStore store,
    required PasskeyClient passkey,
    required AuthSessionController sessions,
  }) : _api = api,
       _store = store,
       _passkey = passkey,
       _sessions = sessions {
    _observedToken = _activeRecord()?.token;
    _store.addListener(_authorityChanged);
    _sessions.addListener(_authorityChanged);
  }

  final CredentialManagementApi _api;
  final AuthStore _store;
  final PasskeyClient _passkey;
  final AuthSessionController _sessions;
  SecurityManagementStatus _status = SecurityManagementStatus.signedOut;
  DeviceDirectory? _devices;
  RecoveryCredentialSummary? _credentials;
  RecoveryCodeRotation? _rotation;
  PasskeyRemovalIntent? _removal;
  String? _recoveryCode, _rotationDigest, _removalCredentialId, _errorMessage;
  String? _observedToken;
  AuthFailure? _error;
  int _epoch = 0;
  int? _nativeOwnerEpoch;
  bool _busy = false, _disposed = false;

  SecurityManagementStatus get status => _status;
  bool get busy => _busy;
  AuthFailure? get error => _error;
  String? get errorMessage => _errorMessage;
  DeviceDirectory? get devices => _devices;
  RecoveryCredentialSummary? get credentials => _credentials;
  String? get recoveryCode => _recoveryCode;
  String? get removalCredentialId => _removalCredentialId;
  CredentialChangeKind? get pendingKind =>
      switch (_store.current?.pendingCredentialChange?['kind']) {
        'ROTATION' => CredentialChangeKind.rotation,
        'PASSKEY_BINDING' => CredentialChangeKind.passkeyBinding,
        'PASSKEY_REMOVAL' => CredentialChangeKind.passkeyRemoval,
        _ => null,
      };

  SessionRecord? _activeRecord() {
    final state = _store.current;
    final record = state?.session;
    if (state == null || record == null ||
        !_sessions.isCurrentToken(record.token)) return null;
    final digest = sessionTokenDigest(record.token);
    if (state.logouts.any((entry) => entry.tokenDigest == digest) ||
        state.pendingReset?['state'] == 'UNKNOWN' ||
        state.pendingReset?['state'] == 'EXPIRED' ||
        state.pendingClosure?['state'] == 'UNKNOWN') return null;
    return record;
  }

  bool _current(int epoch, SessionRecord record) =>
      !_disposed && epoch == _epoch &&
      _activeRecord()?.token == record.token &&
      _activeRecord()?.accountId == record.accountId;

  void _authorityChanged() {
    if (_disposed) return;
    final active = _activeRecord();
    if (_store.current == null || active?.token != _observedToken) {
      _epoch++;
      _cancelOwnedNative();
      _observedToken = active?.token;
      _clearEphemeral();
      _devices = null;
      _credentials = null;
      _busy = false;
      _status = _store.current == null
          ? SecurityManagementStatus.storageFailure
          : _sessions.status == AuthStatus.unavailable
          ? SecurityManagementStatus.unavailable
          : SecurityManagementStatus.signedOut;
      _notify();
    }
  }

  /// Opening the page performs at most one read of an existing result anchor.
  /// No timer, lifecycle callback or result query renews the session in a loop.
  Future<void> load() => _run((epoch, record) async {
    _clearEphemeral();
    _devices = null;
    _credentials = null;
    _status = SecurityManagementStatus.loading;
    _notify();
    final pending = _store.current!.pendingCredentialChange;
    if (pending != null) {
      if (!_belongs(pending, record)) {
        _status = SecurityManagementStatus.previousSessionPending;
        return;
      }
      if (pending['state'] == 'UNKNOWN') {
        await _reconcile(epoch, record, pending);
        return;
      }
      _status = _pendingStatus(pending['state']);
      return;
    }
    await _loadDirectory(epoch, record);
  });

  Future<void> _loadDirectory(int epoch, SessionRecord record) async {
    if (!_current(epoch, record)) return;
    final devices = await _api.devices(record.token);
    if (!await _metadata(epoch, record, devices.sessionExpiresAt)) return;
    if (!_current(epoch, record)) return;
    final credentials = await _api.recoveryCredentials(record.token);
    if (!await _metadata(epoch, record, credentials.sessionExpiresAt)) return;
    if (!_current(epoch, record)) return;
    final expiry = _store.current!.session!.expiresAt;
    _devices = DeviceDirectory(
      currentSignedInAt: devices.currentSignedInAt,
      lastReplacedSignedInAt: devices.lastReplacedSignedInAt,
      lastReplacedAt: devices.lastReplacedAt,
      sessionExpiresAt: expiry,
    );
    _credentials = RecoveryCredentialSummary(
      passkeys: List<PasskeySummary>.unmodifiable(credentials.passkeys),
      sessionExpiresAt: expiry,
    );
    _status = SecurityManagementStatus.ready;
  }

  Future<void> beginRecoveryCodeRotation(String password) =>
      _run((epoch, record) async {
        _requireNoPending();
        _clearEphemeral();
        final intent = await _api.createRecoveryCodeRotation(
          sessionToken: record.token,
          password: password,
        );
        if (!await _metadata(epoch, record, intent.sessionExpiresAt)) return;
        if (!_current(epoch, record)) return;
        final digest = _codeDigest(intent.newRecoveryCode);
        _rotation = intent;
        _recoveryCode = intent.newRecoveryCode;
        _rotationDigest = digest;
        _status = SecurityManagementStatus.rotationCodeShown;
      });

  /// Showing and confirming are separate screens; the original plaintext is
  /// dropped before the input field is made available and cannot be shown twice.
  void hideRecoveryCode() {
    if (_busy || _status != SecurityManagementStatus.rotationCodeShown ||
        _rotation == null) return;
    final previous = _rotation!;
    _rotation = RecoveryCodeRotation(
      rotationIntentId: previous.rotationIntentId,
      expiresAt: previous.expiresAt,
      newRecoveryCode: '',
      sessionExpiresAt: previous.sessionExpiresAt,
    );
    _recoveryCode = null;
    _status = SecurityManagementStatus.rotationCodeConfirmation;
    _notify();
  }

  Future<void> confirmRecoveryCodeRotation(String fullConfirmation) =>
      _run((epoch, record) async {
        _requireNoPending();
        final intent = _rotation;
        if (_status != SecurityManagementStatus.rotationCodeConfirmation ||
            intent == null || _rotationDigest == null) {
          throw const AuthFailure(
            kind: AuthFailureKind.rejected, code: 'HIDE_CODE_FIRST',
          );
        }
        if (_codeDigest(fullConfirmation) != _rotationDigest) {
          throw const AuthFailure(
            kind: AuthFailureKind.rejected,
            code: 'RECOVERY_CODE_CONFIRMATION_FAILED',
          );
        }
        final pending = await _savePending(
          epoch, record, 'ROTATION', intent.rotationIntentId,
        );
        if (pending == null || !_current(epoch, record)) return;
        _clearEphemeral();
        _status = SecurityManagementStatus.pending;
        _notify();
        if (!_current(epoch, record)) return;
        final expiry = await _api.confirmRecoveryCodeRotation(
          sessionToken: record.token,
          rotationIntentId: intent.rotationIntentId,
          newRecoveryCodeConfirmation: fullConfirmation,
          idempotencyKey: pending['key'] as String,
        );
        await _acceptResult(
          epoch, record, pending, CredentialChangeState.committed, expiry,
        );
      });

  Future<void> bindPasskey(String password) => _run((epoch, record) async {
    _requireNoPending();
    _clearEphemeral();
    final options = await _api.createPasskeyCreationOptions(
      sessionToken: record.token, password: password,
    );
    if (!await _metadata(epoch, record, options.sessionExpiresAt)) return;
    if (!_current(epoch, record)) return;
    _nativeOwnerEpoch = epoch;
    final Map<String, dynamic> attestation;
    try {
      attestation = await _passkey.create(options.publicKey);
    } finally {
      if (_nativeOwnerEpoch == epoch) _nativeOwnerEpoch = null;
    }
    // Native completion, including a callback after logout or new login, grants
    // no authority. Never persist or transmit a stale native result.
    if (!_current(epoch, record)) return;
    final pending = await _savePending(
      epoch, record, 'PASSKEY_BINDING', options.challengeId,
    );
    if (pending == null || !_current(epoch, record)) return;
    _status = SecurityManagementStatus.pending;
    _notify();
    if (!_current(epoch, record)) return;
    final expiry = await _api.registerPasskey(
      sessionToken: record.token,
      challengeId: options.challengeId,
      attestation: attestation,
      idempotencyKey: pending['key'] as String,
    );
    await _acceptResult(
      epoch, record, pending, CredentialChangeState.committed, expiry,
    );
  });

  Future<void> beginPasskeyRemoval(String credentialId, String password) =>
      _run((epoch, record) async {
        _requireNoPending();
        _clearEphemeral();
        final intent = await _api.createPasskeyRemovalIntent(
          sessionToken: record.token,
          credentialId: credentialId,
          password: password,
        );
        if (!await _metadata(epoch, record, intent.sessionExpiresAt)) return;
        if (!_current(epoch, record)) return;
        _removal = intent;
        _removalCredentialId = credentialId;
        _status = SecurityManagementStatus.removalConfirmation;
      });

  Future<void> confirmPasskeyRemoval() => _run((epoch, record) async {
    _requireNoPending();
    final intent = _removal;
    final credential = _removalCredentialId;
    if (_status != SecurityManagementStatus.removalConfirmation ||
        intent == null || credential == null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected, code: 'REMOVAL_CONFIRMATION_REQUIRED',
      );
    }
    final pending = await _savePending(
      epoch, record, 'PASSKEY_REMOVAL', intent.removalIntentId,
      credentialId: credential,
    );
    if (pending == null || !_current(epoch, record)) return;
    _clearEphemeral();
    _status = SecurityManagementStatus.pending;
    _notify();
    if (!_current(epoch, record)) return;
    final expiry = await _api.removePasskey(
      sessionToken: record.token,
      credentialId: credential,
      removalIntentId: intent.removalIntentId,
      idempotencyKey: pending['key'] as String,
    );
    await _acceptResult(
      epoch, record, pending, CredentialChangeState.committed, expiry,
    );
  });

  Future<void> reconcilePending() => _run((epoch, record) async {
    _clearEphemeral();
    final pending = _store.current!.pendingCredentialChange;
    if (pending == null) {
      await _loadDirectory(epoch, record);
      return;
    }
    if (!_belongs(pending, record)) {
      _status = SecurityManagementStatus.previousSessionPending;
      return;
    }
    if (pending['state'] != 'UNKNOWN') {
      _status = _pendingStatus(pending['state']);
      return;
    }
    await _reconcile(epoch, record, pending);
  });

  Future<void> _reconcile(
    int epoch, SessionRecord record, Map<String, dynamic> pending,
  ) async {
    if (!_current(epoch, record)) return;
    _status = SecurityManagementStatus.pending;
    final outcome = await _api.credentialChangeResult(
      sessionToken: record.token,
      changeId: pending['intentId'] as String,
      idempotencyKey: pending['key'] as String,
    );
    await _acceptResult(
      epoch, record, pending, outcome.state, outcome.sessionExpiresAt,
    );
  }

  Future<Map<String, dynamic>?> _savePending(
    int epoch, SessionRecord record, String kind, String intentId, {
    String? credentialId,
  }) async {
    if (!_current(epoch, record)) return null;
    final pending = <String, dynamic>{
      'v': 1,
      'kind': kind,
      'intentId': intentId,
      'key': AuthCrypto.randomEncoded(32),
      'accountId': record.accountId,
      'originalTokenDigest': sessionTokenDigest(record.token),
      'state': 'UNKNOWN',
      if (credentialId != null) 'credentialId': credentialId,
    };
    var saved = false;
    await _store.update((latest) {
      if (!_current(epoch, record) || latest.session?.token != record.token) {
        return latest;
      }
      if (latest.pendingCredentialChange != null) {
        throw const AuthFailure(
          kind: AuthFailureKind.rejected, code: 'PENDING_CHECK_REQUIRED',
        );
      }
      saved = true;
      return latest.copyWith(pendingCredentialChange: pending);
    });
    return saved && _current(epoch, record) ? pending : null;
  }

  Future<void> _acceptResult(
    int epoch, SessionRecord record, Map<String, dynamic> pending,
    CredentialChangeState outcome, DateTime expiry,
  ) async {
    if (!await _metadata(epoch, record, expiry)) return;
    if (!_current(epoch, record)) return;
    if (_store.current?.pendingCredentialChange?['key'] != pending['key']) return;
    if (outcome == CredentialChangeState.pending) {
      _status = SecurityManagementStatus.pending;
      return;
    }
    final next = Map<String, dynamic>.from(pending)
      ..['state'] = outcome == CredentialChangeState.committed
          ? 'COMMITTED' : 'NOT_COMMITTED';
    var saved = false;
    await _store.update((latest) {
      if (!_current(epoch, record) || latest.session?.token != record.token ||
          latest.pendingCredentialChange?['key'] != pending['key']) return latest;
      saved = true;
      return latest.copyWith(pendingCredentialChange: next);
    });
    if (!saved || !_current(epoch, record)) return;
    _status = outcome == CredentialChangeState.committed
        ? SecurityManagementStatus.committed
        : SecurityManagementStatus.notCommitted;
  }

  Future<bool> _metadata(
    int epoch, SessionRecord record, DateTime? expiresAt,
  ) async {
    if (!_current(epoch, record)) return false;
    if (expiresAt == null || !expiresAt.isUtc) {
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    }
    return _sessions.persistSessionMetadata(
      record.token, expiresAt, () => _current(epoch, record),
    );
  }

  /// Only a known terminal server result may be acknowledged in the ordinary
  /// flow. An unknown operation never turns into success by local dismissal.
  Future<void> acknowledgeResult() => _run((epoch, record) async {
    final pending = _store.current!.pendingCredentialChange;
    if (pending == null ||
        !{'COMMITTED', 'NOT_COMMITTED'}.contains(pending['state'])) return;
    await _clearPending(epoch, record, pending);
    if (_current(epoch, record)) await _loadDirectory(epoch, record);
  });

  /// The UI must ask for explicit acknowledgement that the old outcome remains
  /// unknown. This only drops a local anchor after a session change or server
  /// tombstone; it never resends proof or declares an operation committed.
  Future<void> abandonPending() => _run((epoch, record) async {
    final pending = _store.current!.pendingCredentialChange;
    if (pending == null ||
        (_belongs(pending, record) && pending['state'] != 'EXPIRED')) return;
    await _clearPending(epoch, record, pending);
    if (_current(epoch, record)) await _loadDirectory(epoch, record);
  });

  Future<void> _clearPending(
    int epoch, SessionRecord record, Map<String, dynamic> pending,
  ) => _store.update((latest) {
    if (!_current(epoch, record) ||
        latest.pendingCredentialChange?['key'] != pending['key']) return latest;
    return latest.copyWith(clearPendingCredentialChange: true);
  }).then<void>((_) {});

  void cancelEphemeral() {
    if (_disposed) return;
    _epoch++;
    _cancelOwnedNative();
    _busy = false;
    _clearEphemeral();
    _error = null;
    _errorMessage = null;
    final record = _activeRecord();
    final pending = _store.current?.pendingCredentialChange;
    _status = record == null
        ? SecurityManagementStatus.signedOut
        : pending != null
        ? _belongs(pending, record)
            ? _pendingStatus(pending['state'])
            : SecurityManagementStatus.previousSessionPending
        : SecurityManagementStatus.ready;
    _notify();
  }

  void _cancelOwnedNative() {
    if (_nativeOwnerEpoch == null) return;
    _nativeOwnerEpoch = null;
    final client = _passkey;
    if (client is CancellablePasskeyClient) {
      unawaited(client.cancel().catchError((Object _) {}));
    }
  }

  void _requireNoPending() {
    if (_store.current?.pendingCredentialChange != null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected, code: 'PENDING_CHECK_REQUIRED',
      );
    }
  }

  static bool _belongs(Map<String, dynamic> pending, SessionRecord record) =>
      pending['accountId'] == record.accountId &&
      pending['originalTokenDigest'] == sessionTokenDigest(record.token);

  static SecurityManagementStatus _pendingStatus(Object? state) => switch (state) {
    'COMMITTED' => SecurityManagementStatus.committed,
    'NOT_COMMITTED' => SecurityManagementStatus.notCommitted,
    'EXPIRED' => SecurityManagementStatus.resultExpired,
    _ => SecurityManagementStatus.pending,
  };

  static String _codeDigest(String code) {
    if (code.length > 64 ||
        !RegExp(r'^[A-Za-z2-7 -]+$').hasMatch(code)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'RECOVERY_CODE_CONFIRMATION_FAILED',
      );
    }
    final canonical = code.replaceAll(RegExp(r'[ -]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z2-7]{25}[AEIMQUY4]$').hasMatch(canonical)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'RECOVERY_CODE_CONFIRMATION_FAILED',
      );
    }
    return hashes.sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<void> _run(
    Future<void> Function(int epoch, SessionRecord record) operation,
  ) async {
    if (_busy || _disposed) return;
    final epoch = ++_epoch;
    _busy = true;
    _error = null;
    _errorMessage = null;
    _notify();
    SessionRecord? record;
    try {
      await _store.read();
      if (_disposed || epoch != _epoch) return;
      record = _activeRecord();
      if (record == null) {
        _status = _sessions.status == AuthStatus.unavailable
            ? SecurityManagementStatus.unavailable
            : SecurityManagementStatus.signedOut;
        return;
      }
      _observedToken = record.token;
      await operation(epoch, record);
    } on AuthStorageFailure {
      if (!_disposed && (epoch == _epoch || _store.current == null)) {
        _clearEphemeral();
        _devices = null;
        _credentials = null;
        _status = SecurityManagementStatus.storageFailure;
        _errorMessage = '系统安全存储未能确认写入，请恢复后核对，操作尚未确认。';
      }
    } on AuthFailure catch (failure) {
      if (record == null || !_current(epoch, record)) return;
      _error = failure;
      if (failure.unauthorized) {
        // Fresh password failures do not revoke a valid bearer. Only explicit
        // session errors or an unclassified 401 invalidate current authority.
        if (failure.code != 'AUTHENTICATION_FAILED') {
          _sessions.sessionUnauthorized(record.token, failure.code);
        }
        _errorMessage = failure.code == 'AUTHENTICATION_FAILED'
            ? '密码复验失败，请重新输入密码。' : '会话已失效，请重新登录。';
      } else if (failure.kind == AuthFailureKind.unavailable) {
        _clearEphemeral();
        _devices = null;
        _credentials = null;
        _sessions.sessionUnavailable(record.token);
        _status = SecurityManagementStatus.unavailable;
        _errorMessage = '暂时无法授权此操作，请恢复服务后重新核对。';
      } else if (failure.resultsExpired &&
          _store.current?.pendingCredentialChange != null) {
        final pending = _store.current!.pendingCredentialChange!;
        try {
          await _store.update((latest) {
            if (!_current(epoch, record!) ||
                latest.pendingCredentialChange?['key'] != pending['key']) return latest;
            return latest.copyWith(pendingCredentialChange: {
              ...pending, 'state': 'EXPIRED',
            });
          });
        } on AuthStorageFailure {
          if (!_disposed && _store.current == null) {
            _status = SecurityManagementStatus.storageFailure;
            _errorMessage = '系统安全存储未能确认写入，请恢复后核对原操作。';
          }
          return;
        }
        if (_current(epoch, record)) {
          _status = SecurityManagementStatus.resultExpired;
          _errorMessage = '结果核对记录已过期，不能推断上次操作是否提交。';
        }
      } else {
        if (_store.current?.pendingCredentialChange != null) {
          _status = _pendingStatus(
            _store.current!.pendingCredentialChange!['state'],
          );
        } else if (_status == SecurityManagementStatus.loading) {
          _status = SecurityManagementStatus.ready;
        }
        _errorMessage = failure.uncertain
            ? '提交结果尚未确认，请核对原操作；不会自动重新提交。'
            : failure.code == 'RECOVERY_CODE_CONFIRMATION_FAILED'
            ? '请输入刚保存的新恢复码全文。'
            : '操作未能完成，请核对状态后重试。';
      }
    } on PasskeyFailure catch (failure) {
      if (record != null && _current(epoch, record)) {
        _clearEphemeral();
        _status = SecurityManagementStatus.ready;
        _errorMessage = failure.code == 'PASSKEY_CANCELLED'
            ? '已取消系统 Passkey 操作。'
            : '系统 Passkey 暂不可用，请检查设备支持及关联配置后重试。';
      }
    } on Object {
      if (record != null && _current(epoch, record)) {
        _errorMessage = '操作未能完成，请核对状态后重试。';
        if (_store.current?.pendingCredentialChange != null) {
          _status = SecurityManagementStatus.pending;
        }
      }
    } finally {
      if (!_disposed && epoch == _epoch) _busy = false;
      _notify();
    }
  }

  void _clearEphemeral() {
    _rotation = null;
    _removal = null;
    _rotationDigest = null;
    _recoveryCode = null;
    _removalCredentialId = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _cancelOwnedNative();
    _clearEphemeral();
    _store.removeListener(_authorityChanged);
    _sessions.removeListener(_authorityChanged);
    super.dispose();
  }
}
