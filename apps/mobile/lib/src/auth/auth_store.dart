import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';

import 'auth_crypto.dart';
import 'auth_state_codec.dart';

class AuthStorageFailure implements Exception {
  const AuthStorageFailure();
  @override
  String toString() => 'System authentication storage is unavailable';
}

/// The platform adapter must replace one value atomically and acknowledge its
/// durable write. No filesystem, preferences or in-memory fallback is allowed.
abstract interface class AuthVault {
  Future<String?> read();
  Future<void> write(String value);
}

class FlutterAuthVault implements AuthVault {
  FlutterAuthVault({String namespace = 'hnuhole.auth.v1'})
    : _storage = DurableAuthVault(namespace);
  final DurableAuthVault _storage;
  void _platform() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const AuthStorageFailure();
    }
  }

  @override
  Future<String?> read() async {
    _platform();
    return _storage.read();
  }

  @override
  Future<void> write(String value) async {
    _platform();
    await _storage.write(value);
  }
}

class SessionRecord {
  const SessionRecord({
    required this.token,
    required this.accountId,
    required this.expiresAt,
    this.approvedPendingResetId,
  });
  final String token;
  final String accountId;
  final DateTime expiresAt;
  // Only explicit password login can grant access while an older reset outcome
  // remains unknown. Startup never creates this permission on its own.
  final String? approvedPendingResetId;
  Map<String, dynamic> toJson() => {
    'token': token,
    'accountId': accountId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (approvedPendingResetId != null)
      'approvedPendingResetId': approvedPendingResetId,
  };
  static SessionRecord parse(Map<String, dynamic> m) {
    _fields(m, {'token', 'accountId', 'expiresAt', 'approvedPendingResetId'});
    final token = _string(m, 'token');
    AuthCrypto.decode(token, bytes: 32);
    final account = _string(m, 'accountId');
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(account)) {
      throw const FormatException('Invalid account record');
    }
    final expiry = _string(m, 'expiresAt');
    final at = DateTime.parse(expiry);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
            .hasMatch(expiry) ||
        !at.isUtc ||
        at.toIso8601String().substring(0, 19) != expiry.substring(0, 19)) {
      throw const FormatException('Invalid expiry record');
    }
    final approved = m['approvedPendingResetId'];
    if (approved != null) {
      if (approved is! String) {
        throw const FormatException('Invalid pending permission');
      }
      AuthCrypto.decode(approved, bytes: 32);
    }
    return SessionRecord(
      token: token,
      accountId: account,
      expiresAt: at,
      approvedPendingResetId: approved as String?,
    );
  }
}

class LogoutTask {
  const LogoutTask({required this.tokenDigest, this.revocationSecret});
  final String tokenDigest;
  final String? revocationSecret;
  Map<String, dynamic> toJson() => {
    'tokenDigest': tokenDigest,
    'revocationSecret': revocationSecret,
  };
  static LogoutTask parse(Map<String, dynamic> m) {
    _fields(m, {'tokenDigest', 'revocationSecret'});
    final hash = _string(m, 'tokenDigest');
    AuthCrypto.decode(hash, bytes: 32);
    final secret = m['revocationSecret'];
    if (secret != null) {
      if (secret is! String) {
        throw const FormatException('Invalid logout record');
      }
      AuthCrypto.decode(secret, bytes: 32);
    }
    return LogoutTask(tokenDigest: hash, revocationSecret: secret as String?);
  }
}

class AuthState {
  const AuthState({
    this.session,
    this.logouts = const [],
    this.registration,
    this.pendingReset,
    this.pendingClosure,
    this.cInstallationId,
    this.vInstallationId,
  });
  final SessionRecord? session;
  final List<LogoutTask> logouts;
  final Map<String, dynamic>? registration, pendingReset, pendingClosure;
  final String? cInstallationId, vInstallationId;
  AuthState copyWith({
    SessionRecord? session,
    bool clearSession = false,
    List<LogoutTask>? logouts,
    Map<String, dynamic>? registration,
    bool clearRegistration = false,
    Map<String, dynamic>? pendingReset,
    bool clearPendingReset = false,
    Map<String, dynamic>? pendingClosure,
    bool clearPendingClosure = false,
    String? cInstallationId,
    String? vInstallationId,
  }) => AuthState(
    session: clearSession ? null : session ?? this.session,
    logouts: logouts ?? this.logouts,
    registration: clearRegistration ? null : registration ?? this.registration,
    pendingReset: clearPendingReset ? null : pendingReset ?? this.pendingReset,
    pendingClosure: clearPendingClosure
        ? null
        : pendingClosure ?? this.pendingClosure,
    cInstallationId: cInstallationId ?? this.cInstallationId,
    vInstallationId: vInstallationId ?? this.vInstallationId,
  );
  Map<String, dynamic> toJson(String scope) => {
    'schema': 1,
    'scope': scope,
    'session': session?.toJson(),
    'logouts': logouts.map((e) => e.toJson()).toList(),
    'registration': registration,
    'pendingReset': pendingReset,
    'pendingClosure': pendingClosure,
    'cInstallationId': cInstallationId,
    'vInstallationId': vInstallationId,
  };
  static AuthState parse(Map<String, dynamic> m, String scope) {
    _fields(m, {
      'schema',
      'scope',
      'session',
      'logouts',
      'registration',
      'pendingReset',
      'pendingClosure',
      'cInstallationId',
      'vInstallationId',
    });
    if (m['schema'] is! int || m['schema'] != 1 || m['scope'] != scope) {
      throw const FormatException('Invalid authentication storage scope');
    }
    final logout = m['logouts'];
    if (logout is! List || logout.length > 64) {
      throw const FormatException('Invalid logout records');
    }
    final tasks = logout
        .map((e) => LogoutTask.parse(_object(e)))
        .toList(growable: false);
    if (tasks.map((e) => e.tokenDigest).toSet().length != tasks.length) {
      throw const FormatException('Duplicate logout records');
    }
    String? installation(String key) {
      final v = m[key];
      if (v == null) return null;
      if (v is! String) {
        throw const FormatException('Invalid installation record');
      }
      AuthCrypto.decode(v, bytes: 16);
      return v;
    }

    final c = installation('cInstallationId'),
        v = installation('vInstallationId');
    if (c != null && c == v) {
      throw const FormatException('Service installations must be independent');
    }
    final registration = _optionalObject(m['registration']);
    final pendingReset = _optionalObject(m['pendingReset']);
    final pendingClosure = _optionalObject(m['pendingClosure']);
    AuthWorkflowCodec.validate(
      registration: registration,
      pendingReset: pendingReset,
      pendingClosure: pendingClosure,
      cInstallationId: c,
      vInstallationId: v,
    );
    return AuthState(
      session: m['session'] == null
          ? null
          : SessionRecord.parse(_object(m['session'])),
      logouts: List.unmodifiable(tasks),
      registration: _frozenMap(registration),
      pendingReset: _frozenMap(pendingReset),
      pendingClosure: _frozenMap(pendingClosure),
      cInstallationId: c,
      vInstallationId: v,
    );
  }
}

/// All owners share this queue and one platform value. Cache changes and UI
/// notifications happen only after a verified write; unknown writes invalidate
/// the cache and prohibit community use until a fresh read reconciles it.
class AuthStore extends ChangeNotifier {
  AuthStore(this._vault, {this.scope = 'hnuhole.isolated.auth.v1'});
  final AuthVault _vault;
  final String scope;
  Future<void> _tail = Future<void>.value();
  AuthState? _current;
  AuthState? get current => _current;
  bool _disposed = false;
  Future<T> _serial<T>(Future<T> Function() work) {
    final future = _tail.then((_) => work());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  Future<AuthState> _read() async {
    try {
      final raw = await _vault.read();
      if (raw != null && utf8.encode(raw).length > 65536) {
        throw const FormatException('Oversized authentication record');
      }
      final value = raw == null
          ? const AuthState()
          : AuthState.parse(_object(jsonDecode(raw)), scope);
      _current = value;
      return value;
    } on Object {
      _current = null;
      _notify();
      throw const AuthStorageFailure();
    }
  }

  Future<AuthState> read() => _serial(_read);
  Future<AuthState> update(AuthState Function(AuthState) change) =>
      _serial(() async {
        final old = await _read();
        try {
          final raw = jsonEncode(change(old).toJson(scope));
          if (utf8.encode(raw).length > 65536) {
            throw const FormatException('Oversized authentication record');
          }
          final verified = AuthState.parse(_object(jsonDecode(raw)), scope);
          await _vault.write(raw);
          if (await _vault.read() != raw) {
            throw const AuthStorageFailure();
          }
          _current = verified;
          _notify();
          return verified;
        } on Object {
          _current = null;
          _notify();
          throw const AuthStorageFailure();
        }
      });
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Map<String, dynamic> _object(Object? v) {
  if (v is! Map<String, dynamic>) {
    throw const FormatException('Invalid authentication record');
  }
  return v;
}

Map<String, dynamic>? _optionalObject(Object? v) =>
    v == null ? null : _object(v);
String _string(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is! String || v.isEmpty) {
    throw const FormatException('Invalid authentication record');
  }
  return v;
}

void _fields(Map<String, dynamic> m, Set<String> allowed) {
  if (m.keys.any((k) => !allowed.contains(k))) {
    throw const FormatException('Unsupported authentication record');
  }
}

Map<String, dynamic>? _frozenMap(Map<String, dynamic>? value) => value == null
    ? null
    : Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key, _freeze(item))),
      );
Object? _freeze(Object? value) => value is Map<String, dynamic>
    ? _frozenMap(value)
    : value is List
    ? List<Object?>.unmodifiable(value.map(_freeze))
    : value;
