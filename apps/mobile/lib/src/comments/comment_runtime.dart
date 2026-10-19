import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/auth_crypto.dart';
import '../auth/auth_session_controller.dart';
import '../auth/auth_store.dart';
import '../identity/identity_api.dart';
import '../identity/identity_management_controller.dart';
import '../posts/post_protocol.dart';
import '../posts/post_models.dart';
import '../storage/post_store.dart';
import 'comment_controller.dart';
import 'comment_http.dart';
import 'comment_journal.dart';
import 'comment_models.dart';
import 'comment_protocol.dart';

String commentUUID() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String commentKey() =>
    AuthCrypto.encode(List.generate(16, (_) => Random.secure().nextInt(256)));

class CommentRuntime extends ChangeNotifier with WidgetsBindingObserver {
  CommentRuntime({
    required this.http,
    required this.sessions,
    required this.authStore,
    required this.identities,
    required this.identityManagement,
    required this.journal,
  }) {
    api = HttpCommentApi(
      request,
      _upload,
      identityMissing: (b) async {
        final d = await directory();
        return !d.identities.any((i) => i.id == b.identityId);
      },
    );
    core = CommentController(api: api, journal: journal);
    core.addListener(_notify);
    WidgetsBinding.instance.addObserver(this);
    sessions.addListener(_changed);
    authStore.addListener(_changed);
    identityManagement.addListener(_identitiesChanged);
    _changed();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_foreground && _automaticPolls++ < 40) unawaited(reconcile());
    });
  }
  final CommentHttp http;
  final AuthSessionController sessions;
  final AuthStore authStore;
  final IdentityApi identities;
  final IdentityManagementController identityManagement;
  final NativeCommentJournal journal;
  Future<void> Function(BuildContext, CommentRejectedInput, Uint8List?)?
  openRetarget;
  late final HttpCommentApi api;
  late final CommentController core;
  Timer? _timer;
  String? _account, _token;
  int _epoch = 0, _version = -1;
  bool _disposed = false, _polling = false;
  bool _foreground = true;
  int _automaticPolls = 0;
  final _mutationBusy = <String>{};
  final _seenCommands = <String>{};
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _automaticPolls = 0;
      unawaited(reconcile());
    }
  }

  final _closed = <String>{};
  final mutations = <String, Map<String, dynamic>>{};
  final deleted = <String>{};
  String? error;
  String? get accountId => _account;
  int get authorityVersion => _epoch;
  bool get available =>
      !_disposed && _token != null && sessions.isCurrentToken(_token!);
  void _notify() {
    for (final e in core.entries) {
      if (_seenCommands.add(e.intent.commandId)) _automaticPolls = 0;
    }
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    final s = authStore.current?.session;
    final token =
        s != null &&
            !_closed.contains(s.accountId) &&
            sessions.isCurrentToken(s.token)
        ? s.token
        : null;
    if (_token == token && _version == sessions.authorityVersion) return;
    _automaticPolls = 0;
    _version = sessions.authorityVersion;
    _token = token;
    _account = token == null ? null : s!.accountId;
    _epoch++;
    _seenCommands.clear();
    mutations.clear();
    deleted.clear();
    journal.staged.clear();
    error = null;
    _notify();
    unawaited(_activate(_account, _epoch));
  }

  void _identitiesChanged() {
    final d = identityManagement.directory;
    if (!available ||
        d == null ||
        identityManagement.status != IdentityManagementStatus.ready) {
      return;
    }
    for (final id
        in core.entries.map((e) => e.intent.binding.identityId).toSet()) {
      if (!d.identities.any((i) => i.id == id)) {
        unawaited(core.identityDeleted(id));
      }
    }
  }

  bool current(int epoch) => available && epoch == _epoch;
  Future<void> _activate(String? account, int epoch) async {
    try {
      await core.activate(account);
      if (account == null || !current(epoch)) return;
      for (final row in await (await journal.store(account)).list()) {
        if (!current(epoch)) return;
        if (row.data['kind'] == 'comment-mutation') {
          mutations[row.id] = Map<String, dynamic>.from(row.data);
        }
      }
      await reconcile();
    } catch (_) {
      if (epoch == _epoch) {
        error = '评论任务存储暂时不可用，恢复后可继续核对。';
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
  }) async {
    if (!available) throw const CommentHttpFailure(401, 'SESSION_INVALID');
    final epoch = _epoch, token = _token!;
    try {
      final r = await http.send(
        token,
        method,
        path,
        body: body,
        query: query,
        bytes: bytes,
        mime: mime,
      );
      if (!current(epoch)) {
        throw const CommentHttpFailure(401, 'SESSION_CHANGED');
      }
      if (!await sessions.persistSessionMetadata(
            token,
            r.expires,
            () => current(epoch),
          ) ||
          !current(epoch)) {
        throw const CommentHttpFailure(401, 'SESSION_CHANGED');
      }
      return r.value;
    } on CommentHttpFailure catch (e) {
      if (current(epoch)) {
        if (e.status == 401) {
          sessions.sessionUnauthorized(token, e.code);
        } else if (e.status == 503) {
          sessions.sessionUnavailable(token);
        }
      }
      rethrow;
    }
  }

  Future<void> _upload(CommentIntent i, int version) async {
    final epoch = _epoch, account = _account!;
    final image = i.content!.image!;
    final bytes = await journal.bytes(account, image);
    if (!current(epoch)) throw const CommentHttpFailure(401, 'SESSION_CHANGED');
    await request(
      'PUT',
      '/api/v1/me/comment-tasks/${i.taskId}/attempts/$version/image',
      bytes: bytes,
      mime: image.selection.mimeType,
    );
  }

  Future<void> reconcile() async {
    if (!available || _polling || !core.ready) return;
    _polling = true;
    final epoch = _epoch;
    try {
      for (final entry in core.entries) {
        if (!current(epoch)) return;
        if (entry.rejectionCode == null &&
            (entry.transport != CommentTransportState.settled ||
                entry.task?.state == CommentTaskState.accepted)) {
          await core.reconcile(entry.localId);
        }
      }
      for (final key in mutations.keys.toList()) {
        if (!current(epoch)) return;
        try {
          await _resolveMutation(key);
        } catch (_) {}
      }
    } finally {
      _polling = false;
    }
  }

  Future<Map<String, dynamic>> contextFor(String post) => request(
    'GET',
    '/api/v1/posts/${PostProtocol.resourceId(post)}/comment-context',
  );
  Future<IdentityDirectory> directory() async {
    final epoch = _epoch, token = _token;
    if (!available || token == null) throw StateError('No session');
    final d = await identities.identities(token);
    if (!current(epoch)) throw StateError('Session changed');
    await sessions.persistSessionMetadata(
      token,
      d.sessionExpiresAt,
      () => current(epoch),
    );
    return d;
  }

  Future<void> sealUnknown(String id) async {
    final e = core.entries.singleWhere((e) => e.localId == id);
    if (e.transport != CommentTransportState.unknown ||
        e.intent.reconciliationOnly) {
      throw StateError('Only unknown commands may be sealed');
    }
    await request(
      'POST',
      '/api/v1/comment-commands/${e.intent.commandId}/seal',
      body: {
        'operation': e.intent.operation.name.toUpperCase(),
        'requestDigest': HttpCommentApi.digest(e.intent),
      },
    );
    await core.reconcile(id);
  }

  Future<void> mutate(String id, {bool? liked}) async {
    PostProtocol.resourceId(id);
    final busyKey = '$_epoch:$id';
    if (!_mutationBusy.add(busyKey)) return;
    try {
      await _mutate(id, liked: liked);
    } finally {
      _mutationBusy.remove(busyKey);
    }
  }

  Future<void> _mutate(String id, {bool? liked}) async {
    final pending = mutations.entries
        .where((e) => e.value['comment'] == id)
        .toList();
    if (pending.isNotEmpty) {
      final previous = pending.single;
      await _resolveMutation(previous.key);
      if (mutations.containsKey(previous.key) ||
          previous.value['operation'] == 'DELETE' ||
          previous.value['operation'] == 'SET_LIKE' &&
              previous.value['liked'] == liked) {
        return;
      }
      // Only after the previous command is authoritatively settled may this
      // explicit, different action receive its own new immutable key.
    }
    if (!available) throw StateError('No session');
    final epoch = _epoch, account = _account!, key = commentKey();
    final m = <String, dynamic>{
      'kind': 'comment-mutation',
      'comment': id,
      'key': key,
      'operation': liked == null ? 'DELETE' : 'SET_LIKE',
      'liked': liked,
    };
    final db = await journal.store(account);
    await db.saveMediaDraft(key, null, m, {});
    _automaticPolls = 0;
    if (!current(epoch)) return;
    mutations[key] = m;
    _notify();
    try {
      final r = await request(
        'PUT',
        '/api/v1/comments/$id/${liked == null ? 'delete' : 'like'}-commands/$key',
        body: liked == null ? {} : {'liked': liked},
      );
      if (current(epoch)) await _finishMutation(key, r);
    } catch (_) {
      if (current(epoch)) {
        error = '结果尚未确认，请核对原操作。';
        _notify();
      }
    }
  }

  Future<void> _resolveMutation(String key) async {
    final epoch = _epoch;
    final r = await request('GET', '/api/v1/comment-commands/$key');
    if (current(epoch)) await _finishMutation(key, r);
  }

  Future<void> _finishMutation(String key, Map<String, dynamic> r) async {
    final m = mutations[key];
    if (m == null) return;
    if (r['state'] == 'UNKNOWN_NOT_OBSERVED') return;
    if (r['operation'] != m['operation']) {
      throw const FormatException('Mutation operation mismatch');
    }
    if (!{'APPLIED', 'REJECTED', 'NOT_ACCEPTED'}.contains(r['state'])) {
      throw const FormatException('Mutation receipt');
    }
    if (r['state'] == 'APPLIED') {
      PostJson.record(
        r,
        m['operation'] == 'DELETE'
            ? {'state', 'operation', 'commentId', 'deletedCount'}
            : {'state', 'operation', 'commentId', 'liked', 'likeCount'},
      );
      if (m['operation'] == 'DELETE') {
        PostJson.integer(r, 'deletedCount', 1, 1000000);
      } else {
        PostJson.integer(r, 'likeCount', 0, 9007199254740991);
        if (r['liked'] != m['liked']) {
          throw const FormatException('Like desired state mismatch');
        }
      }
    } else {
      PostJson.record(r, {'state', 'operation', 'errorCode'});
      PostJson.text(r, 'errorCode');
    }
    if (r['state'] == 'APPLIED' && r['commentId'] != m['comment']) {
      throw const FormatException('Mutation target mismatch');
    }
    final epoch = _epoch, account = _account!;
    await journal.remove(account, key);
    if (!current(epoch)) return;
    if (r['state'] == 'APPLIED' && m['operation'] == 'DELETE') {
      deleted.add(m['comment'] as String);
    }
    mutations.remove(key);
    error = r['state'] == 'APPLIED' ? null : '原操作未能执行，请刷新内容后重试。';
    _notify();
  }

  Future<void> sealMutation(String key) async {
    final m = mutations[key]!;
    final frame = m['operation'] == 'DELETE'
        ? CommentProtocol.delete(commentId: m['comment'] as String)
        : CommentProtocol.setLike(
            commentId: m['comment'] as String,
            liked: m['liked'] as bool,
          );
    final epoch = _epoch;
    final r = await request(
      'POST',
      '/api/v1/comment-commands/$key/seal',
      body: {
        'operation': m['operation'],
        'requestDigest': CommentProtocol.digest(frame),
      },
    );
    if (current(epoch)) await _finishMutation(key, r);
  }

  Future<void> purgeClosedAccount(String account) async {
    _closed.add(account);
    _changed();
    await journal.purgeClosedAccount(account);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    sessions.removeListener(_changed);
    authStore.removeListener(_changed);
    core.removeListener(_notify);
    identityManagement.removeListener(_identitiesChanged);
    core.dispose();
    http.close();
    unawaited(journal.close());
    super.dispose();
  }
}

class CommentScope extends InheritedNotifier<CommentRuntime> {
  const CommentScope({
    super.key,
    required CommentRuntime runtime,
    required super.child,
  }) : super(notifier: runtime);
  static CommentRuntime? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<CommentScope>()?.notifier;
}
