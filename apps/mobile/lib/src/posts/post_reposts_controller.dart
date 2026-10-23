part of 'post_controller.dart';

class PostRepostState {
  PostRepostSnapshot? value;
  bool loading = false, sending = false, uncertain = false;
  String? error;
  String? pendingIdentity, expectedVersion;
  bool? desired;
  int revision = 0;
  bool get unresolved => pendingIdentity != null;
  bool get reposted => value?.items.isNotEmpty ?? false;
}

extension PostRepostsController on PostController {
  bool get supportsReposts => _api is PostRepostsApi;
  PostRepostsApi get _repostsApi => _api as PostRepostsApi;
  PostRepostState repostState(String postId) =>
      _reposts.putIfAbsent(postId, PostRepostState.new);
  List<RepostedPost> get repostItems => List.unmodifiable(
    _repostItems.map(
      (item) => _deletedPostIds.contains(item.postId)
          ? RepostedPost(
              postId: item.postId,
              identityId: item.identityId,
              repostedAt: item.repostedAt,
              post: null,
            )
          : item,
    ),
  );
  List<String> get unresolvedRepostIds => List.unmodifiable(
    _reposts.entries.where((e) => e.value.unresolved).map((e) => e.key),
  );
  String? get repostCursor => _repostCursor;
  String? get repostListError => _repostListError;
  bool get repostListLoading => _repostListLoading;
  bool _repostCurrent(int authority) =>
      available && authority == _epoch && supportsReposts;

  void _clearReposts() {
    _reposts.clear();
    _repostItems = [];
    _repostCursor = null;
    _repostListError = null;
    _repostListLoading = false;
    _repostListOpened = false;
    _repostListRevision++;
  }

  Future<List<ManagedIdentity>> repostIdentities({
    required int authorityVersion,
  }) async {
    if (!_repostCurrent(authorityVersion)) return [];
    _PostAuthority? a;
    try {
      a = await _authority();
      final directory = await _identities.identities(a.token);
      if (!_current(a) ||
          !await _sessions.persistSessionMetadata(
            a.token,
            directory.sessionExpiresAt,
            () => _current(a!),
          )) {
        return [];
      }
      if (!_current(a)) return [];
      return directory.identities;
    } catch (error) {
      if (a != null && _current(a)) _failure(error, a);
      rethrow;
    }
  }

  Future<void> loadRepostState(
    String id, {
    required int authorityVersion,
  }) async {
    if (!_repostCurrent(authorityVersion)) return;
    final state = repostState(id);
    if (state.unresolved) return;
    final ticket = ++state.revision;
    state.loading = true;
    state.error = null;
    _notify();
    _PostAuthority? a;
    try {
      a = await _authority();
      final response = await _repostsApi.postReposts(
        sessionToken: a.token,
        postId: id,
      );
      final actual = await _accept(a, response);
      if (ticket != state.revision || state.unresolved) return;
      if (response.interactionVersion == null) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      state.value = actual;
    } catch (error) {
      if (_repostCurrent(authorityVersion) && ticket == state.revision) {
        state.error = '转帖状态读取失败，请重试。';
        _propagateFeedAuthorityFailure(error, a);
      }
    } finally {
      if (_repostCurrent(authorityVersion) && ticket == state.revision) {
        state.loading = false;
        _notify();
      }
    }
  }

  Future<void> loadReposts({
    required int authorityVersion,
    bool more = false,
  }) async {
    if (!_repostCurrent(authorityVersion)) return;
    _repostListOpened = true;
    if (_reposts.values.any((s) => s.unresolved) ||
        more && (_repostListLoading || _repostCursor == null)) {
      return;
    }
    final ticket = ++_repostListRevision;
    final cursor = more ? _repostCursor : null;
    _repostListOpened = true;
    _repostListLoading = true;
    _repostListError = null;
    _notify();
    _PostAuthority? a;
    try {
      a = await _authority();
      final page = await _accept(
        a,
        await _repostsApi.ownReposts(sessionToken: a.token, cursor: cursor),
      );
      if (ticket != _repostListRevision) return;
      final items = more ? [..._repostItems, ...page.items] : page.items;
      final unique = <String, RepostedPost>{
        for (final item in items) item.key: item,
      };
      _repostItems = unique.values.toList();
      _repostCursor = page.nextCursor;
    } catch (error) {
      if (_repostCurrent(authorityVersion) && ticket == _repostListRevision) {
        _repostListError = '转帖列表读取失败，请重试。';
        _propagateFeedAuthorityFailure(error, a);
      }
    } finally {
      if (_repostCurrent(authorityVersion) && ticket == _repostListRevision) {
        _repostListLoading = false;
        _notify();
      }
    }
  }

  /// Explicit identity and route authority: an old page cannot operate a new account.
  Future<void> setRepost(
    String id,
    String identityId,
    bool enabled, {
    required int authorityVersion,
  }) async {
    if (!_repostCurrent(authorityVersion)) return;
    final state = repostState(id);
    if (state.unresolved) return;
    state.pendingIdentity = identityId;
    state.desired = enabled;
    state.expectedVersion = null;
    state.uncertain = false;
    state.revision++;
    state.loading = false;
    _repostListRevision++;
    _repostListLoading = false;
    await _writeRepost(id, state, authorityVersion);
  }

  Future<void> retryRepost(String id, {required int authorityVersion}) async {
    if (!_repostCurrent(authorityVersion)) return;
    final state = repostState(id);
    if (state.sending) return;
    if (state.unresolved) {
      await _writeRepost(id, state, authorityVersion);
    } else {
      await loadRepostState(id, authorityVersion: authorityVersion);
    }
  }

  void _finishRepost(
    String id,
    PostRepostState state,
    PostRepostSnapshot actual,
  ) {
    final matched = actual.contains(state.pendingIdentity!) == state.desired;
    state.value = actual;
    state.error = matched ? null : '操作未生效，已同步当前状态。';
    state.pendingIdentity = null;
    state.desired = null;
    state.expectedVersion = null;
    state.uncertain = false;
    // Invalidate in-flight pages and remove confirmed cancellations immediately.
    _repostListRevision++;
    _repostListLoading = false;
    _repostItems.removeWhere(
      (item) => item.postId == id && !actual.contains(item.identityId),
    );
  }

  Future<void> _writeRepost(String id, PostRepostState state, int epoch) async {
    if (!_repostCurrent(epoch) || state.sending) return;
    state.sending = true;
    state.error = null;
    _notify();
    _PostAuthority? a;
    var attempted = false;
    try {
      a = await _authority();
      if (state.expectedVersion == null) {
        final response = await _repostsApi.postReposts(
          sessionToken: a.token,
          postId: id,
        );
        state.value = await _accept(a, response);
        if (response.interactionVersion == null) {
          throw const PostFailure(kind: PostFailureKind.invalidResponse);
        }
        state.expectedVersion = response.interactionVersion;
      }
      attempted = true;
      final response = await _repostsApi.setPostRepost(
        sessionToken: a.token,
        postId: id,
        identityId: state.pendingIdentity!,
        reposted: state.desired!,
        version: state.expectedVersion!,
      );
      final actual = await _accept(a, response);
      if (response.interactionVersion == null ||
          response.interactionVersion == state.expectedVersion) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      _finishRepost(id, state, actual);
    } catch (error) {
      if (!_repostCurrent(epoch)) return;
      _propagateFeedAuthorityFailure(error, a);
      if (!_repostCurrent(epoch)) return;
      final conflict =
          error is PostFailure && error.code == 'INTERACTION_VERSION_CONFLICT';
      final definite =
          error is PostFailure && error.kind == PostFailureKind.rejected;
      state.uncertain = state.uncertain || attempted && !definite;
      state.error = state.uncertain ? '转帖结果尚未确认，请重试核对。' : '转帖操作失败，请重试。';
      if ((conflict || state.uncertain) && a != null) {
        try {
          final response = await _repostsApi.postReposts(
            sessionToken: a.token,
            postId: id,
          );
          final actual = await _accept(a, response);
          if (response.interactionVersion != null &&
              response.interactionVersion != state.expectedVersion) {
            _finishRepost(id, state, actual);
          }
        } catch (readError) {
          if (_repostCurrent(epoch)) {
            _propagateFeedAuthorityFailure(readError, a);
          }
        }
      } else {
        state.pendingIdentity = null;
        state.desired = null;
        state.expectedVersion = null;
      }
    } finally {
      if (_repostCurrent(epoch)) {
        state.sending = false;
        _notify();
        if (!state.unresolved && _repostListOpened) {
          await loadReposts(authorityVersion: epoch);
        }
      }
    }
  }
}
