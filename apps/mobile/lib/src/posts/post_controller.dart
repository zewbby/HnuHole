import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_crypto.dart';
import '../auth/auth_models.dart';
import '../auth/auth_session_controller.dart';
import '../auth/auth_store.dart';
import '../identity/identity_api.dart';
import '../storage/post_store.dart';
import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

typedef PostStoreFactory = Future<PostStore> Function(String accountId);

/// 只记录本机原发布意图首次持久观察到的公开成功；不含正文或账号。
class PostPublicationNotice {
  const PostPublicationNotice({
    required this.sequence,
    required this.postId,
    required this.channelId,
  });
  final int sequence;
  final String postId, channelId;
}

/// 编辑输入只属于创建它的授权窗口；已受理重试永远保留原身份和通道。
class PostDraftEditor {
  PostDraftEditor({
    required this.id,
    required this.channelId,
    required this.accountId,
    required this.authorityVersion,
    this.identityId,
    this.title = '',
    this.body = '',
    this.revision = 0,
    this.persisted = false,
    this.isRetry = false,
    this.taskId,
    this.attemptVersion,
    this.bufferId,
    this.bufferRevision = 0,
  });
  final String id, channelId, accountId;
  final int authorityVersion;
  final bool isRetry;
  final String? taskId;
  final int? attemptVersion;
  final String? bufferId;
  int bufferRevision;
  String? identityId;
  String title, body;
  int revision;
  bool persisted, saved = false, saving = false, submitted = false;
  String? error;
}

class PersonalPostItem {
  const PersonalPostItem({
    required this.id,
    required this.title,
    required this.sortAt,
    this.local,
    this.task,
    this.post,
  });
  final String id, title;
  final DateTime sortAt;
  final StoredPostEntry? local;
  final PostTask? task;
  final PostCard? post;
  bool get isDraft => local?.isDraft ?? false;
  String get body => task != null
      ? task!.content?.body ?? ''
      : local?.data['body'] as String? ?? '';
  String get channelId =>
      post?.channelId ??
      task?.channelId ??
      local?.data['channelId'] as String? ??
      '';
  String get state => post != null
      ? 'PUBLISHED'
      : {
          'submitted',
          'UNKNOWN',
          'RESULT_EXPIRED',
          'NOT_ACCEPTED',
          'REJECTED',
        }.contains(local?.state)
      ? local!.state.toUpperCase()
      : task?.state.name.toUpperCase() ??
            (isDraft ? 'DRAFT' : local?.state ?? 'UNKNOWN');
}

class _PostAuthority {
  const _PostAuthority(this.epoch, this.token, this.accountId, this.store);
  final int epoch;
  final String token, accountId;
  final PostStore? store;
}

class _StalePostAuthority implements Exception {}

/// SQLite 保存先于发送；每次网络响应先持久续期，再更新原授权窗口的视图。
class PostController extends ChangeNotifier {
  PostController({
    required this._api,
    required this._sessions,
    required this._authStore,
    required this._identities,
    required this._openStore,
    DateTime Function()? clock,
    this._purgeStore,
    String Function()? newId,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => AuthCrypto.randomEncoded(16)) {
    _sessions.addListener(_authorityChanged);
    _authStore.addListener(_authorityChanged);
    _authorityChanged();
    if (pollInterval > Duration.zero) {
      _poller = Timer.periodic(pollInterval, (_) {
        if (!available) return;
        for (final entry in List<StoredPostEntry>.of(_local)) {
          if (_needsQuery(entry)) unawaited(reconcile(entry.id));
        }
      });
    }
  }

  final PostApi _api;
  final AuthSessionController _sessions;
  final AuthStore _authStore;
  final IdentityApi _identities;
  final PostStoreFactory _openStore;
  final Future<void> Function(String accountId)? _purgeStore;
  final DateTime Function() _clock;
  final String Function() _newId;
  PostStore? _store;
  Future<void> _opening = Future.value();
  String? _token, _accountId;
  int _epoch = 0, _sessionVersion = -1, _pending = 0;
  bool _disposed = false;
  bool _storageRetrying = false;
  Timer? _poller;
  final _checking = <String, Future<void>>{};
  final _publishing = <String>{};
  final _deleting = <String, Future<bool>>{};
  final _deletedPostIds = <String>{};
  final _saving = <String, Future<bool>>{};
  final _sending = <String>{};
  final _retired = <String, Future<void>>{};
  final _activating = <String, Future<void>>{};
  final _remoteTasks = <String, PostTask>{};
  List<StoredPostEntry> _local = [];
  List<OwnPostCard> _own = [];
  String? _ownCursor, _taskCursor;
  int _feedRequest = 0, _personalRequest = 0;
  int _publicationSequence = 0;
  PostPublicationNotice? _latestPublicationNotice;
  String? currentChannelId, feedCursor, feedError, personalError, errorMessage;
  bool feedLoading = false, personalLoading = false;
  List<PostCard> feedItems = [];
  List<PersonalPostItem> personalItems = [];
  ManagedIdentity? personalIdentity;

  String? get accountId => _accountId;
  int get authorityVersion => _epoch;
  PostPublicationNotice? get latestPublicationNotice =>
      available ? _latestPublicationNotice : null;
  bool isPostDeleted(String postId) =>
      available && _deletedPostIds.contains(postId);
  bool get busy => _pending > 0;
  bool get available =>
      !_disposed &&
      _accountId != null &&
      _token != null &&
      _sessions.isCurrentToken(_token!);
  bool editorCurrent(PostDraftEditor editor) =>
      available &&
      editor.accountId == _accountId &&
      editor.authorityVersion == _epoch;

  void _authorityChanged() {
    if (_disposed) return;
    final record = _authStore.current?.session;
    final permitted = record != null && _sessions.isCurrentToken(record.token);
    final token = permitted ? record.token : null;
    final account = permitted ? record.accountId : null;
    if (token == _token &&
        account == _accountId &&
        _sessionVersion == _sessions.authorityVersion) {
      return;
    }
    _sessionVersion = _sessions.authorityVersion;
    _token = token;
    _accountId = account;
    final epoch = ++_epoch;
    final old = _store;
    _store = null;
    if (old != null) {
      _retired[old.accountId] = old.close();
      unawaited(_retired[old.accountId]!.catchError((Object _) {}));
    }
    _local = [];
    _own = [];
    _remoteTasks.clear();
    _deletedPostIds.clear();
    _latestPublicationNotice = null;
    personalItems = [];
    personalIdentity = null;
    feedItems = [];
    currentChannelId = feedCursor = feedError = personalError = errorMessage =
        null;
    _ownCursor = _taskCursor = null;
    feedLoading = personalLoading = false;
    _publishing.clear();
    _deleting.clear();
    _checking.clear();
    _notify();
    if (account != null) {
      _opening = _activate(account, epoch);
      _activating[account] = _opening;
    } else {
      _opening = Future.value();
    }
  }

  Future<void> _activate(String account, int epoch) async {
    try {
      final store = await _openStore(account);
      if (_disposed || epoch != _epoch || account != _accountId) {
        await store.close();
        return;
      }
      _store = store;
      final entries = await store.list();
      if (epoch != _epoch) return;
      _local = entries;
      _rememberDeletedPosts(entries);
      _mergePersonal();
      _notify();
      // 恢复只核对已有命令，不重发 CREATE，也不自动替用户重试失败任务。
      for (final entry in _local.where(_needsQuery)) {
        unawaited(reconcile(entry.id));
      }
    } on Object {
      if (epoch == _epoch) {
        errorMessage = '本机内容存储不可用，已保留原数据。请重试。';
        _notify();
      }
    }
  }

  static bool _needsQuery(StoredPostEntry e) =>
      !e.isDraft && {'submitted', 'UNKNOWN', 'ACCEPTED'}.contains(e.state);
  static bool _unresolved(StoredPostEntry e) =>
      {'submitted', 'UNKNOWN', 'RESULT_EXPIRED'}.contains(e.state);

  Future<void> retryStorage() async {
    if (!available || _store != null) return;
    if (_storageRetrying) {
      await _opening;
      return;
    }
    _storageRetrying = true;
    final account = _accountId!;
    try {
      _opening = _activate(account, _epoch);
      _activating[account] = _opening;
      await _opening;
    } finally {
      _storageRetrying = false;
    }
  }

  Future<_PostAuthority> _authority({bool storage = false}) async {
    if (storage) await _opening;
    if (storage && available && _store == null) await retryStorage();
    if (!available) throw _StalePostAuthority();
    if (storage && _store == null) throw const PostStorageFailure();
    return _PostAuthority(_epoch, _token!, _accountId!, _store);
  }

  bool _current(_PostAuthority a) =>
      available &&
      a.epoch == _epoch &&
      a.token == _token &&
      a.accountId == _accountId;

  Future<T> _accept<T>(_PostAuthority a, PostResponse<T> response) async {
    if (!_current(a) ||
        !await _sessions.persistSessionMetadata(
          a.token,
          response.sessionExpiresAt,
          () => _current(a),
        ) ||
        !_current(a)) {
      throw _StalePostAuthority();
    }
    return response.value;
  }

  void _failure(Object error, [_PostAuthority? authority]) {
    if (error is _StalePostAuthority ||
        authority != null && !_current(authority)) {
      return;
    }
    if (error is AuthFailure) {
      if (authority != null && error.unauthorized) {
        _sessions.sessionUnauthorized(authority.token, error.code);
      } else if (authority != null &&
          error.kind == AuthFailureKind.unavailable) {
        _sessions.sessionUnavailable(authority.token);
      } else {
        errorMessage = '暂时无法读取身份，请重试。';
        _notify();
      }
      return;
    } else if (error is PostFailure) {
      if (error.kind == PostFailureKind.unauthorized) {
        if (authority != null) {
          _sessions.sessionUnauthorized(authority.token, error.code);
        }
        return;
      }
      if (error.kind == PostFailureKind.unavailable) {
        if (authority != null) _sessions.sessionUnavailable(authority.token);
        return;
      }
      errorMessage = error.kind == PostFailureKind.rejected
          ? _rejectionMessage(error.code)
          : '暂时无法核对结果，原操作已保留，请稍后核对。';
    } else if (error is PostStorageFailure || error is AuthStorageFailure) {
      errorMessage = '本机保存失败，内容仍保留在当前页面，请重试或复制。';
    } else {
      errorMessage = '暂时无法完成操作，请重试。';
    }
    _notify();
  }

  Future<void> loadFeed(String channelId, {bool more = false}) async {
    final request = ++_feedRequest;
    _PostAuthority? a;
    try {
      PostProtocol.resourceId(channelId);
      a = await _authority();
      if (more && (currentChannelId != channelId || feedCursor == null)) return;
      final cursor = more ? feedCursor : null;
      if (!more) {
        currentChannelId = channelId;
        feedItems = [];
        feedCursor = null;
      }
      feedLoading = true;
      feedError = null;
      _notify();
      final page = await _accept(
        a,
        await _api.feed(
          sessionToken: a.token,
          channelId: channelId,
          cursor: cursor,
        ),
      );
      if (request != _feedRequest || currentChannelId != channelId) return;
      if (page.items.any((p) => p.channelId != channelId)) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      final ids = (more ? feedItems : <PostCard>[])
          .map((p) => p.postId)
          .toSet();
      feedItems = [
        if (more) ...feedItems,
        ...page.items.where(
          (p) => !_deletedPostIds.contains(p.postId) && ids.add(p.postId),
        ),
      ];
      feedCursor = page.nextCursor;
    } catch (error) {
      _failure(error, a);
      if (a != null && _current(a) && request == _feedRequest) {
        feedError = '暂时无法加载帖子，请重试。';
      }
    } finally {
      if (a != null && _current(a) && request == _feedRequest) {
        feedLoading = false;
        _notify();
      }
    }
  }

  Future<PostDetail?> loadDetail(String postId) async {
    _PostAuthority? a;
    try {
      a = await _authority();
      if (_deletedPostIds.contains(postId)) return null;
      final post = await _accept(
        a,
        await _api.detail(sessionToken: a.token, postId: postId),
      );
      return _deletedPostIds.contains(postId) ? null : post;
    } catch (error) {
      _failure(error, a);
      return null;
    }
  }

  /// 身份管理返回时刷新已显示的公共投影，保留当前列表顺序与分页游标。
  Future<void> refreshKnownPosts() async {
    _PostAuthority? a;
    try {
      a = await _authority();
      final ids = feedItems.map((p) => p.postId).toList();
      for (final id in ids) {
        PostDetail? post;
        try {
          post = await _accept(
            a,
            await _api.detail(sessionToken: a.token, postId: id),
          );
        } on PostFailure catch (error) {
          if (error.statusCode != 404) rethrow;
        }
        if (!_current(a)) return;
        if (post == null) {
          feedItems = feedItems.where((p) => p.postId != id).toList();
        } else {
          feedItems = [
            for (final old in feedItems) old.postId == id ? post : old,
          ];
        }
      }
      _notify();
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<bool> canDelete(String postId) async {
    _PostAuthority? a;
    try {
      a = await _authority();
      if (_deletedPostIds.contains(postId)) return false;
      final result = await _accept(
        a,
        await _api.capabilities(sessionToken: a.token, postId: postId),
      );
      return result.canDelete;
    } catch (error) {
      if (error is! PostFailure || error.statusCode != 404) _failure(error, a);
      return false;
    }
  }

  Future<void> loadPersonal({bool more = false}) async {
    final request = ++_personalRequest;
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      personalLoading = true;
      personalError = null;
      _notify();
      final posts = !more || _ownCursor != null
          ? await _accept(
              a,
              await _api.ownPosts(
                sessionToken: a.token,
                cursor: more ? _ownCursor : null,
              ),
            )
          : null;
      final tasks = !more || _taskCursor != null
          ? await _accept(
              a,
              await _api.tasks(
                sessionToken: a.token,
                cursor: more ? _taskCursor : null,
              ),
            )
          : null;
      var local = await a.store!.list();
      final queriedTasks = <String, PostTask>{};
      // 已隐藏失败项不在分页中；点查已知任务，避免本机旧正文重新出现。
      for (final entry in local.where((e) => e.state == 'FAILED')) {
        final taskId = entry.data['taskId'] as String?;
        if (taskId == null) continue;
        final task = await _accept(
          a,
          await _api.task(sessionToken: a.token, taskId: taskId),
        );
        await _applyTask(a, entry, task);
        queriedTasks[task.taskId] = task;
      }
      local = await a.store!.list();
      final directory = await _identities.identities(a.token);
      final scoped = a;
      if (!await _sessions.persistSessionMetadata(
        a.token,
        directory.sessionExpiresAt,
        () => _current(scoped),
      )) {
        return;
      }
      final context = await _accept(
        a,
        await _api.composerContext(sessionToken: a.token),
      );
      if (!_current(a) || request != _personalRequest) return;
      final originals = directory.identities.where((i) => i.isOriginal);
      personalIdentity = originals.isNotEmpty
          ? originals.first
          : directory.identities
                .where((i) => i.id == context.defaultIdentityId)
                .firstOrNull;
      personalIdentity ??=
          (List<ManagedIdentity>.of(directory.identities)..sort((x, y) {
                final byTime = x.createdAt.compareTo(y.createdAt);
                return byTime != 0 ? byTime : x.id.compareTo(y.id);
              }))
              .firstOrNull;
      if (!more) {
        _own = [];
        _remoteTasks.clear();
      }
      final ids = _own.map((p) => p.post.postId).toSet();
      if (posts != null) {
        _own = [
          ..._own,
          ...posts.items.where(
            (p) =>
                !_deletedPostIds.contains(p.post.postId) &&
                ids.add(p.post.postId),
          ),
        ];
        _ownCursor = posts.nextCursor;
      }
      if (tasks != null) {
        for (final task in tasks.items) {
          _remoteTasks[task.taskId] = task;
        }
        _taskCursor = tasks.nextCursor;
      }
      // 点查晚于分页快照，旧分页不能覆盖更新的终态或尝试版本。
      _remoteTasks.addAll(queriedTasks);
      _local = local;
      _rememberDeletedPosts(local);
      _mergePersonal();
      for (final task in queriedTasks.values.where(
        (t) => t.state == PostTaskState.published,
      )) {
        unawaited(_insertPublished(a, task.postId));
      }
    } catch (error) {
      _failure(error, a);
      if (a != null && _current(a)) personalError = '暂时无法核对本人内容，请重试。';
    } finally {
      if (a != null && _current(a) && request == _personalRequest) {
        personalLoading = false;
        _notify();
      }
    }
  }

  bool get personalHasMore => _ownCursor != null || _taskCursor != null;

  void _mergePersonal() {
    // 删除后到达的旧本人页也不能把正文留回任务缓存。
    _remoteTasks.removeWhere(
      (_, task) => _deletedPostIds.contains(task.postId),
    );
    _own = _own
        .where((post) => !_deletedPostIds.contains(post.post.postId))
        .toList();
    final items = <PersonalPostItem>[];
    final knownTasks = <String>{};
    for (final entry in _local) {
      if (entry.data['isRetryBuffer'] == true ||
          _deletedPostIds.contains(entry.data['postId']) ||
          entry.data['abandoned'] == true ||
          {
            'PUBLISHED',
            'CANCELLED',
            'HIDDEN',
            'DELETED',
          }.contains(entry.state)) {
        continue;
      }
      final taskId = entry.data['taskId'] as String?;
      final task = taskId == null ? null : _remoteTasks[taskId];
      if (taskId != null) knownTasks.add(taskId);
      if (task != null && !task.visible) continue;
      items.add(
        PersonalPostItem(
          id: entry.id,
          title: task != null
              ? task.content?.title ?? '内容不可用'
              : entry.data['title'] as String? ?? '',
          sortAt:
              task?.serverSortAt ??
              DateTime.parse(entry.data['editedAt'] as String),
          local: entry,
          task: task,
        ),
      );
    }
    for (final task in _remoteTasks.values) {
      if (task.visible &&
          !_deletedPostIds.contains(task.postId) &&
          !knownTasks.contains(task.taskId)) {
        items.add(
          PersonalPostItem(
            id: 'task:${task.taskId}',
            title: task.content?.title ?? '内容不可用',
            sortAt: task.serverSortAt,
            task: task,
          ),
        );
      }
    }
    for (final post in _own) {
      items.add(
        PersonalPostItem(
          id: 'post:${post.post.postId}',
          title: post.post.title,
          sortAt: post.serverSortAt,
          post: post.post,
        ),
      );
    }
    items.sort((a, b) {
      final time = b.sortAt.compareTo(a.sortAt);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    personalItems = List.unmodifiable(items);
  }

  PostDraftEditor newDraft(String channelId) {
    if (!available) throw _StalePostAuthority();
    PostProtocol.resourceId(channelId);
    return PostDraftEditor(
      id: _newId(),
      channelId: channelId,
      accountId: _accountId!,
      authorityVersion: _epoch,
    );
  }

  Future<PostDraftEditor?> restoreDraft(String id) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final entry = await a.store!.get(id);
      if (!_current(a) ||
          entry == null ||
          !entry.isDraft ||
          entry.data['isRetryBuffer'] == true) {
        return null;
      }
      return PostDraftEditor(
        id: entry.id,
        channelId: entry.data['channelId'] as String,
        accountId: a.accountId,
        authorityVersion: a.epoch,
        identityId: entry.data['identityId'] as String?,
        title: entry.data['title'] as String,
        body: entry.data['body'] as String,
        revision: entry.revision,
        persisted: true,
      )..saved = true;
    } catch (error) {
      _failure(error, a);
      return null;
    }
  }

  Map<String, dynamic> _editorData(PostDraftEditor e) => {
    'channelId': e.channelId,
    'identityId': e.identityId,
    'title': e.title,
    'body': e.body,
    'editedAt': _clock().toUtc().toIso8601String(),
    if (e.taskId != null) 'taskId': e.taskId,
    if (e.attemptVersion != null) 'attemptVersion': e.attemptVersion,
  };

  Future<bool> saveDraft(PostDraftEditor e) {
    if (e.submitted) return Future.value(false);
    final previous = _saving[e.id];
    final future = _saveDraft(e, previous);
    _saving[e.id] = future;
    future.whenComplete(() {
      if (identical(_saving[e.id], future)) _saving.remove(e.id);
    });
    return future;
  }

  Future<bool> _saveDraft(PostDraftEditor e, Future<bool>? previous) async {
    if (previous != null) await previous;
    if (!editorCurrent(e) || e.submitted) return false;
    e.saving = true;
    e.error = null;
    final data = _editorData(e);
    try {
      final a = await _authority(storage: true);
      if (!editorCurrent(e)) return false;
      // 空白新稿不落盘，也不能覆盖其他草稿。
      if (!e.persisted &&
          !PostContentRules.hasMeaningfulText(e.title) &&
          !PostContentRules.hasMeaningfulText(e.body)) {
        e.saved = true;
        return true;
      }
      if (e.isRetry) data['isRetryBuffer'] = true;
      final id = e.bufferId ?? e.id;
      final revision = e.isRetry ? e.bufferRevision : e.revision;
      final entry = e.persisted
          ? await a.store!.saveDraft(id, revision, data)
          : await a.store!.createDraft(id, data);
      if (!_current(a) || !editorCurrent(e)) return false;
      if (e.isRetry) {
        e.bufferRevision = entry.revision;
      } else {
        e.revision = entry.revision;
      }
      e.persisted = true;
      e.saved =
          e.title == data['title'] &&
          e.body == data['body'] &&
          e.identityId == data['identityId'];
      await _refreshLocal(a);
      return true;
    } catch (error) {
      if (editorCurrent(e)) {
        e.error = '保存失败，请重试、复制文字，或明确放弃退出。';
        _failure(error);
      }
      return false;
    } finally {
      e.saving = false;
      _notify();
    }
  }

  Future<bool> discardDraft(PostDraftEditor e) async {
    if (!editorCurrent(e) || e.submitted) return false;
    _PostAuthority? a;
    try {
      final prior = _saving[e.id];
      if (prior != null) await prior;
      a = await _authority(storage: true);
      if (!editorCurrent(e)) return false;
      if (e.persisted) {
        await a.store!.deleteDraft(
          e.bufferId ?? e.id,
          e.isRetry ? e.bufferRevision : e.revision,
        );
      }
      if (!_current(a)) return false;
      e.persisted = false;
      e.revision = 0;
      await _refreshLocal(a);
      return true;
    } catch (error) {
      _failure(error, a);
      return false;
    }
  }

  Future<List<ManagedIdentity>> prepareComposer(PostDraftEditor e) async {
    _PostAuthority? a;
    try {
      if (!editorCurrent(e)) return [];
      a = await _authority();
      final directory = await _identities.identities(a.token);
      final scoped = a;
      if (!_current(a) ||
          !await _sessions.persistSessionMetadata(
            a.token,
            directory.sessionExpiresAt,
            () => _current(scoped),
          )) {
        return [];
      }
      final context = await _accept(
        a,
        await _api.composerContext(sessionToken: a.token),
      );
      if (!editorCurrent(e)) return [];
      if (e.isRetry) {
        if (!directory.identities.any((i) => i.id == e.identityId)) {
          e.error = '原发布身份已失效，此任务不能更换身份重试。';
          return [];
        }
      } else if (!directory.identities.any((i) => i.id == e.identityId)) {
        e.identityId = context.defaultIdentityId;
      }
      return directory.identities;
    } on AuthFailure catch (error) {
      if (a != null && _current(a)) {
        if (error.unauthorized) {
          _sessions.sessionUnauthorized(a.token, error.code);
        } else {
          _sessions.sessionUnavailable(a.token);
        }
      }
      return [];
    } catch (error) {
      _failure(error, a);
      return [];
    }
  }

  Future<bool> publish(PostDraftEditor e) async {
    if (!editorCurrent(e) || e.submitted || !_publishing.add(e.id)) {
      return false;
    }
    _PostAuthority? a;
    try {
      PostContentRules.validate(e.title, e.body);
      if (e.identityId == null) {
        e.error = '请先选择有效身份。';
        return false;
      }
      if (!await saveDraft(e)) return false;
      a = await _authority(storage: true);
      if (!editorCurrent(e)) return false;
      StoredPostEntry? retryOriginal;
      if (e.isRetry) {
        final original = await a.store!.get(e.id);
        final task = await _accept(
          a,
          await _api.task(sessionToken: a.token, taskId: e.taskId!),
        );
        if (original == null ||
            _unresolved(original) ||
            !task.canRetry ||
            task.state != PostTaskState.failed ||
            task.attemptVersion != e.attemptVersion ||
            task.channelId != e.channelId ||
            task.identityId != e.identityId) {
          e.error = '请先核对原任务；重试只能使用原身份、通道和当前失败版本。';
          return false;
        }
        e.revision = original.revision;
        retryOriginal = original;
      }
      final payload = e.isRetry
          ? <String, dynamic>{
              'taskId': e.taskId!,
              'expectedAttemptVersion': e.attemptVersion!,
              'title': e.title,
              'body': e.body,
            }
          : <String, dynamic>{
              'channelId': e.channelId,
              'identityId': e.identityId!,
              'title': e.title,
              'body': e.body,
            };
      final operation = e.isRetry ? PostOperation.retry : PostOperation.create;
      final digest = PostProtocol.digest(
        e.isRetry
            ? PostProtocol.retry(
                taskId: e.taskId!,
                expectedAttemptVersion: e.attemptVersion!,
                title: e.title,
                body: e.body,
              )
            : PostProtocol.create(
                channelId: e.channelId,
                identityId: e.identityId!,
                title: e.title,
                body: e.body,
              ),
      );
      final intent = StoredPostIntent(
        commandId: _newId(),
        operation: operation.wire,
        digest: digest,
        payload: payload,
      );
      final data = <String, dynamic>{
        if (retryOriginal != null) ...retryOriginal.data,
        ..._editorData(e),
        'commandState': 'UNKNOWN',
      };
      final entry = e.isRetry
          ? await a.store!.appendIntent(e.id, e.revision, intent, data)
          : await a.store!.submitDraft(e.id, e.revision, intent, data);
      if (!_current(a) || !editorCurrent(e)) return false;
      e.revision = entry.revision;
      e.submitted = true;
      e.saved = true;
      if (e.isRetry && e.persisted) {
        // 提交意图已落盘；旧编辑缓冲只含该尝试的副本，不能成为第二次提交。
        try {
          await a.store!.deleteDraft(e.bufferId!, e.bufferRevision);
        } on PostStorageFailure {
          // 重启后以未决命令围栏阻止恢复这个缓冲；不重复发送来补偿清理失败。
        }
      }
      await _refreshLocal(a);
      // 只有原提交上下文确实写入 SQLite 后，确认页才可以返回通道。
      unawaited(_send(a, entry));
      return true;
    } catch (error) {
      if (editorCurrent(e)) {
        e.error = '未能保存发布操作，内容仍保留，请重试。';
        _failure(error, a);
      }
      return false;
    } finally {
      _publishing.remove(e.id);
      _notify();
    }
  }

  void _rememberDeletedPosts(List<StoredPostEntry> entries) {
    for (final entry in entries) {
      final postId = entry.data['postId'];
      if (entry.state == 'DELETED' && postId is String) {
        _markPostDeleted(postId);
      }
    }
  }

  void _markPostDeleted(String postId) {
    _deletedPostIds.add(postId);
    if (_latestPublicationNotice?.postId == postId) {
      _latestPublicationNotice = null;
    }
    feedItems = feedItems.where((p) => p.postId != postId).toList();
    _own = _own.where((p) => p.post.postId != postId).toList();
    _remoteTasks.removeWhere((_, task) => task.postId == postId);
  }

  bool _isLocalPublicationTransition(StoredPostEntry entry, PostTask task) {
    if (task.state != PostTaskState.published ||
        !{'submitted', 'UNKNOWN', 'ACCEPTED'}.contains(entry.state) ||
        entry.intents.isEmpty) {
      return false;
    }
    final intent = entry.intents.last;
    final int? version = switch (intent.operation) {
      'CREATE' => 1,
      'RETRY' =>
        (intent.payload['expectedAttemptVersion'] as int?) == null
            ? null
            : (intent.payload['expectedAttemptVersion'] as int) + 1,
      _ => null,
    };
    return version == task.attemptVersion;
  }

  void _noticePublication(_PostAuthority a, PostTask task) {
    if (!_current(a) || _deletedPostIds.contains(task.postId)) return;
    _latestPublicationNotice = PostPublicationNotice(
      sequence: ++_publicationSequence,
      postId: task.postId,
      channelId: task.channelId,
    );
    _notify();
  }

  Future<void> _refreshLocal(_PostAuthority a) async {
    final entries = await a.store!.list();
    if (!_current(a)) return;
    _local = entries;
    _rememberDeletedPosts(entries);
    _mergePersonal();
    _notify();
  }

  Future<void> _send(_PostAuthority a, StoredPostEntry entry) async {
    final intent = entry.intents.last;
    if (!_current(a) || !_sending.add(intent.commandId)) return;
    _pending++;
    _notify();
    try {
      final p = intent.payload;
      final response = switch (intent.operation) {
        'CREATE' => await _api.create(
          sessionToken: a.token,
          commandId: intent.commandId,
          channelId: p['channelId'] as String,
          identityId: p['identityId'] as String,
          title: p['title'] as String,
          body: p['body'] as String,
        ),
        'RETRY' => await _api.retry(
          sessionToken: a.token,
          commandId: intent.commandId,
          taskId: p['taskId'] as String,
          expectedAttemptVersion: p['expectedAttemptVersion'] as int,
          title: p['title'] as String,
          body: p['body'] as String,
        ),
        'CANCEL' => await _api.cancel(
          sessionToken: a.token,
          commandId: intent.commandId,
          taskId: p['taskId'] as String,
          expectedAttemptVersion: p['expectedAttemptVersion'] as int,
        ),
        'HIDE_TASK' => await _api.hide(
          sessionToken: a.token,
          commandId: intent.commandId,
          taskId: p['taskId'] as String,
          expectedAttemptVersion: p['expectedAttemptVersion'] as int,
        ),
        'DELETE_POST' => await _api.delete(
          sessionToken: a.token,
          commandId: intent.commandId,
          postId: p['postId'] as String,
        ),
        _ => throw const FormatException('Unknown original operation'),
      };
      await _applyResult(a, entry.id, intent, await _accept(a, response));
    } catch (error) {
      // mutation 的409也先核对原回执；超时、503或写盘失败都不能变成新草稿。
      _failure(error, a);
      if (_current(a)) unawaited(reconcile(entry.id));
    } finally {
      _sending.remove(intent.commandId);
      _pending--;
      _notify();
    }
  }

  Future<void> reconcile(String id) async {
    final pending = _checking[id];
    if (pending != null) return pending;
    final future = _reconcile(id);
    _checking[id] = future;
    try {
      await future;
    } finally {
      if (identical(_checking[id], future)) _checking.remove(id);
    }
  }

  Future<void> _reconcile(String id) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final entry = await a.store!.get(id);
      if (!_current(a) ||
          entry == null ||
          entry.isDraft ||
          entry.intents.isEmpty) {
        return;
      }
      if ({
        'HIDDEN',
        'DELETED',
        'CANCELLED',
        'NOT_ACCEPTED',
      }.contains(entry.state)) {
        return;
      }
      final intent = entry.intents.last;
      if (intent.operation == 'TASK_ANCHOR') {
        await _applyTask(
          a,
          entry,
          await _accept(
            a,
            await _api.task(
              sessionToken: a.token,
              taskId: entry.data['taskId'] as String,
            ),
          ),
        );
        return;
      }
      final result = await _accept(
        a,
        await _api.commandResult(
          sessionToken: a.token,
          commandId: intent.commandId,
        ),
      );
      await _applyResult(a, id, intent, result);
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<void> seal(String id) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final entry = await a.store!.get(id);
      if (!_current(a) ||
          entry == null ||
          entry.isDraft ||
          entry.intents.isEmpty ||
          !{'submitted', 'UNKNOWN'}.contains(entry.state)) {
        return;
      }
      final intent = entry.intents.last;
      if (intent.operation == 'TASK_ANCHOR') return;
      final operation = PostOperation.values.firstWhere(
        (v) => v.wire == intent.operation,
      );
      final result = await _accept(
        a,
        await _api.seal(
          sessionToken: a.token,
          commandId: intent.commandId,
          operation: operation,
          requestDigest: intent.digest,
        ),
      );
      await _applyResult(a, id, intent, result);
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<void> _applyResult(
    _PostAuthority a,
    String id,
    StoredPostIntent intent,
    PostCommandResult result,
  ) async {
    if (!_current(a)) return;
    final entry = await a.store!.get(id);
    if (!_current(a) ||
        entry == null ||
        entry.intents.last.commandId != intent.commandId) {
      return;
    }
    if (result.operation != null &&
        result.operation!.wire != intent.operation) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    if (result.taskId != null &&
            intent.payload['taskId'] != null &&
            result.taskId != intent.payload['taskId'] ||
        result.postId != null &&
            intent.payload['postId'] != null &&
            result.postId != intent.payload['postId']) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    var state = switch (result.state) {
      PostCommandState.unknownNotObserved => 'UNKNOWN',
      PostCommandState.accepted => 'ACCEPTED',
      PostCommandState.committed =>
        result.taskState?.name.toUpperCase() ??
            (intent.operation == 'HIDE_TASK' ? 'HIDDEN' : 'DELETED'),
      PostCommandState.rejected => 'REJECTED',
      PostCommandState.notAccepted => 'NOT_ACCEPTED',
      PostCommandState.resultExpired => 'RESULT_EXPIRED',
    };
    var data = Map<String, dynamic>.from(entry.data)
      ..['commandState'] = result.state.name
      ..['errorCode'] = result.errorCode;
    if (result.taskId != null) data['taskId'] = result.taskId;
    if (result.postId != null) data['postId'] = result.postId;
    if (result.attemptVersion != null) {
      data['attemptVersion'] = result.attemptVersion;
    }
    // 初始ACCEPTED是历史回执；当前终态必须另读 task，不能回退已有PUBLISHED。
    final taskId = data['taskId'] as String?;
    PostTask? observedTask;
    if (taskId != null &&
        result.state != PostCommandState.unknownNotObserved &&
        result.state != PostCommandState.resultExpired) {
      final task = await _accept(
        a,
        await _api.task(sessionToken: a.token, taskId: taskId),
      );
      if (task.postId != data['postId'] ||
          task.identityId != data['identityId'] ||
          task.channelId != data['channelId']) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      observedTask = task;
      state = task.visible
          ? task.state.name.toUpperCase()
          : task.state == PostTaskState.published
          ? 'PUBLISHED'
          : 'HIDDEN';
      data['attemptVersion'] = task.attemptVersion;
      data['editedAt'] = task.serverSortAt.toIso8601String();
      if (!task.contentAvailable && state == 'FAILED') {
        state = 'CONTENT_UNAVAILABLE';
      }
      if (!task.contentAvailable) {
        data.remove('title');
        data.remove('body');
      }
    }
    if ({
      'PUBLISHED',
      'CANCELLED',
      'HIDDEN',
      'DELETED',
      'CONTENT_UNAVAILABLE',
    }.contains(state)) {
      data.remove('title');
      data.remove('body');
    }
    if (!_current(a)) return;
    // 同一命令的并发核对可遇CAS竞争；下次核对读取最新revision即可，不重发。
    if ({
      'PUBLISHED',
      'CANCELLED',
      'HIDDEN',
      'DELETED',
      'CONTENT_UNAVAILABLE',
    }.contains(state)) {
      await a.store!.compactTerminal(id, entry.revision, state, data);
    } else {
      await a.store!.recordResult(id, entry.revision, state, data);
    }
    if (!_current(a)) return;
    if (observedTask != null) _remoteTasks[observedTask.taskId] = observedTask;
    await _refreshLocal(a);
    if (!_current(a)) return;
    if (result.state == PostCommandState.accepted &&
        observedTask != null &&
        _isLocalPublicationTransition(entry, observedTask)) {
      _noticePublication(a, observedTask);
    }
    if (!_current(a)) return;
    final currentTask = taskId == null ? null : _remoteTasks[taskId];
    if (currentTask != null) await _dropRetryBuffers(a, currentTask);
    if (!_current(a)) return;
    if (state == 'DELETED') {
      _markPostDeleted(data['postId'] as String);
      _mergePersonal();
      _notify();
    } else if (state == 'PUBLISHED') {
      unawaited(_insertPublished(a, data['postId'] as String));
    }
  }

  Future<void> _applyTask(
    _PostAuthority a,
    StoredPostEntry entry,
    PostTask task,
  ) async {
    if (!_current(a) ||
        task.taskId != entry.data['taskId'] ||
        task.postId != entry.data['postId'] ||
        task.identityId != entry.data['identityId'] ||
        task.channelId != entry.data['channelId']) {
      throw _StalePostAuthority();
    }
    final data = Map<String, dynamic>.from(entry.data)
      ..['attemptVersion'] = task.attemptVersion
      ..['editedAt'] = task.serverSortAt.toIso8601String();
    final state = task.visible
        ? task.state.name.toUpperCase()
        : task.state == PostTaskState.published
        ? 'PUBLISHED'
        : 'HIDDEN';
    if (!task.contentAvailable && state == 'FAILED') {
      await a.store!.compactTerminal(
        entry.id,
        entry.revision,
        'CONTENT_UNAVAILABLE',
        data,
      );
    } else if ({'PUBLISHED', 'CANCELLED', 'HIDDEN'}.contains(state)) {
      await a.store!.compactTerminal(entry.id, entry.revision, state, data);
    } else {
      await a.store!.recordResult(entry.id, entry.revision, state, data);
    }
    if (!_current(a)) return;
    _remoteTasks[task.taskId] = task;
    await _refreshLocal(a);
    if (!_current(a)) return;
    if (entry.state == 'ACCEPTED' &&
        _isLocalPublicationTransition(entry, task)) {
      _noticePublication(a, task);
    }
    if (!_current(a)) return;
    await _dropRetryBuffers(a, task);
    if (!_current(a)) return;
    if (state == 'PUBLISHED') unawaited(_insertPublished(a, task.postId));
  }

  Future<void> _dropRetryBuffers(_PostAuthority a, PostTask task) async {
    final buffers = (await a.store!.list())
        .where(
          (e) =>
              e.isDraft &&
              e.data['isRetryBuffer'] == true &&
              e.data['taskId'] == task.taskId &&
              (!task.contentAvailable ||
                  task.state != PostTaskState.failed ||
                  e.data['attemptVersion'] != task.attemptVersion),
        )
        .toList();
    if (!_current(a)) return;
    for (final buffer in buffers) {
      if (!_current(a)) return;
      await a.store!.deleteDraft(buffer.id, buffer.revision);
    }
  }

  Future<void> _insertPublished(_PostAuthority a, String postId) async {
    try {
      if (!_current(a) || _deletedPostIds.contains(postId)) return;
      final post = await _accept(
        a,
        await _api.detail(sessionToken: a.token, postId: postId),
      );
      if (_deletedPostIds.contains(postId)) return;
      if (currentChannelId == post.channelId) {
        final request = _feedRequest;
        final latest = await _accept(
          a,
          await _api.feed(sessionToken: a.token, channelId: post.channelId),
        );
        if (_deletedPostIds.contains(postId)) return;
        if (request == _feedRequest &&
            currentChannelId == post.channelId &&
            latest.items.any((p) => p.postId == postId)) {
          // 服务器给出最新页顺序；历史回执不把旧帖顶到首位，不改变原分页游标。
          final visibleItems = latest.items
              .where((p) => !_deletedPostIds.contains(p.postId))
              .toList();
          final prefixIds = visibleItems.map((p) => p.postId).toSet();
          feedItems = [
            ...visibleItems,
            ...feedItems.where((p) => !prefixIds.contains(p.postId)),
          ];
        }
      }
      // 本人task证明归属，当前公共作者证明身份仍有效；第一页缺席不等于失去资格。
      final ownedTask = _remoteTasks.values.where(
        (task) =>
            task.postId == postId && task.state == PostTaskState.published,
      );
      _own = [
        if (ownedTask.isNotEmpty && post.author.state == PostAuthorState.active)
          OwnPostCard(post: post, serverSortAt: post.publishedAt),
        ..._own.where((p) => p.post.postId != postId),
      ];
      _mergePersonal();
      _notify();
    } catch (error) {
      _failure(error, a);
    }
  }

  /// 身份资料变化只刷新已加载内容；保留本人分页游标和阅读位置。
  Future<void> refreshPersonalProjections() async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final ownIds = _own.map((p) => p.post.postId).toList();
      for (final id in ownIds) {
        PostDetail? post;
        try {
          post = await _accept(
            a,
            await _api.detail(sessionToken: a.token, postId: id),
          );
        } on PostFailure catch (error) {
          if (error.statusCode != 404) rethrow;
        }
        if (!_current(a)) return;
        _own = [
          for (final old in _own)
            if (old.post.postId != id)
              old
            else if (post != null &&
                post.author.state == PostAuthorState.active)
              OwnPostCard(post: post, serverSortAt: post.publishedAt),
        ];
      }
      for (final taskId in _remoteTasks.keys.toList()) {
        final task = await _accept(
          a,
          await _api.task(sessionToken: a.token, taskId: taskId),
        );
        final matching = (await a.store!.list()).where(
          (e) => !e.isDraft && e.data['taskId'] == taskId,
        );
        if (matching.isNotEmpty && !_unresolved(matching.first)) {
          await _applyTask(a, matching.first, task);
        } else if (_current(a)) {
          _remoteTasks[taskId] = task;
        }
      }
      final directory = await _identities.identities(a.token);
      final scoped = a;
      if (!await _sessions.persistSessionMetadata(
        a.token,
        directory.sessionExpiresAt,
        () => _current(scoped),
      )) {
        return;
      }
      final context = await _accept(
        a,
        await _api.composerContext(sessionToken: a.token),
      );
      if (!_current(a)) return;
      final originals = directory.identities.where((i) => i.isOriginal);
      final ordered = List<ManagedIdentity>.of(directory.identities)
        ..sort((x, y) {
          final byTime = x.createdAt.compareTo(y.createdAt);
          return byTime != 0 ? byTime : x.id.compareTo(y.id);
        });
      personalIdentity =
          originals.firstOrNull ??
          directory.identities
              .where((i) => i.id == context.defaultIdentityId)
              .firstOrNull ??
          ordered.firstOrNull;
      _mergePersonal();
      _notify();
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<PostDraftEditor?> editFailedTask(String taskId) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final task = await _accept(
        a,
        await _api.task(sessionToken: a.token, taskId: taskId),
      );
      if (!task.canRetry ||
          task.state != PostTaskState.failed ||
          task.content == null) {
        return null;
      }
      final entry = await _entryForTask(a, task);
      if (!_current(a)) return null;
      if (_unresolved(entry)) {
        await reconcile(entry.id);
        errorMessage = '原重试结果尚未核对完成，请先核对，不能另发新尝试。';
        _notify();
        return null;
      }
      final buffer = await a.store!.findRetryBuffer(
        task.taskId,
        task.attemptVersion,
      );
      if (!_current(a)) return null;
      final bufferId = buffer?.id ?? _newId();
      return PostDraftEditor(
        id: entry.id,
        channelId: task.channelId,
        accountId: a.accountId,
        authorityVersion: a.epoch,
        identityId: task.identityId,
        title: buffer?.data['title'] as String? ?? task.content!.title,
        body: buffer?.data['body'] as String? ?? task.content!.body,
        revision: entry.revision,
        persisted: buffer != null,
        isRetry: true,
        taskId: task.taskId,
        attemptVersion: task.attemptVersion,
        bufferId: bufferId,
        bufferRevision: buffer?.revision ?? 0,
      )..saved = buffer != null;
    } catch (error) {
      _failure(error, a);
      return null;
    }
  }

  Future<StoredPostEntry> _entryForTask(_PostAuthority a, PostTask task) async {
    final entries = await a.store!.list();
    if (!_current(a)) throw _StalePostAuthority();
    final match = entries.where(
      (e) =>
          !e.isDraft &&
          e.data['isRetryBuffer'] != true &&
          e.data['taskId'] == task.taskId,
    );
    if (match.isNotEmpty) return match.first;
    // 跨设备只有任务事实时，先创建本地维护锚点；它不能被恢复为普通草稿。
    final id = _newId();
    final data = <String, dynamic>{
      'channelId': task.channelId,
      'identityId': task.identityId,
      'title': task.content?.title ?? '',
      'body': task.content?.body ?? '',
      'editedAt': task.serverSortAt.toIso8601String(),
      'taskId': task.taskId,
      'postId': task.postId,
      'attemptVersion': task.attemptVersion,
    };
    final anchor = StoredPostIntent(
      commandId: _newId(),
      operation: 'TASK_ANCHOR',
      digest: PostProtocol.digest(
        PostProtocol.cancel(
          taskId: task.taskId,
          expectedAttemptVersion: task.attemptVersion,
        ),
      ),
      payload: {'taskId': task.taskId},
    );
    return a.store!.createSubmitted(
      id,
      anchor,
      data,
      state: task.state.name.toUpperCase(),
    );
  }

  Future<void> cancelTask(String taskId) => _taskCommand(taskId, false);
  Future<void> hideTask(String taskId) => _taskCommand(taskId, true);
  Future<void> _taskCommand(String taskId, bool hide) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final task = await _accept(
        a,
        await _api.task(sessionToken: a.token, taskId: taskId),
      );
      if (hide ? !task.canHide : !task.canCancel) return;
      final entry = await _entryForTask(a, task);
      if (!_current(a)) return;
      if (_unresolved(entry)) {
        await reconcile(entry.id);
        return;
      }
      final intent = StoredPostIntent(
        commandId: _newId(),
        operation: hide ? 'HIDE_TASK' : 'CANCEL',
        digest: PostProtocol.digest(
          hide
              ? PostProtocol.hide(
                  taskId: task.taskId,
                  expectedAttemptVersion: task.attemptVersion,
                )
              : PostProtocol.cancel(
                  taskId: task.taskId,
                  expectedAttemptVersion: task.attemptVersion,
                ),
        ),
        payload: {
          'taskId': task.taskId,
          'expectedAttemptVersion': task.attemptVersion,
        },
      );
      final next = await a.store!.appendIntent(
        entry.id,
        entry.revision,
        intent,
        Map<String, dynamic>.from(entry.data)..['commandState'] = 'UNKNOWN',
      );
      if (!_current(a)) return;
      await _refreshLocal(a);
      await _send(a, next);
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<bool> deletePost(String postId) {
    final pending = _deleting[postId];
    if (pending != null) return pending;
    final future = _deletePost(postId);
    _deleting[postId] = future;
    future.whenComplete(() {
      if (identical(_deleting[postId], future)) _deleting.remove(postId);
    });
    return future;
  }

  Future<bool> _deletePost(String postId) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      if (_deletedPostIds.contains(postId)) return true;
      final entries = await a.store!.list();
      if (!_current(a)) return false;
      final deleted = entries.any(
        (e) => e.data['postId'] == postId && e.state == 'DELETED',
      );
      if (deleted) {
        _markPostDeleted(postId);
        _mergePersonal();
        _notify();
        return true;
      }
      final unresolved = entries.where(
        (e) =>
            e.data['postId'] == postId &&
            e.intents.isNotEmpty &&
            e.intents.last.operation == 'DELETE_POST' &&
            _unresolved(e),
      );
      if (unresolved.isNotEmpty) {
        await reconcile(unresolved.first.id);
        final resolved = await a.store!.get(unresolved.first.id);
        return _current(a) && resolved?.state == 'DELETED';
      }
      if (!await canDelete(postId) || !_current(a)) return false;
      final id = _newId();
      final data = <String, dynamic>{
        'postId': postId,
        'editedAt': _clock().toUtc().toIso8601String(),
        'title': '删除结果待核对',
        'body': '',
      };
      final intent = StoredPostIntent(
        commandId: _newId(),
        operation: 'DELETE_POST',
        digest: PostProtocol.digest(PostProtocol.delete(postId: postId)),
        payload: {'postId': postId},
      );
      final entry = await a.store!.createSubmitted(id, intent, data);
      await _send(a, entry);
      final result = await a.store!.get(id);
      return _current(a) && result?.state == 'DELETED';
    } catch (error) {
      _failure(error, a);
      return false;
    }
  }

  /// 明确未受理的 CREATE 才可复制为新编辑；原命令防重事实永久保留。
  Future<PostDraftEditor?> recoverUnaccepted(String id) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final entry = await a.store!.get(id);
      if (!_current(a) ||
          entry == null ||
          entry.intents.last.operation != 'CREATE' ||
          !{'NOT_ACCEPTED', 'REJECTED'}.contains(entry.state) ||
          entry.data['abandoned'] == true) {
        return null;
      }
      final editor = newDraft(entry.data['channelId'] as String)
        ..title = entry.data['title'] as String? ?? ''
        ..body = entry.data['body'] as String? ?? ''
        ..identityId = entry.data['identityId'] as String?;
      if (!await saveDraft(editor)) return null;
      if (!_current(a)) return null;
      await a.store!.compactTerminal(
        id,
        entry.revision,
        'NOT_ACCEPTED',
        Map<String, dynamic>.from(entry.data)..['abandoned'] = true,
      );
      await _refreshLocal(a);
      return editor;
    } catch (error) {
      _failure(error, a);
      return null;
    }
  }

  Future<void> discardUnaccepted(String id) async {
    _PostAuthority? a;
    try {
      a = await _authority(storage: true);
      final entry = await a.store!.get(id);
      if (!_current(a) ||
          entry == null ||
          entry.intents.last.operation != 'CREATE' ||
          !{'NOT_ACCEPTED', 'REJECTED'}.contains(entry.state)) {
        return;
      }
      await a.store!.compactTerminal(
        id,
        entry.revision,
        'NOT_ACCEPTED',
        Map<String, dynamic>.from(entry.data)..['abandoned'] = true,
      );
      await _refreshLocal(a);
    } catch (error) {
      _failure(error, a);
    }
  }

  /// 只由认证流程持久确认正式关闭后调用；普通退出和冻结不会到这里。
  Future<void> purgeClosedAccount(String originalAccountId) async {
    await _activating[originalAccountId];
    await _retired[originalAccountId];
    final current = _store;
    if (_purgeStore != null) {
      if (current?.accountId == originalAccountId) {
        _store = null;
        await current!.close();
      }
      await _purgeStore(originalAccountId);
      return;
    }
    if (current != null && current.accountId == originalAccountId) {
      await current.purgeClosedAccount();
      _local = [];
      personalItems = [];
      _notify();
    } else {
      final store = await _openStore(originalAccountId);
      try {
        await store.purgeClosedAccount();
      } finally {
        await store.close();
      }
    }
  }

  static String _rejectionMessage(String? code) => switch (code) {
    'POST_IDENTITY_UNAVAILABLE' => '原身份已失效，请核对任务或重新选择草稿身份。',
    'TASK_NOT_RETRYABLE' => '当前任务不能重试，请核对最新状态。',
    'POSTING_RESTRICTED' || 'ACCOUNT_CLOSING' => '当前暂不能发布，原操作已保留。',
    'POST_CHANNEL_UNAVAILABLE' => '当前通道不可用。',
    _ => '服务端未接受这次操作，请核对原结果。',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller?.cancel();
    _epoch++;
    _sessions.removeListener(_authorityChanged);
    _authStore.removeListener(_authorityChanged);
    final store = _store;
    _store = null;
    if (store != null) unawaited(store.close().catchError((Object _) {}));
    super.dispose();
  }
}
