import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../auth/auth_crypto.dart';
import '../auth/auth_models.dart';
import '../auth/auth_session_controller.dart';
import '../auth/auth_store.dart';
import 'identity_api.dart';
import 'identity_name_formatter.dart';

enum IdentityManagementStatus {
  idle,
  loading,
  ready,
  pending,
  retryRequired,
  signedOut,
  storageFailure,
  unavailable,
}

/// An immutable, owner-scoped intent is durable before transmission. A missing
/// receipt never proves the original request cannot still arrive: all retries
/// query first and reuse the exact original key, resource and nickname.
class IdentityManagementController extends ChangeNotifier {
  IdentityManagementController({
    required this._api,
    required this._store,
    required AuthSessionController sessions,
  }) : _sessions = sessions {
    _observedAuthority = sessions.authorityVersion;
    _observedToken = _active()?.token;
    _store.addListener(_authorityChanged);
    _sessions.addListener(_authorityChanged);
  }
  final IdentityApi _api;
  final AuthStore _store;
  final AuthSessionController _sessions;
  IdentityDirectory? _directory;
  IdentityManagementStatus _status = IdentityManagementStatus.idle;
  String? _message, _observedToken;
  AuthFailure? _error;
  int _epoch = 0, _observedAuthority = 0;
  bool _busy = false, _disposed = false, _entryReady = false;
  IdentityDirectory? get directory => _directory;
  IdentityManagementStatus get status => _status;
  String? get errorMessage => _message;
  AuthFailure? get error => _error;
  bool get busy => _busy;
  Object? get authorityKey {
    final active = _active();
    return active == null
        ? null
        : (active.accountId, active.token, _sessions.authorityVersion);
  }

  bool get entryReady => _entryReady && authorityKey != null;
  bool get hasPending => _pending(_active()) != null;
  Map<String, dynamic>? get pendingAvatar {
    final record = _active();
    final draft = record == null
        ? null
        : _store.current?.identityDrafts[record.accountId];
    return draft is Map<String, dynamic> &&
            draft['username'] == _sessions.username
        ? draft['upload'] as Map<String, dynamic>?
        : null;
  }

  Uint8List? _uploadBytes;
  String? _uploadAsset;
  String get initialNickname {
    final record = _active();
    final draft = record == null
        ? null
        : _store.current?.identityDrafts[record.accountId];
    return draft is Map<String, dynamic> &&
            draft['username'] == _sessions.username
        ? draft['nickname'] as String
        : '';
  }

  String get initialAvatar {
    final record = _active();
    final draft = record == null
        ? null
        : _store.current?.identityDrafts[record.accountId];
    return draft is Map<String, dynamic> &&
            draft['username'] == _sessions.username
        ? draft['avatar'] as String? ?? 'default-v1'
        : 'default-v1';
  }

  Future<String?> uploadAvatar(
    String assetId,
    Uint8List bytes,
    String mime, {
    String target = 'CREATE',
  }) async {
    String? uploaded;
    await _run((epoch, authority, record) async {
      if (_api is! IdentityAvatarApi || hasPending) return;
      if (pendingAvatar != null) {
        await _abandonAvatar(epoch, authority, record);
        if (!_current(epoch, authority, record)) return;
      }
      final digest = AuthCrypto.encode(sha256.convert(bytes).bytes);
      await _writeUpload(epoch, authority, record, {
        'assetId': assetId,
        'digest': digest,
        'mime': mime,
        'target': target,
      });
      if (!_current(epoch, authority, record)) return;
      _uploadBytes = Uint8List.fromList(bytes);
      _uploadAsset = assetId;
      final result = await (_api as IdentityAvatarApi).uploadIdentityAvatar(
        sessionToken: record.token,
        assetId: assetId,
        bytes: bytes,
        mime: mime,
      );
      if (!await _metadata(epoch, authority, record, result.sessionExpiresAt) ||
          !_current(epoch, authority, record)) {
        return;
      }
      if (result.avatar != 'avatar-v1:$assetId') {
        throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
      }
      uploaded = result.avatar;
    }, preserveDirectoryOnFailure: true);
    return uploaded;
  }

  Future<String?> recoverAvatar({
    required String target,
    bool retry = false,
  }) async {
    String? recovered;
    await _run((epoch, authority, record) async {
      final pending = pendingAvatar;
      if (_api is! IdentityAvatarApi ||
          pending == null ||
          pending['target'] != target ||
          hasPending) {
        return;
      }
      final avatar = 'avatar-v1:${pending['assetId']}';
      IdentityAvatarResult result;
      try {
        result = await (_api as IdentityAvatarApi).readIdentityAvatar(
          sessionToken: record.token,
          avatar: avatar,
        );
      } on AuthFailure catch (failure) {
        if (failure.code != 'IDENTITY_AVATAR_NOT_FOUND' ||
            !retry ||
            _uploadAsset != pending['assetId'] ||
            _uploadBytes == null) {
          rethrow;
        }
        result = await (_api as IdentityAvatarApi).uploadIdentityAvatar(
          sessionToken: record.token,
          assetId: pending['assetId'] as String,
          bytes: _uploadBytes!,
          mime: pending['mime'] as String,
        );
      }
      if (await _metadata(epoch, authority, record, result.sessionExpiresAt) &&
          _current(epoch, authority, record)) {
        recovered = avatar;
      }
    }, preserveDirectoryOnFailure: true);
    return recovered;
  }

  Future<bool> abandonAvatar() async {
    var done = false;
    await _run((epoch, authority, record) async {
      if (hasPending) return;
      await _abandonAvatar(epoch, authority, record);
      done = _current(epoch, authority, record);
    }, preserveDirectoryOnFailure: true);
    return done;
  }

  Future<void> _abandonAvatar(
    int epoch,
    int authority,
    SessionRecord record,
  ) async {
    final pending = pendingAvatar;
    if (pending == null) return;
    final expiry = await (_api as IdentityAvatarApi).abandonIdentityAvatar(
      sessionToken: record.token,
      avatar: 'avatar-v1:${pending['assetId']}',
    );
    if (!await _metadata(epoch, authority, record, expiry)) return;
    await _writeUpload(epoch, authority, record, null);
    _uploadBytes = null;
    _uploadAsset = null;
  }

  Future<void> _writeUpload(
    int epoch,
    int authority,
    SessionRecord record,
    Map<String, dynamic>? upload,
  ) async {
    await _store.update((latest) {
      if (!_current(epoch, authority, record)) return latest;
      final prior = latest.identityDrafts[record.accountId];
      final draft = <String, dynamic>{
        'v': 1,
        'username': _sessions.username!,
        'nickname': '',
        if (prior is Map<String, dynamic> &&
            prior['username'] == _sessions.username)
          ...prior,
      };
      if (upload == null) {
        draft.remove('upload');
        if (draft['avatar'] is String &&
            (draft['avatar'] as String).startsWith('avatar-v1:')) {
          draft['avatar'] = 'default-v1';
        }
      } else {
        draft['upload'] = upload;
      }
      return latest.copyWith(
        identityDrafts: {...latest.identityDrafts, record.accountId: draft},
      );
    });
  }

  /// Save only committed legal IME input for first setup. The owner and current
  /// authority are rechecked inside the shared store queue; logout does not erase
  /// another account's draft or apply a delayed write to a replacement session.
  Future<bool> saveInitialDraft(String nickname, {String? avatar}) async {
    final record = _active(), authority = _sessions.authorityVersion;
    final username = _sessions.username;
    if (_disposed ||
        record == null ||
        username == null ||
        hasPending ||
        _directory?.identities.isEmpty != true ||
        IdentityNameFormatter.filterCharacters(nickname) != nickname ||
        utf8.encode(nickname).length > 512 ||
        avatar != null && !validIdentityAvatar(avatar)) {
      return false;
    }
    var saved = false;
    try {
      await _store.update((latest) {
        if (_disposed ||
            authority != _sessions.authorityVersion ||
            _active()?.token != record.token ||
            _active()?.accountId != record.accountId ||
            _sessions.username != username ||
            latest.identityChanges.containsKey(record.accountId)) {
          return latest;
        }
        saved = true;
        return latest.copyWith(
          identityDrafts: {
            ...latest.identityDrafts,
            record.accountId: {
              'v': 1,
              'username': username,
              'nickname': nickname,
              'avatar': avatar ?? initialAvatar,
              if (pendingAvatar != null) 'upload': pendingAvatar,
            },
          },
        );
      });
      return saved;
    } on AuthStorageFailure {
      if (!_disposed && _store.current == null) {
        _directory = null;
        _status = IdentityManagementStatus.storageFailure;
        _message = '昵称草稿尚未确认保存，请恢复安全存储后重试。';
        _notify();
      }
      return false;
    }
  }

  Future<bool> discardInitialDraft() async {
    final record = _active(), authority = _sessions.authorityVersion;
    if (_disposed || record == null || hasPending) return false;
    if (pendingAvatar != null && !await abandonAvatar()) return false;
    var saved = false;
    try {
      await _store.update((latest) {
        if (_disposed ||
            authority != _sessions.authorityVersion ||
            _active()?.token != record.token ||
            _active()?.accountId != record.accountId ||
            latest.identityChanges.containsKey(record.accountId)) {
          return latest;
        }
        final drafts = Map<String, dynamic>.from(latest.identityDrafts)
          ..remove(record.accountId);
        saved = true;
        return latest.copyWith(identityDrafts: drafts);
      });
      return saved;
    } on AuthStorageFailure {
      if (!_disposed && _store.current == null) {
        _status = IdentityManagementStatus.storageFailure;
        _message = '尚未确认放弃昵称草稿，请恢复后重新核对。';
        _notify();
      }
      return false;
    }
  }

  SessionRecord? _active() {
    final record = _store.current?.session;
    return record != null &&
            _sessions.isCurrentToken(record.token) &&
            _sessions.username != null
        ? record
        : null;
  }

  Map<String, dynamic>? _pending(SessionRecord? record) {
    if (record == null) return null;
    final value = _store.current?.identityChanges[record.accountId];
    if (value is! Map<String, dynamic> ||
        value['username'] != _sessions.username) {
      return null;
    }
    return value;
  }

  bool _current(int epoch, int authority, SessionRecord record) =>
      !_disposed &&
      epoch == _epoch &&
      authority == _sessions.authorityVersion &&
      _active()?.token == record.token &&
      _active()?.accountId == record.accountId;

  void _authorityChanged() {
    if (_disposed) return;
    final active = _active();
    if (_store.current == null ||
        active?.token != _observedToken ||
        _observedAuthority != _sessions.authorityVersion) {
      _epoch++;
      _entryReady = false;
      _uploadBytes = null;
      _uploadAsset = null;
      _observedToken = active?.token;
      _observedAuthority = _sessions.authorityVersion;
      _busy = false;
      _directory = null;
      _message = null;
      _error = null;
      _status = _store.current == null
          ? IdentityManagementStatus.storageFailure
          : _sessions.status == AuthStatus.unavailable
          ? IdentityManagementStatus.unavailable
          : active == null
          ? IdentityManagementStatus.signedOut
          : IdentityManagementStatus.idle;
      _notify();
    }
  }

  Future<void> load() => _run((epoch, authority, record) async {
    _directory = null;
    _status = IdentityManagementStatus.loading;
    _notify();
    final pending = _pending(record);
    if (pending == null || pending['state'] == 'COMMITTED') {
      await _loadDirectory(epoch, authority, record, pending);
    } else {
      if (!_entryReady) {
        final directory = await _api.identities(record.token);
        if (!await _metadata(
              epoch,
              authority,
              record,
              directory.sessionExpiresAt,
            ) ||
            !_current(epoch, authority, record)) {
          return;
        }
        _entryReady = directory.identities.isNotEmpty;
        _notify();
      }
      await _reconcile(epoch, authority, record, pending);
    }
  });

  Future<void> create(String nickname, {String? avatar}) =>
      _change(IdentityOperation.create, nickname: nickname, avatar: avatar);
  Future<void> rename(String identityId, String nickname, {String? avatar}) =>
      _change(
        IdentityOperation.rename,
        identityId: identityId,
        nickname: nickname,
        avatar: avatar,
      );
  Future<void> changeAvatar(String identityId, String avatar) =>
      _change(IdentityOperation.avatar, identityId: identityId, avatar: avatar);
  Future<void> delete(String identityId) =>
      _change(IdentityOperation.delete, identityId: identityId);

  Future<void> _change(
    IdentityOperation operation, {
    String? identityId,
    String? nickname,
    String? avatar,
  }) => _run((epoch, authority, record) async {
    if (_store.current!.identityChanges.containsKey(record.accountId)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'PENDING_CHECK_REQUIRED',
      );
    }
    if (nickname != null && IdentityNameFormatter.validate(nickname) != null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'IDENTITY_INVALID_NAME',
      );
    }
    final pending = <String, dynamic>{
      'v': 1,
      'key': AuthCrypto.randomEncoded(16),
      'username': _sessions.username!,
      'operation': operation.name.toUpperCase(),
      'state': 'UNKNOWN',
      if (identityId != null) 'identityId': identityId,
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
    };
    var saved = false;
    await _store.update((latest) {
      if (!_current(epoch, authority, record)) return latest;
      if (latest.identityChanges.containsKey(record.accountId)) return latest;
      saved = true;
      return latest.copyWith(
        identityChanges: {...latest.identityChanges, record.accountId: pending},
      );
    });
    if (!saved || !_current(epoch, authority, record)) return;
    _directory = null;
    _status = IdentityManagementStatus.pending;
    _notify();
    if (_current(epoch, authority, record)) {
      await _submit(epoch, authority, record, pending);
    }
  });

  Future<void> reconcilePending() => _run((epoch, authority, record) async {
    final pending = _pending(record);
    if (pending == null || pending['state'] == 'COMMITTED') {
      await _loadDirectory(epoch, authority, record, pending);
    } else {
      await _reconcile(epoch, authority, record, pending);
    }
  });

  Future<void> retryPending() => _run((epoch, authority, record) async {
    final pending = _pending(record);
    if (pending == null || pending['state'] != 'UNKNOWN') return;
    final committed = await _reconcile(epoch, authority, record, pending);
    if (!committed &&
        _current(epoch, authority, record) &&
        _pending(record)?['key'] == pending['key']) {
      await _submit(epoch, authority, record, pending);
    }
  });

  Future<bool> _reconcile(
    int epoch,
    int authority,
    SessionRecord record,
    Map<String, dynamic> pending,
  ) async {
    _directory = null;
    _status = IdentityManagementStatus.pending;
    _notify();
    final result = await _api.identityChangeResult(
      sessionToken: record.token,
      idempotencyKey: pending['key'] as String,
    );
    if (!await _metadata(epoch, authority, record, result.sessionExpiresAt)) {
      return true;
    }
    if (!_current(epoch, authority, record)) return true;
    if (result.committed) {
      await _acceptCommitted(epoch, authority, record, pending, result);
      return true;
    }
    if (result.rejected) {
      if (result.operation != _operation(pending) ||
          result.identityId != null ||
          !_definitiveRejections.contains(result.errorCode)) {
        throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
      }
      await _clearPending(epoch, authority, record, pending);
      if (_current(epoch, authority, record)) {
        _status = IdentityManagementStatus.idle;
        _error = AuthFailure(
          kind: AuthFailureKind.rejected,
          code: result.errorCode,
        );
        _message = _failureMessage(_error!);
      }
      return true;
    }
    if (result.operation != null || result.identityId != null) {
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    }
    _status = IdentityManagementStatus.retryRequired;
    return false;
  }

  Future<void> _submit(
    int epoch,
    int authority,
    SessionRecord record,
    Map<String, dynamic> pending,
  ) async {
    if (!_current(epoch, authority, record)) return;
    _status = IdentityManagementStatus.pending;
    _notify();
    final IdentityChangeOutcome outcome;
    try {
      outcome = await _api.changeIdentity(
        sessionToken: record.token,
        idempotencyKey: pending['key'] as String,
        operation: _operation(pending),
        identityId: pending['identityId'] as String?,
        nickname: pending['nickname'] as String?,
        avatar: pending['avatar'] as String?,
      );
    } on AuthFailure catch (failure) {
      // The server permanently binds business rejection to this key. Query
      // that tombstone before clearing; a missing receipt remains unknown.
      if (_current(epoch, authority, record) &&
          failure.kind == AuthFailureKind.rejected &&
          _definitiveRejections.contains(failure.code)) {
        await _reconcile(epoch, authority, record, pending);
        return;
      }
      rethrow;
    }
    if (!await _metadata(epoch, authority, record, outcome.sessionExpiresAt)) {
      return;
    }
    if (_current(epoch, authority, record)) {
      await _acceptCommitted(epoch, authority, record, pending, outcome);
    }
  }

  Future<void> _acceptCommitted(
    int epoch,
    int authority,
    SessionRecord record,
    Map<String, dynamic> pending,
    IdentityChangeOutcome outcome,
  ) async {
    if (!outcome.committed ||
        outcome.operation != _operation(pending) ||
        outcome.identityId == null ||
        pending['identityId'] != null &&
            outcome.identityId != pending['identityId']) {
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    }
    await _store.update((latest) {
      if (!_current(epoch, authority, record) ||
          _pending(record)?['key'] != pending['key']) {
        return latest;
      }
      final drafts = Map<String, dynamic>.from(latest.identityDrafts);
      if (_operation(pending) == IdentityOperation.create) {
        drafts.remove(record.accountId);
      } else {
        final draft = drafts[record.accountId];
        if (draft is Map<String, dynamic> &&
            draft['upload'] is Map &&
            pending['avatar'] == 'avatar-v1:${draft['upload']['assetId']}') {
          drafts[record.accountId] = Map<String, dynamic>.from(draft)
            ..remove('upload');
        }
      }
      _uploadBytes = null;
      _uploadAsset = null;
      return latest.copyWith(
        identityChanges: {
          ...latest.identityChanges,
          record.accountId: {...pending, 'state': 'COMMITTED'},
        },
        identityDrafts: drafts,
      );
    });
    if (_current(epoch, authority, record)) {
      await _loadDirectory(epoch, authority, record, pending);
    }
  }

  Future<void> _loadDirectory(
    int epoch,
    int authority,
    SessionRecord record,
    Map<String, dynamic>? completed,
  ) async {
    if (!_current(epoch, authority, record)) return;
    _directory = null;
    _status = IdentityManagementStatus.loading;
    _notify();
    final result = await _api.identities(record.token);
    if (!await _metadata(epoch, authority, record, result.sessionExpiresAt)) {
      return;
    }
    if (completed != null) {
      await _clearPending(epoch, authority, record, completed);
    }
    if (!_current(epoch, authority, record)) return;
    _directory = result;
    _entryReady = result.identities.isNotEmpty;
    _status = IdentityManagementStatus.ready;
  }

  Future<void> _clearPending(
    int epoch,
    int authority,
    SessionRecord record,
    Map<String, dynamic> pending,
  ) async {
    await _store.update((latest) {
      if (!_current(epoch, authority, record) ||
          _pending(record)?['key'] != pending['key']) {
        return latest;
      }
      final changes = Map<String, dynamic>.from(latest.identityChanges)
        ..remove(record.accountId);
      return latest.copyWith(identityChanges: changes);
    });
  }

  Future<bool> _metadata(
    int epoch,
    int authority,
    SessionRecord record,
    DateTime expiry,
  ) async {
    if (!_current(epoch, authority, record)) return false;
    if (!expiry.isUtc) {
      throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
    }
    return _sessions.persistSessionMetadata(
      record.token,
      expiry,
      () => _current(epoch, authority, record),
    );
  }

  static IdentityOperation _operation(Map<String, dynamic> pending) =>
      switch (pending['operation']) {
        'CREATE' => IdentityOperation.create,
        'RENAME' => IdentityOperation.rename,
        'DELETE' => IdentityOperation.delete,
        'AVATAR' => IdentityOperation.avatar,
        _ => throw const FormatException('Invalid identity operation'),
      };
  static const _definitiveRejections = {
    'IDENTITY_INVALID_NAME',
    'IDENTITY_DUPLICATE_NAME',
    'IDENTITY_LIMIT',
    'IDENTITY_CREATE_COOLDOWN',
    'IDENTITY_RENAME_COOLDOWN',
    'IDENTITY_LAST_REQUIRED',
    'IDENTITY_NOT_FOUND',
    'IDENTITY_AVATAR_INVALID',
  };

  Future<void> _run(
    Future<void> Function(int, int, SessionRecord) work, {
    bool preserveDirectoryOnFailure = false,
  }) async {
    if (_busy || _disposed) return;
    _busy = true;
    final epoch = ++_epoch, authority = _sessions.authorityVersion;
    _message = null;
    _error = null;
    _notify();
    SessionRecord? record;
    try {
      await _store.read();
      if (_disposed ||
          epoch != _epoch ||
          authority != _sessions.authorityVersion) {
        return;
      }
      record = _active();
      if (record == null) {
        _directory = null;
        _status = _sessions.status == AuthStatus.unavailable
            ? IdentityManagementStatus.unavailable
            : IdentityManagementStatus.signedOut;
        return;
      }
      _observedToken = record.token;
      _observedAuthority = authority;
      await work(epoch, authority, record);
    } on AuthStorageFailure {
      if (!_disposed && (epoch == _epoch || _store.current == null)) {
        _directory = null;
        _status = IdentityManagementStatus.storageFailure;
        _message = '安全存储尚未确认写入，请恢复后核对原操作。';
      }
    } on AuthFailure catch (failure) {
      if (record == null || !_current(epoch, authority, record)) return;
      _error = failure;
      if (!preserveDirectoryOnFailure ||
          failure.unauthorized ||
          failure.kind == AuthFailureKind.unavailable) {
        _directory = null;
      }
      if (failure.unauthorized) {
        _sessions.sessionUnauthorized(record.token, failure.code);
        _status = IdentityManagementStatus.signedOut;
        _message = '会话已失效，请使用原账号重新登录后核对。';
      } else if (failure.kind == AuthFailureKind.unavailable) {
        _sessions.sessionUnavailable(record.token);
        _status = IdentityManagementStatus.unavailable;
        _message = '暂时无法核对账号状态，请恢复服务后重试。';
      } else {
        _status = _pending(record) == null
            ? preserveDirectoryOnFailure && _directory != null
                  ? IdentityManagementStatus.ready
                  : IdentityManagementStatus.idle
            : IdentityManagementStatus.pending;
        _message = _failureMessage(failure);
      }
    } on Object {
      if (record != null && _current(epoch, authority, record)) {
        if (!preserveDirectoryOnFailure) _directory = null;
        _status = hasPending
            ? IdentityManagementStatus.pending
            : preserveDirectoryOnFailure && _directory != null
            ? IdentityManagementStatus.ready
            : IdentityManagementStatus.idle;
        _message = '操作结果尚未确认，请重新核对。';
      }
    } finally {
      if (!_disposed && epoch == _epoch) _busy = false;
      _notify();
    }
  }

  static String _failureMessage(AuthFailure failure) => switch (failure.code) {
    'IDENTITY_AVATAR_INVALID' => '头像已失效或图片不符合要求，请重新选择静态图片。',
    'IDENTITY_AVATAR_LIMIT' => '待保存的头像过多，请先完成当前设置或稍后重试。',
    'IDENTITY_INVALID_NAME' => '昵称不符合规则，请检查输入。',
    'IDENTITY_DUPLICATE_NAME' => '你已拥有同名身份，请换一个昵称。',
    'IDENTITY_LIMIT' => '最多保留 3 个身份。',
    'IDENTITY_CREATE_COOLDOWN' => '还未到可创建日期，请刷新核对。',
    'IDENTITY_RENAME_COOLDOWN' => '距离上次改名尚未满 30 天，请刷新核对。',
    'IDENTITY_LAST_REQUIRED' => '必须保留至少一个身份。',
    'IDENTITY_NOT_FOUND' => '身份已不存在，请刷新列表。',
    'PENDING_CHECK_REQUIRED' => '请先核对上次操作。',
    _ => '提交结果尚未确认，请核对原操作。',
  };

  void cancelView() {
    if (_disposed) return;
    _epoch++;
    _busy = false;
    _directory = null;
    _message = null;
    _status = _active() == null
        ? IdentityManagementStatus.signedOut
        : IdentityManagementStatus.idle;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _store.removeListener(_authorityChanged);
    _sessions.removeListener(_authorityChanged);
    super.dispose();
  }
}
