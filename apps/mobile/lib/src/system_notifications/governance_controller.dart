import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../auth/auth_session_controller.dart';
import '../auth/auth_store.dart';
import '../auth/auth_crypto.dart';
import '../identity/identity_api.dart';
import '../identity/active_identity_controller.dart';
import '../posts/post_protocol.dart';
import '../posts/post_models.dart';
import 'governance_api.dart';
import 'notification_models.dart';
import 'moderation_access.dart';
import 'governance_material_vault.dart';

/// A separate origin-scoped native vault value, with no filesystem fallback.
/// Only submitted operations are retained; abandoning an unsubmitted form never
/// creates a draft. Unknown operations retain their immutable original material.
class GovernancePendingStore {
  GovernancePendingStore(this.vault);
  final AuthVault vault;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<Map<String, dynamic>> _read() async {
    final raw = await vault.read();
    if (raw == null) return {};
    if (raw.length > 50 * 1024 * 1024) throw const AuthStorageFailure();
    final root = PostJson.record(
      GovernanceStrictJson(raw, maxList: 200).decode(),
      {'v', 'owners'},
    );
    if (root['v'] != 1 || root['owners'] is! Map<String, dynamic>) {
      throw const AuthStorageFailure();
    }
    final owners = Map<String, dynamic>.from(root['owners'] as Map);
    if (owners.length > 32) throw const AuthStorageFailure();
    for (final entry in owners.entries) {
      if (entry.key.length == 43) {
        AuthCrypto.decode(entry.key, bytes: 32);
      } else {
        PostProtocol.resourceId(entry.key);
      }
      final p = PostJson.record(
        entry.value,
        {'id', 'path', 'queryPath', 'body', 'kind'},
        optional: {'retryToken'},
      );
      PostJson.id(p, 'id');
      if (p['retryToken'] != null) PostJson.id(p, 'retryToken');
      if (p['body'] is! Map<String, dynamic> ||
          !{'REPORT', 'DM_REPORT', 'APPEAL', 'MATERIAL'}.contains(p['kind']) ||
          p['path'] is! String ||
          p['queryPath'] is! String) {
        throw const AuthStorageFailure();
      }
    }
    return owners;
  }

  Future<Map<String, dynamic>?> get(String account) => _serial(() async {
    final owners = await _read();
    final value = owners[account];
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  });
  Future<void> put(
    String account,
    Map<String, dynamic>? value,
    bool Function() current,
  ) => _serial(() async {
    final owners = await _read();
    if (!current()) return;
    if (value == null) {
      owners.remove(account);
    } else {
      owners[account] = value;
    }
    final encoded = jsonEncode({'v': 1, 'owners': owners});
    if (encoded.length > 50 * 1024 * 1024) throw const AuthStorageFailure();
    await vault.write(encoded);
    if (await vault.read() != encoded) throw const AuthStorageFailure();
  });
  Future<void> close() async {
    await _tail;
    final v = vault;
    if (v is GovernanceMaterialVault) await v.close();
  }
}

class _Authority {
  const _Authority(this.epoch, this.token, this.account);
  final int epoch;
  final String token, account;
}

class GovernanceController extends ChangeNotifier {
  GovernanceController({
    required this.api,
    required this.sessions,
    required this.authStore,
    required this.identitiesApi,
    required this.pendingStore,
    this.restrictedAccess,
  }) {
    sessions.addListener(_changed);
    authStore.addListener(_changed);
    restrictedAccess?.addListener(_changed);
    _changed();
  }
  final GovernanceApi api;
  final AuthSessionController sessions;
  final AuthStore authStore;
  final IdentityApi identitiesApi;
  final GovernancePendingStore pendingStore;
  final ModerationAccess? restrictedAccess;
  bool get restricted => _token != null && _token == restrictedAccess?.token;
  List<ManagedIdentity> identities = [];
  List<SystemNotice> items = [];
  String? _selectedIdentityId, nextBefore, error;
  ActiveIdentityController? activeIdentity;
  String? get selectedIdentityId => restricted
      ? _selectedIdentityId
      : activeIdentity?.accountId == _account
      ? activeIdentity?.selectedId ?? _selectedIdentityId
      : _selectedIdentityId;
  set selectedIdentityId(String? id) => _selectedIdentityId = id;
  void bindActiveIdentity(ActiveIdentityController? value) {
    activeIdentity?.removeListener(_activeIdentityChanged);
    activeIdentity = value;
    value?.addListener(_activeIdentityChanged);
    _activeIdentityChanged();
  }

  void _activeIdentityChanged() {
    if (restricted) return;
    _listRequest++;
    items = [];
    nextBefore = null;
    _notify();
  }

  Map<String, dynamic>? pending;
  bool loading = false, busy = false;
  bool _disposed = false;
  int _epoch = 0, _version = -1, _listRequest = 0;
  String? _token, _account;
  final Set<String> _closedAccounts = {};
  String? get accountId => _account;
  int get authorityVersion => _epoch;
  bool get available =>
      !_disposed &&
      _token != null &&
      (sessions.isCurrentToken(_token!) || _token == restrictedAccess?.token);
  bool _inboxUnread = false;
  bool get hasUnread => _inboxUnread || items.any((i) => i.unread);

  void updateInboxUnread(bool unread) {
    if (_inboxUnread == unread) return;
    _inboxUnread = unread;
    _notify();
  }

  Future<Map<String, dynamic>?> requestInbox(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!path.startsWith('/api/v1/notifications')) {
      throw ArgumentError('Invalid inbox path');
    }
    final authority = _capture();
    try {
      return await _request(authority, method, path, body: body, query: query);
    } on Object catch (e) {
      _fail(e, authority);
      rethrow;
    }
  }

  void selectInboxIdentity(String id) {
    if (!identities.any((i) => i.id == id)) return;
    activeIdentity?.selectConfirmed(
      id,
      identities.map((i) => i.id),
      account: accountId,
    );
    selectedIdentityId = id;
    _listRequest++;
    items = [];
    nextBefore = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    final record = authStore.current?.session;
    final ordinaryToken =
        record != null &&
            !_closedAccounts.contains(record.accountId) &&
            sessions.isCurrentToken(record.token)
        ? record.token
        : null;
    if (ordinaryToken != null && restrictedAccess?.token != null) {
      unawaited(restrictedAccess!.clear());
    }
    final token = ordinaryToken ?? restrictedAccess?.token;
    if (_token == token && _version == sessions.authorityVersion) return;
    _version = sessions.authorityVersion;
    _token = token;
    _account = token == null
        ? null
        : ordinaryToken != null
        ? record!.accountId
        : restrictedAccess!.ownerKey;
    _epoch++;
    _listRequest++;
    identities = [];
    items = [];
    _inboxUnread = false;
    selectedIdentityId = nextBefore = error = null;
    pending = null;
    busy = loading = false;
    _notify();
    if (available) unawaited(restorePending());
  }

  _Authority _capture() {
    if (!available) throw const GovernanceFailure(401, 'SESSION_INVALID');
    return _Authority(_epoch, _token!, _account!);
  }

  bool _current(_Authority a) =>
      available &&
      a.epoch == _epoch &&
      a.token == _token &&
      a.account == _account;
  Future<Map<String, dynamic>?> _request(
    _Authority a,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (restricted &&
        (path.startsWith('/api/v1/reports') ||
            path.startsWith('/api/v1/dm/') ||
            query?['identityId'] != null)) {
      throw const GovernanceFailure(403, 'MODERATION_SELF_SCOPE_REQUIRED');
    }
    final response = await api.request(
      a.token,
      method,
      path,
      body: body,
      query: query,
    );
    if (!_current(a)) return null;
    if (restricted) {
      if (response.expiresAt.isAfter(restrictedAccess!.expiresAt!)) {
        throw const FormatException('Restricted access cannot renew');
      }
    } else if (!await sessions.persistSessionMetadata(
          a.token,
          response.expiresAt,
          () => _current(a),
        ) ||
        !_current(a)) {
      return null;
    }
    return response.value;
  }

  void _fail(Object e, _Authority a) {
    if (!_current(a)) return;
    if (e is GovernanceFailure && e.status == 503 && !restricted) {
      sessions.sessionUnavailable(a.token);
      return;
    }
    if (e is GovernanceFailure && e.status == 401) {
      if (restricted) {
        unawaited(restrictedAccess!.clear());
      } else {
        sessions.sessionUnauthorized(a.token, e.code);
      }
      return;
    }
    error = e is AuthStorageFailure
        ? '本机安全保存失败，原任务结果尚未确认。请恢复后重新核对。'
        : e is GovernanceFailure && !e.uncertain
        ? '操作未完成，请检查权限、目标状态或材料后重试。'
        : '暂时无法确认结果，原操作已保留，请核对原任务。';
    _notify();
  }

  Future<void> restorePending() async {
    final a = _capture();
    try {
      final p = await pendingStore.get(a.account);
      if (!_current(a)) return;
      pending = p;
      _notify();
      if (p != null) await reconcilePending();
    } on Object catch (e) {
      _fail(e, a);
    }
  }

  Future<void> purgeClosedAccount(String accountId) async {
    PostProtocol.resourceId(accountId);
    _closedAccounts.add(accountId);
    _changed();
    await pendingStore.put(accountId, null, () => true);
  }

  Future<bool> loadIdentities() async {
    final a = _capture();
    if (restricted) {
      identities = [];
      selectedIdentityId = null;
      _notify();
      return true;
    }
    try {
      final directory = await identitiesApi.identities(a.token);
      if (!_current(a) ||
          !await sessions.persistSessionMetadata(
            a.token,
            directory.sessionExpiresAt,
            () => _current(a),
          ) ||
          !_current(a)) {
        return false;
      }
      identities = directory.identities;
      if (selectedIdentityId != null &&
          !identities.any((i) => i.id == selectedIdentityId)) {
        selectedIdentityId = null;
      }
      _notify();
      return true;
    } on Object catch (e) {
      _fail(e, a);
      return false;
    }
  }

  Future<void> selectIdentity(String? id) async {
    if (id != null && !identities.any((i) => i.id == id)) return;
    if (id != null && !restricted) {
      activeIdentity?.selectConfirmed(
        id,
        identities.map((i) => i.id),
        account: accountId,
      );
    }
    selectedIdentityId = id;
    items = [];
    nextBefore = null;
    _notify();
    await loadNotifications();
  }

  Future<void> loadNotifications({bool more = false}) async {
    final a = _capture(), request = ++_listRequest;
    final identity = selectedIdentityId;
    loading = true;
    error = null;
    _notify();
    try {
      final raw = await _request(
        a,
        'GET',
        '/api/v1/system-notifications',
        query: {
          'limit': '50',
          if (identity != null) 'identityId': identity,
          if (more && nextBefore != null) 'before': nextBefore!,
        },
      );
      if (raw == null ||
          request != _listRequest ||
          identity != selectedIdentityId) {
        return;
      }
      final m = PostJson.record(raw, {'items'}, optional: {'nextBefore'});
      if (m['items'] is! List || (m['items'] as List).length > 50) {
        throw const FormatException('Invalid notification page');
      }
      final notices = (m['items'] as List).map(SystemNotice.parse).toList();
      if (notices.any(
        (n) => n.scope == 'IDENTITY' && n.identityId != identity,
      )) {
        throw const FormatException('Cross identity notification');
      }
      if (notices.map((n) => n.id).toSet().length != notices.length) {
        throw const FormatException('Duplicate notification');
      }
      items = more
          ? [...items, ...notices.where((n) => !items.any((i) => i.id == n.id))]
          : notices;
      nextBefore = m['nextBefore'] == null
          ? null
          : PostJson.text(m, 'nextBefore', maxLength: 128);
    } on Object catch (e) {
      _fail(e, a);
    } finally {
      if (_current(a) && request == _listRequest) {
        loading = false;
        _notify();
      }
    }
  }

  Future<SystemNotice?> openNotice(
    String id, {
    String? targetIdentityId,
  }) async {
    if (targetIdentityId != null && targetIdentityId != selectedIdentityId) {
      await selectIdentity(targetIdentityId);
      if (!available || selectedIdentityId != targetIdentityId) return null;
    }
    final a = _capture();
    final identity = selectedIdentityId;
    final query = identity == null ? null : {'identityId': identity};
    try {
      final raw = await _request(
        a,
        'GET',
        '/api/v1/system-notifications/${PostProtocol.resourceId(id)}',
        query: query,
      );
      if (raw == null || selectedIdentityId != identity) return null;
      final notice = SystemNotice.parse(raw);
      if (notice.id != id) {
        throw const FormatException('Mismatched notification');
      }
      if (notice.scope == 'IDENTITY' && notice.identityId != identity) {
        throw const FormatException('Cross identity notification detail');
      }
      final read = await _request(
        a,
        'POST',
        '/api/v1/system-notifications/$id/read',
        body: {},
        query: query,
      );
      if (read == null || selectedIdentityId != identity) return null;
      final opened = SystemNotice.parse(read);
      if (opened.id != notice.id ||
          opened.scope != notice.scope ||
          opened.identityId != notice.identityId ||
          opened.readAt == null ||
          opened.route.name != notice.route.name ||
          opened.route.resourceId != notice.route.resourceId) {
        throw const FormatException('Mismatched read receipt');
      }
      items = [
        for (final item in items)
          if (item.scope == 'ACCOUNT' || item.identityId == selectedIdentityId)
            item.id == id ? opened : item,
      ];
      _notify();
      return opened;
    } on Object catch (e) {
      _fail(e, a);
      return null;
    }
  }

  Future<Map<String, dynamic>?> readResource(NotificationRoute route) async {
    final a = _capture();
    final prefix = switch (route.name) {
      'REPORT' => 'reports',
      'SANCTION' => 'sanctions',
      'APPEAL' => 'appeals',
      _ => null,
    };
    if (prefix == null) return null;
    try {
      final result = await _request(
        a,
        'GET',
        '/api/v1/$prefix/${PostProtocol.resourceId(route.resourceId)}',
      );
      if (result == null) return null;
      if (route.name == 'REPORT') {
        final r = _reportReceipt(result);
        if (r != null && r['id'] != route.resourceId) {
          throw const FormatException('Mismatched report');
        }
      } else {
        _resourceReceipt(route.name, result);
        if (result['id'] != route.resourceId) {
          throw const FormatException('Mismatched resource');
        }
      }
      return result;
    } on Object catch (e) {
      _fail(e, a);
      return null;
    }
  }

  Future<bool> submitReport({
    required String postId,
    String? commentId,
    required String? identityId,
    required String reason,
    required String description,
    required List<EvidenceImage> images,
  }) {
    if (restricted) return Future.value(false);
    validateMaterials(description, images, textLimit: 200, imageLimit: 6);
    if (!reportReasons.containsKey(reason)) {
      throw const FormatException('Invalid reason');
    }
    PostProtocol.resourceId(postId);
    if (commentId != null) PostProtocol.resourceId(commentId);
    if (identityId != null) PostProtocol.resourceId(identityId);
    final id = governanceId();
    return _submit(id, 'REPORT', '/api/v1/reports/$id', '/api/v1/reports/$id', {
      'postId': postId,
      if (commentId != null) 'commentId': commentId,
      'identityId': identityId,
      'reason': reason,
      'description': description,
      'images': images.map((i) => i.toJson()).toList(),
    });
  }

  Future<bool> submitDmReport(
    Map<String, dynamic> snapshot,
    String reason,
    String description,
    List<EvidenceImage> images,
  ) {
    if (restricted || snapshot['authorized'] != true) {
      return Future.value(false);
    }
    validateMaterials(description, images, textLimit: 200, imageLimit: 6);
    var materialBytes =
        images.fold<int>(0, (n, image) => n + image.bytes.length) +
        utf8.encode(description).length;
    for (final entry in snapshot['entries'] as List) {
      materialBytes +=
          utf8.encode(entry['text'] as String).length +
          base64Decode(entry['data'] as String).length;
    }
    if (materialBytes > 32 * 1024 * 1024) {
      throw const FormatException('Evidence budget exceeded');
    }
    if (!reportReasons.containsKey(reason)) {
      throw const FormatException('Invalid reason');
    }
    final id = governanceId(), path = '/api/v1/dm/governance/reports/';
    return _submit(id, 'DM_REPORT', '$path$id', '$path$id', {
      ...snapshot,
      'reason': reason,
      'description': description,
      'images': images.map((i) => i.toJson()).toList(),
    });
  }

  Future<AppealMaterialPage?> readAppealMaterials(
    String appealId,
    String cursor,
  ) async {
    final a = _capture();
    try {
      if (cursor.isEmpty || cursor.length > 128) {
        throw const FormatException('Invalid material cursor');
      }
      final result = await _request(
        a,
        'GET',
        '/api/v1/appeals/${PostProtocol.resourceId(appealId)}/materials',
        query: {'cursor': cursor},
      );
      if (result == null) return null;
      final page = AppealMaterialPage.parse(result);
      if (page.nextCursor == cursor) {
        throw const FormatException('Material cursor did not advance');
      }
      return page;
    } on Object catch (e) {
      _fail(e, a);
      return null;
    }
  }

  Future<bool> submitAppeal(
    String sanctionId,
    String description,
    List<EvidenceImage> images,
  ) {
    validateMaterials(description, images, textLimit: 500, imageLimit: 6);
    final id = governanceId();
    final target = PostProtocol.resourceId(sanctionId);
    return _submit(
      id,
      'APPEAL',
      '/api/v1/sanctions/$target/appeals/$id',
      '/api/v1/sanctions/$target/appeal-requests/$id',
      {
        'description': description,
        'images': images.map((i) => i.toJson()).toList(),
      },
    );
  }

  Future<bool> supplementAppeal(
    String appealId,
    String description,
    List<EvidenceImage> images,
  ) {
    validateMaterials(description, images, textLimit: 500, imageLimit: 3);
    final id = governanceId(), target = PostProtocol.resourceId(appealId);
    return _submit(
      id,
      'MATERIAL',
      '/api/v1/appeals/$target/materials/$id',
      '/api/v1/appeals/$target/material-requests/$id',
      {
        'description': description,
        'images': images.map((i) => i.toJson()).toList(),
      },
    );
  }

  Future<bool> _submit(
    String id,
    String kind,
    String path,
    String queryPath,
    Map<String, dynamic> body,
  ) async {
    if (busy || pending != null) return false;
    final a = _capture();
    busy = true;
    error = null;
    _notify();
    try {
      // Recover storage before creating a new key; a previous process might
      // have lost the acknowledgement of its final vault write.
      final existing = await pendingStore.get(a.account);
      if (!_current(a)) return false;
      if (existing != null) {
        pending = existing;
        return false;
      }
      final p = {
        'id': id,
        'kind': kind,
        'path': path,
        'queryPath': queryPath,
        'body': body,
      };
      await pendingStore.put(a.account, p, () => _current(a));
      if (!_current(a)) return false;
      pending = p;
      final result = await _request(a, 'PUT', path, body: body);
      if (result == null) return false;
      return await _complete(a, p, result, isQuery: false);
    } on Object catch (e) {
      _fail(e, a);
      if (_current(a) &&
          pending != null &&
          e is GovernanceFailure &&
          (e.uncertain || e.code.endsWith('ATTEMPT_SEALED'))) {
        try {
          final original = await _request(
            a,
            'GET',
            pending!['queryPath'] as String,
          );
          if (original != null) {
            return await _complete(a, pending!, original, isQuery: true);
          }
        } on Object catch (queryError) {
          _fail(queryError, a);
        }
      }
      return false;
    } finally {
      if (_current(a)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> _complete(
    _Authority a,
    Map<String, dynamic> p,
    Map<String, dynamic> result, {
    required bool isQuery,
  }) async {
    final state = result['state'];
    final submitted = {'REPORT', 'DM_REPORT'}.contains(p['kind']) || isQuery
        ? state == 'SUBMITTED'
        : result['id'] is String;
    if (!submitted) {
      if (state != 'NOT_SUBMITTED') {
        throw const FormatException('Invalid original request result');
      }
      await _rememberRetryToken(a, p, result);
      error = '已确认原任务未提交。可保留原材料、原任务重试，或放弃。';
      return false;
    }
    if ({'REPORT', 'DM_REPORT'}.contains(p['kind'])) {
      final report = _reportReceipt(result), original = p['body'] as Map;
      if (report == null ||
          report['id'] != p['id'] ||
          (p['kind'] == 'DM_REPORT'
              ? report['conversationId'] != original['conversationId']
              : report['postId'] != original['postId']) ||
          report['commentId'] != original['commentId'] ||
          report['reason'] != original['reason'] ||
          report['description'] != original['description']) {
        throw const FormatException('Mismatched report receipt');
      }
    } else {
      final appeal = isQuery ? result['appeal'] : result;
      if (appeal is! Map<String, dynamic>) {
        throw const FormatException('Missing appeal receipt');
      }
      _resourceReceipt('APPEAL', appeal);
      final segments = (p['path'] as String).split('/');
      if (p['kind'] == 'APPEAL' && appeal['sanctionId'] != segments[4] ||
          p['kind'] == 'MATERIAL' && appeal['id'] != segments[4]) {
        throw const FormatException('Mismatched appeal receipt');
      }
    }
    await pendingStore.put(a.account, null, () => _current(a));
    if (!_current(a)) return false;
    pending = null;
    error = null;
    return true;
  }

  static Map<String, dynamic>? _reportReceipt(Map<String, dynamic> raw) {
    final wrapper = PostJson.record(
      raw,
      {'state'},
      optional: {'report', 'retryToken'},
    );
    if (wrapper['state'] == 'NOT_SUBMITTED' && wrapper['report'] == null) {
      return null;
    }
    if (wrapper['state'] != 'SUBMITTED') {
      throw const FormatException('Invalid report state');
    }
    final r = PostJson.record(
      wrapper['report'],
      {'id', 'caseId', 'state', 'postId', 'reason', 'description', 'createdAt'},
      optional: {'outcome', 'explanation', 'commentId', 'conversationId'},
    );
    for (final key in ['id', 'caseId']) {
      PostJson.id(r, key);
    }
    if (r['conversationId'] != null) {
      PostJson.id(r, 'conversationId');
      if (r['postId'] != '' || r['commentId'] != null) {
        throw const FormatException('Invalid DM report target');
      }
    } else {
      PostJson.id(r, 'postId');
    }
    if (r['commentId'] != null) PostJson.id(r, 'commentId');
    if (!{'PENDING', 'PROCESSING', 'ENDED'}.contains(r['state']) ||
        !reportReasons.containsKey(r['reason'])) {
      throw const FormatException('Invalid report');
    }
    PostJson.text(r, 'description', maxLength: 800, allowEmpty: true);
    PostJson.date(r, 'createdAt');
    for (final key in ['outcome', 'explanation']) {
      if (r[key] != null) {
        PostJson.text(r, key, maxLength: 2048, allowEmpty: true);
      }
    }
    return r;
  }

  Future<Map<String, dynamic>> _rememberRetryToken(
    _Authority a,
    Map<String, dynamic> original,
    Map<String, dynamic> result,
  ) async {
    final token = PostJson.id(result, 'retryToken');
    final updated = {...original, 'retryToken': token};
    await pendingStore.put(a.account, updated, () => _current(a));
    if (_current(a)) pending = updated;
    return updated;
  }

  static void _resourceReceipt(String kind, Map<String, dynamic> raw) {
    if (kind == 'SANCTION') {
      final r = PostJson.record(
        raw,
        {
          'id',
          'caseId',
          'action',
          'reason',
          'startsAt',
          'postId',
          'appealCount',
        },
        optional: {
          'endsAt',
          'revokedAt',
          'activeAppealId',
          'commentId',
          'conversationId',
        },
      );
      for (final key in ['id', 'caseId']) {
        PostJson.id(r, key);
      }
      if (r['conversationId'] != null) {
        PostJson.id(r, 'conversationId');
        if (r['postId'] != '' || r['commentId'] != null) {
          throw const FormatException('Invalid DM sanction target');
        }
      } else {
        PostJson.id(r, 'postId');
      }
      if (r['commentId'] != null) PostJson.id(r, 'commentId');
      PostJson.text(r, 'reason', maxLength: 2048);
      PostJson.date(r, 'startsAt');
      if (r['appealCount'] is! int ||
          (r['appealCount'] as int) < 0 ||
          (r['appealCount'] as int) > 3) {
        throw const FormatException('Invalid appeal count');
      }
      for (final key in ['endsAt', 'revokedAt']) {
        if (r[key] != null) PostJson.date(r, key);
      }
      if (r['activeAppealId'] != null) PostJson.id(r, 'activeAppealId');
    } else {
      final r = PostJson.record(
        raw,
        {'id', 'sanctionId', 'state', 'ordinal', 'reason', 'materials'},
        optional: {'caseId', 'version', 'action', 'nextMaterialsCursor'},
      );
      PostJson.id(r, 'id');
      PostJson.id(r, 'sanctionId');
      if (r['caseId'] != null) PostJson.id(r, 'caseId');
      if (r['version'] != null) PostJson.integer(r, 'version', 1, 2147483647);
      if (r['nextMaterialsCursor'] != null) {
        PostJson.text(r, 'nextMaterialsCursor', maxLength: 128);
      }
      if (r['action'] != null &&
          !{
            'TAKEDOWN',
            'MUTE',
            'BAN',
            'RESET_NICKNAME',
            'RESET_AVATAR',
          }.contains(r['action'])) {
        throw const FormatException('Invalid appeal action');
      }
      if (!{'PENDING', 'ACCEPTED', 'REJECTED'}.contains(r['state']) ||
          r['ordinal'] is! int ||
          (r['ordinal'] as int) < 1 ||
          (r['ordinal'] as int) > 3 ||
          r['materials'] is! List ||
          (r['materials'] as List).length > 1) {
        throw const FormatException('Invalid appeal');
      }
      for (final material in r['materials'] as List) {
        AppealMaterialPage.material(material);
      }
    }
  }

  Future<bool> reconcilePending({
    bool retry = false,
    bool discard = false,
  }) async {
    if (busy || pending == null) return false;
    final a = _capture(), p = pending!;
    busy = true;
    error = null;
    _notify();
    try {
      final result = await _request(a, 'GET', p['queryPath'] as String);
      if (result == null) return false;
      if (result['state'] == 'SUBMITTED') {
        return await _complete(a, p, result, isQuery: true);
      }
      if (result['state'] != 'NOT_SUBMITTED') {
        throw const FormatException('Invalid original request result');
      }
      // GET has fenced all older attempts; its newest token must be durable
      // before any replacement PUT can use the same logical request key.
      PostJson.id(result, 'retryToken');
      if (discard) {
        await pendingStore.put(a.account, null, () => _current(a));
        if (!_current(a)) return false;
        pending = null;
        return true;
      }
      if (retry) {
        final updated = await _rememberRetryToken(a, p, result);
        if (!_current(a)) return false;
        final receipt = await _request(
          a,
          'PUT',
          p['path'] as String,
          body: {
            ...Map<String, dynamic>.from(p['body'] as Map),
            'retryToken': updated['retryToken'],
          },
        );
        return receipt != null &&
            await _complete(a, p, receipt, isQuery: false);
      }
      await _rememberRetryToken(a, p, result);
      error = '已确认原任务未提交，可使用原材料重试。';
      return false;
    } on Object catch (e) {
      _fail(e, a);
      if (_current(a) &&
          e is GovernanceFailure &&
          (e.uncertain || e.code.endsWith('ATTEMPT_SEALED'))) {
        try {
          final original = await _request(a, 'GET', p['queryPath'] as String);
          if (original != null) {
            return await _complete(a, p, original, isQuery: true);
          }
        } on Object catch (queryError) {
          _fail(queryError, a);
        }
      }
      return false;
    } finally {
      if (_current(a)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    activeIdentity?.removeListener(_activeIdentityChanged);
    _disposed = true;
    _epoch++;
    sessions.removeListener(_changed);
    authStore.removeListener(_changed);
    restrictedAccess?.removeListener(_changed);
    unawaited(pendingStore.close());
    super.dispose();
  }
}
