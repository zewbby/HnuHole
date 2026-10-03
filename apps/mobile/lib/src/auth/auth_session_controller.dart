import 'dart:async';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart';

import '../navigation/channel_directory_controller.dart';
import 'auth_api.dart';
import 'auth_crypto.dart';
import 'auth_models.dart';
import 'auth_store.dart';

enum AuthStatus {
  starting,
  signedOut,
  restoring,
  authenticated,
  unavailable,
  storageFailure,
  closurePending,
  resetPending,
}

String sessionTokenDigest(String token) => AuthCrypto.encode(
  hashes.sha256.convert(AuthCrypto.decode(token, bytes: 32)).bytes,
);

/// Local expiry is display metadata. Only C can establish whether a session or
/// revocation capability is still active, including an unknown prior renewal.
class AuthSessionController extends ChangeNotifier {
  AuthSessionController({
    required AuthApi api,
    required AuthStore store,
    required ChannelDirectoryController directory,
  }) : _api = api, _store = store, _directory = directory {
    _store.addListener(_storeChanged);
    _directory.onSessionUnauthorized = _directoryUnauthorized;
    _directory.onSessionRetry = retry;
    _directory.onSessionMetadata = _persistDirectoryExpiry;
  }
  final AuthApi _api;
  final AuthStore _store;
  final ChannelDirectoryController _directory;
  AuthStatus _status = AuthStatus.starting;
  CurrentSession? _currentSession;
  String? _error;
  bool _busy = false, _disposed = false;
  Future<void>? _logoutRetry;
  int _operation = 0;
  String? _authorizedToken;
  AuthStatus get status => _status;
  bool get busy => _busy;
  String? get errorMessage => _error;
  String? get error => _error;
  CurrentSession? get currentSession => _currentSession;
  String? get username => _currentSession?.username;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _authorizedToken != null;
  bool get hasPendingLogout => _store.current?.logouts.isNotEmpty ?? false;
  int get authorityVersion => _operation;

  bool isCurrentToken(String token) =>
      !_disposed && isAuthenticated && _authorizedToken == token &&
      _usable(_store.current ?? const AuthState())?.token == token;

  void sessionUnauthorized(String token, String? code) =>
      _directoryUnauthorized(token, code);

  Future<bool> persistSessionMetadata(
    String token, DateTime expiresAt, bool Function() isCurrent,
  ) => _persistDirectoryExpiry(token, expiresAt, isCurrent);

  /// A protected management read cannot leave prior community data exposed
  /// after the service reports that authorization is unavailable.
  void sessionUnavailable(String token) {
    if (!isCurrentToken(token)) return;
    _operation++;
    _suspend();
    _status = AuthStatus.unavailable;
    _error = '暂时无法核对会话，请恢复服务后重试。';
    _notify();
  }

  SessionRecord? _usable(AuthState state) {
    final record = state.session;
    if (record == null) return null;
    final hash = sessionTokenDigest(record.token);
    if (state.logouts.any((task) => task.tokenDigest == hash)) return null;
    final closure = state.pendingClosure;
    if (closure != null &&
        closure['state'] == 'UNKNOWN' &&
        (closure['originalBearer'] == record.token ||
            closure['originalTokenDigest'] == hash)) {
      return null;
    }
    final reset = state.pendingReset;
    if (reset != null &&
        (reset['state'] == 'UNKNOWN' || reset['state'] == 'EXPIRED') &&
        (reset['originalTokenDigest'] == hash ||
            record.approvedPendingResetId != reset['intentId'])) {
      return null;
    }
    return record;
  }

  AuthStatus _emptyStatus(AuthState state) {
    if (state.pendingClosure != null) return AuthStatus.closurePending;
    if (state.pendingReset != null) return AuthStatus.resetPending;
    return AuthStatus.signedOut;
  }

  void _storeChanged() {
    if (_disposed) return;
    final state = _store.current;
    if (state == null) {
      _operation++;
      _suspend();
      _status = AuthStatus.storageFailure;
      _error = '系统安全存储不可用，请恢复后重试。';
      _notify();
      return;
    }
    final usable = _usable(state);
    if (_authorizedToken != null && usable?.token != _authorizedToken) {
      _operation++;
      _clear();
      _status = _emptyStatus(state);
      _notify();
    }
  }

  void _clear() {
    _authorizedToken = null;
    _currentSession = null;
    _directory.signOut();
  }

  void _suspend() {
    _authorizedToken = null;
    _currentSession = null;
    _directory.suspend();
  }

  void clearCommunityAccess() {
    final state = _store.current;
    if (state == null || _usable(state) == null) {
      _operation++;
      _clear();
      _status = state == null ? AuthStatus.storageFailure : _emptyStatus(state);
      _notify();
    }
  }

  Future<void> start() async {
    if (_busy) return;
    final operation = ++_operation;
    _busy = true;
    _status = AuthStatus.restoring;
    _error = null;
    _suspend();
    _notify();
    try {
      await _store.read();
      await _convertLogoutMarkers();
      unawaited(retryPendingLogout());
      final state = await _store.read();
      final record = _usable(state);
      if (operation != _operation && _status == AuthStatus.storageFailure) {
        return;
      }
      if (record == null) {
        _clear();
        _status = _emptyStatus(state);
        return;
      }
      // Store transitions during logout conversion can invalidate older work;
      // start a fresh fence after they are durably complete.
      final fence = ++_operation;
      await _restore(record, fence);
    } on AuthStorageFailure {
      _suspend();
      _status = AuthStatus.storageFailure;
      _error = '系统安全存储不可用，不能恢复社区会话。';
    } on Object {
      _suspend();
      _status = AuthStatus.unavailable;
      _error = '暂时无法确认会话，请重试。';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> retry() => start();
  Future<void> _restore(SessionRecord record, int fence) async {
    try {
      final view = await _api.currentSession(record.token);
      if (_disposed ||
          fence != _operation ||
          _usable(_store.current ?? const AuthState())?.token != record.token) {
        return;
      }
      if (view.accountId != record.accountId) {
        throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
      }
      await _store.update(
        (s) => s.session?.token == record.token
            ? s.copyWith(
                session: SessionRecord(
                  token: record.token,
                  accountId: view.accountId,
                  expiresAt: view.expiresAt,
                  approvedPendingResetId: record.approvedPendingResetId,
                ),
              )
            : s,
      );
      if (fence != _operation ||
          _usable(_store.current ?? const AuthState())?.token != record.token) {
        return;
      }
      _currentSession = view;
      _authorizedToken = record.token;
      _status = AuthStatus.authenticated;
      _error = null;
      _notify();
      await _directory.authenticate(record.token);
    } on AuthFailure catch (e) {
      if (_disposed || fence != _operation) return;
      if (e.unauthorized) {
        await _forgetToken(record.token);
        _error = e.code == 'session_replaced'
            ? '此设备的会话已被新设备接替，请重新登录。'
            : '会话已失效，请重新登录。';
      } else {
        _suspend();
        _status = AuthStatus.unavailable;
        _error = '暂时无法确认会话，已保留安全存储中的令牌。';
      }
    }
  }

  /// The local clock only schedules a renewal; C supplies its authority and
  /// expiry. No local timer can extend or resurrect a session.
  Future<void> onActivity() async {
    unawaited(retryPendingLogout());
    if (_busy || !isAuthenticated) return;
    final record = _usable(_store.current ?? const AuthState());
    if (record == null ||
        record.expiresAt.difference(DateTime.now().toUtc()) >
            const Duration(days: 7)) {
      return;
    }
    final fence = ++_operation;
    _busy = true;
    try {
      final expiry = await _api.renewSession(record.token);
      if (_disposed ||
          fence != _operation ||
          _usable(_store.current ?? const AuthState())?.token != record.token) {
        return;
      }
      await _store.update(
        (s) => s.session?.token == record.token
            ? s.copyWith(
                session: SessionRecord(
                  token: record.token,
                  accountId: record.accountId,
                  expiresAt: expiry,
                  approvedPendingResetId: record.approvedPendingResetId,
                ),
              )
            : s,
      );
      if (fence != _operation) return;
      _currentSession = CurrentSession(
        accountId: record.accountId,
        username: _currentSession!.username,
        expiresAt: expiry,
      );
    } on AuthFailure catch (e) {
      if (_disposed || fence != _operation) return;
      if (e.unauthorized) {
        await _forgetToken(record.token);
        _error = '会话已失效，请重新登录。';
      } else {
        _suspend();
        _status = AuthStatus.unavailable;
        _error = '续期结果待确认，请重试恢复会话。';
      }
    } on AuthStorageFailure {
      _suspend();
      _status = AuthStatus.storageFailure;
      _error = '安全存储不可用，请恢复后核对会话。';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> login(String username, String password) async {
    if (_busy) return;
    final fence = ++_operation;
    _suspend();
    _busy = true;
    _error = null;
    _notify();
    try {
      await _convertLogoutMarkers();
      var state = await _store.read();
      if (state.cInstallationId == null) {
        state = await _store.update(
          (s) => s.copyWith(cInstallationId: AuthCrypto.randomEncoded(16)),
        );
      }
      final result = await _api.login(
        username: username,
        password: password,
        installationId: state.cInstallationId!,
        idempotencyKey: AuthCrypto.randomEncoded(32),
      );
      if (_disposed || fence != _operation) {
        await _queueOrphan(result.sessionToken);
        return;
      }
      await _saveSession(result, explicitLogin: true);
      final record = _store.current!.session!;
      await _restore(record, ++_operation);
    } on AuthStorageFailure {
      _clear();
      _status = AuthStatus.storageFailure;
      _error = '安全存储写入失败，不能确认本机登录。';
    } on AuthFailure catch (e) {
      _error = e.unauthorized
          ? '用户名或密码不正确。'
          : e.code == 'SESSION_CREATED_RETRY_LOGIN'
          ? '上次登录已建立会话，请主动重新登录。'
          : '登录结果暂时无法确认，请主动重试。';
    } on Object {
      _error = '登录暂时不可用，请重试。';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> acceptSession(AuthSession session) async {
    _operation++;
    _suspend();
    final state = await _store.read();
    if (state.pendingClosure != null || state.pendingReset != null) {
      await _queueOrphan(session.sessionToken);
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'LOCAL_OPERATION_PENDING',
      );
    }
    await _saveSession(session, explicitLogin: false);
    await _restore(_store.current!.session!, ++_operation);
  }

  Future<void> _saveSession(
    AuthSession session, {
    required bool explicitLogin,
  }) async {
    await _store.update(
      (s) => s.copyWith(
        session: SessionRecord(
          token: session.sessionToken,
          accountId: session.accountId,
          expiresAt: session.expiresAt,
          approvedPendingResetId: explicitLogin
              ? (s.pendingReset?['intentId'] as String?)
              : null,
        ),
      ),
    );
  }

  Future<void> _queueOrphan(String token) async {
    final hash = sessionTokenDigest(token),
        secret = AuthCrypto.revocationSecret(token);
    await _store.update(
      (s) => s.copyWith(
        logouts: [
          ...s.logouts.where((e) => e.tokenDigest != hash),
          LogoutTask(tokenDigest: hash, revocationSecret: secret),
        ],
      ),
    );
  }

  Future<void> logout() async {
    if (_busy) return;
    _operation++;
    _suspend();
    _busy = true;
    _error = null;
    _notify();
    try {
      final state = await _store.read();
      final token = state.session?.token;
      if (token != null) {
        final hash = sessionTokenDigest(token);
        // Phase one is the required durable marker. Failure here never reports
        // logout success; a later startup first reconciles any unknown write.
        await _store.update(
          (s) => s.copyWith(
            logouts: [
              ...s.logouts.where((e) => e.tokenDigest != hash),
              LogoutTask(tokenDigest: hash),
            ],
          ),
        );
      }
      await _convertLogoutMarkers();
      _clear();
      _status = AuthStatus.signedOut;
      await retryPendingLogout();
      _error = hasPendingLogout ? '本地已退出，服务器撤销待确认。' : null;
    } on AuthStorageFailure {
      _clear();
      _status = AuthStatus.storageFailure;
      _error = '退出待办未能完成持久写入，不能确认退出成功。';
    } on Object {
      _clear();
      _status = AuthStatus.storageFailure;
      _error = '退出状态需要安全核对，请重试。';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _convertLogoutMarkers() async {
    final state = await _store.read();
    if (!state.logouts.any((e) => e.revocationSecret == null)) return;
    await _store.update((s) {
      var session = s.session;
      final converted = <LogoutTask>[];
      for (final task in s.logouts) {
        if (task.revocationSecret != null) {
          converted.add(task);
          continue;
        }
        if (session == null ||
            sessionTokenDigest(session.token) != task.tokenDigest) {
          throw const AuthStorageFailure();
        }
        converted.add(
          LogoutTask(
            tokenDigest: task.tokenDigest,
            revocationSecret: AuthCrypto.revocationSecret(session.token),
          ),
        );
        session = null;
      }
      return s.copyWith(
        session: session,
        clearSession: session == null,
        logouts: converted,
      );
    });
  }

  /// Independent capabilities retry without delaying another session's
  /// restoration. One drain runs at a time; foreground activity resumes it.
  Future<void> retryPendingLogout() {
    if (_disposed || _store.current?.logouts.isEmpty == true) {
      return Future<void>.value();
    }
    if (_logoutRetry != null) return _logoutRetry!;
    final future = _drainLogoutTasks()
        .catchError((Object _) {
          // AuthStore itself invalidates authority on an unknown storage failure.
          // Network/unknown outcomes keep the original independent capability.
        })
        .whenComplete(() {
          _logoutRetry = null;
          _notify();
        });
    _logoutRetry = future;
    return future;
  }

  Future<void> _drainLogoutTasks() async {
    final tasks = (await _store.read()).logouts;
    for (final task in tasks) {
      if (task.revocationSecret == null) throw const AuthStorageFailure();
      try {
        await _api.revokeSession(task.revocationSecret!);
        await _store.update(
          (s) => s.copyWith(
            logouts: s.logouts
                .where((e) => e.tokenDigest != task.tokenDigest)
                .toList(),
          ),
        );
      } on AuthFailure {
        /* Unknown means keep this exact capability for retry. */
      }
    }
  }

  Future<void> _forgetToken(String token) async {
    await _store.update(
      (s) => s.session?.token == token ? s.copyWith(clearSession: true) : s,
    );
    if (_authorizedToken == token || _authorizedToken == null) {
      _clear();
      _status = _emptyStatus(_store.current ?? const AuthState());
      _notify();
    }
  }

  void _directoryUnauthorized(String token, String? code) {
    if (token != _authorizedToken) return;
    _operation++;
    _clear();
    _status = AuthStatus.signedOut;
    _error = code == 'session_replaced'
        ? '此设备的会话已被新设备接替，请重新登录。'
        : '会话已失效，请重新登录。';
    _notify();
    _forgetToken(token).catchError((Object _) {
      _status = AuthStatus.storageFailure;
      _notify();
    });
  }

  Future<bool> _persistDirectoryExpiry(
    String token,
    DateTime expiresAt,
    bool Function() isCurrent,
  ) async {
    final fence = _operation;
    bool permitted() =>
        !_disposed &&
        fence == _operation &&
        isCurrent() &&
        _authorizedToken == token &&
        _usable(_store.current ?? const AuthState())?.token == token;
    if (!permitted()) return false;
    var changed = false;
    final state = await _store.update((s) {
      final record = _usable(s);
      if (record == null || record.token != token || !permitted()) return s;
      changed = true;
      // A response committed earlier may arrive after a concurrent renewal.
      final deadline = record.expiresAt.isAfter(expiresAt)
          ? record.expiresAt
          : expiresAt;
      return s.copyWith(
        session: SessionRecord(
          token: token,
          accountId: record.accountId,
          expiresAt: deadline,
          approvedPendingResetId: record.approvedPendingResetId,
        ),
      );
    });
    if (!changed || !permitted()) return false;
    final view = _currentSession;
    if (view == null) return false;
    _currentSession = CurrentSession(
      accountId: view.accountId,
      username: view.username,
      expiresAt: state.session!.expiresAt,
    );
    _notify();
    return permitted();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    _store.removeListener(_storeChanged);
    _directory.onSessionUnauthorized = null;
    _directory.onSessionRetry = null;
    _directory.onSessionMetadata = null;
    super.dispose();
  }
}
