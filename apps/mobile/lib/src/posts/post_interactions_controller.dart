part of 'post_controller.dart';

enum PostInteractionAction { like, favorite }

/// One account-scoped entry is shared by feed and every open detail.
class PostInteractionState {
  PostInteractions? value;
  bool loading = false, sending = false, refreshPending = false;
  PostInteractionAction? pendingAction;
  bool? desired;
  bool? queuedLike, queuedFavorite;
  String? readError, writeError, expectedVersion;
  String? get error => writeError ?? readError;
  bool uncertain = false;
  PostInteractionAction? retryAction;
  bool? retryDesired;
  int revision = 0;
  bool get unresolved => pendingAction != null;
  bool get canChange => value != null && (!unresolved || sending && !uncertain);
  bool get liked =>
      queuedLike ??
      (pendingAction == PostInteractionAction.like
          ? desired!
          : value?.likedByMe ?? false);
  bool get favorited =>
      queuedFavorite ??
      (pendingAction == PostInteractionAction.favorite
          ? desired!
          : value?.favoritedByMe ?? false);
  int? get likes => value == null
      ? null
      : value!.likeCount + (liked != value!.likedByMe ? (liked ? 1 : -1) : 0);
}

extension PostInteractionsController on PostController {
  PostInteractionsApi get _interactionsApi => _api as PostInteractionsApi;
  PostInteractionState interaction(String id) =>
      _interactions.putIfAbsent(id, PostInteractionState.new);

  void _invalidateInteractionReads() {
    for (final entry in _interactions.values) {
      entry.refreshPending = entry.refreshPending || entry.loading;
      entry.revision++;
      entry.loading = false;
    }
  }

  /// Returns false only for an atomic batch invalidated by a removed post.
  Future<bool> loadInteractions(List<String> ids, {bool single = false}) async {
    if (!supportsInteractions || !available || ids.isEmpty) return true;
    final epoch = _epoch;
    final tickets = <String, int>{};
    for (final id in ids.toSet()) {
      if (_deletedPostIds.contains(id)) continue;
      final entry = interaction(id);
      if (entry.unresolved) {
        entry.refreshPending = true;
        continue;
      }
      tickets[id] = ++entry.revision;
      entry.loading = true;
      entry.readError = null;
    }
    if (tickets.isEmpty) return true;
    _notify();
    _PostAuthority? a;
    try {
      a = await _authority();
      if (epoch != _epoch) return true;
      final List<PostInteractions> values;
      if (single && tickets.length == 1) {
        values = [
          await _accept(
            a,
            await _interactionsApi.postInteractions(
              sessionToken: a.token,
              postId: tickets.keys.single,
            ),
          ),
        ];
      } else {
        values = await _accept(
          a,
          await _interactionsApi.interactions(
            sessionToken: a.token,
            postIds: tickets.keys.toList(),
          ),
        );
      }
      for (final value in values) {
        final entry = interaction(value.postId);
        if (tickets[value.postId] == entry.revision &&
            !entry.unresolved &&
            !_deletedPostIds.contains(value.postId)) {
          entry.value = value;
          entry.refreshPending = false;
          entry.readError = null;
        }
      }
    } catch (error) {
      if (epoch != _epoch) return true;
      if (error is PostFailure &&
          {
            PostFailureKind.unauthorized,
            PostFailureKind.unavailable,
          }.contains(error.kind)) {
        _failure(error, a);
      }
      if (epoch != _epoch) return true;
      for (final id in tickets.keys) {
        final entry = interaction(id);
        if (entry.revision == tickets[id] && !entry.unresolved) {
          entry.readError = '互动数据暂时无法读取，请重试。';
        }
      }
      return !(error is PostFailure && error.code == 'POST_NOT_FOUND');
    } finally {
      if (epoch == _epoch) {
        for (final id in tickets.keys) {
          final entry = interaction(id);
          if (entry.revision == tickets[id]) entry.loading = false;
        }
        _notify();
      }
    }
    return true;
  }

  Future<void> changeInteraction(
    String id,
    PostInteractionAction action,
  ) async {
    if (!supportsInteractions || !available || _deletedPostIds.contains(id)) {
      return;
    }
    final entry = interaction(id);
    if (!entry.canChange) return;
    if (entry.unresolved) {
      if (action == PostInteractionAction.like) {
        entry.queuedLike = !entry.liked;
      } else {
        entry.queuedFavorite = !entry.favorited;
      }
      _notify();
      return;
    }
    _beginInteraction(
      entry,
      action,
      action == PostInteractionAction.like
          ? !entry.value!.likedByMe
          : !entry.value!.favoritedByMe,
    );
    await _writeInteraction(id, entry, _epoch);
  }

  void _beginInteraction(
    PostInteractionState entry,
    PostInteractionAction action,
    bool desired,
  ) {
    // Lock before any authority/preflight await, including the other operation.
    entry.refreshPending = entry.refreshPending || entry.loading;
    entry.pendingAction = action;
    entry.desired = desired;
    entry.expectedVersion = null;
    entry.uncertain = false;
    entry.retryAction = null;
    entry.retryDesired = null;
    entry.revision++;
    entry.loading = false;
  }

  Future<void> retryInteraction(String id) async {
    if (!supportsInteractions || !available || _deletedPostIds.contains(id)) {
      return;
    }
    final entry = interaction(id);
    if (entry.sending) return;
    if (!entry.unresolved && entry.retryAction != null) {
      _beginInteraction(entry, entry.retryAction!, entry.retryDesired!);
    }
    if (entry.unresolved) {
      // An uncertain attempt always reuses the original CAS condition.
      await _writeInteraction(id, entry, _epoch);
    } else {
      await loadInteractions([id], single: true);
    }
  }

  void _finishInteraction(PostInteractionState entry, PostInteractions actual) {
    final matched = entry.pendingAction == PostInteractionAction.like
        ? actual.likedByMe == entry.desired
        : actual.favoritedByMe == entry.desired;
    entry.value = actual;
    entry.retryAction = matched ? null : entry.pendingAction;
    entry.retryDesired = matched ? null : entry.desired;
    entry.writeError = matched ? null : '操作未成功，已同步当前状态，请重试。';
    entry.pendingAction = null;
    entry.desired = null;
    entry.expectedVersion = null;
    entry.uncertain = false;
  }

  Future<void> _reconcileInteraction(
    _PostAuthority a,
    String id,
    PostInteractionState entry,
  ) async {
    final response = await _interactionsApi.postInteractions(
      sessionToken: a.token,
      postId: id,
    );
    final actual = await _accept(a, response);
    final version = response.interactionVersion;
    if (version == null) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    if (_deletedPostIds.contains(id)) return;
    entry.value = actual;
    // Only a rotated persistent write fence proves ALL attempts using our old
    // condition can no longer apply, even if the process lost their responses.
    if (version != entry.expectedVersion) _finishInteraction(entry, actual);
  }

  Future<void> _writeInteraction(
    String id,
    PostInteractionState entry,
    int epoch,
  ) async {
    if (entry.sending || epoch != _epoch) return;
    entry.sending = true;
    entry.writeError = null;
    _notify();
    _PostAuthority? a;
    var attempted = false;
    final alreadyUncertain = entry.uncertain;
    try {
      a = await _authority();
      if (epoch != _epoch) return;
      if (entry.expectedVersion == null) {
        final response = await _interactionsApi.postInteractions(
          sessionToken: a.token,
          postId: id,
        );
        final actual = await _accept(a, response);
        if (response.interactionVersion == null) {
          throw const PostFailure(kind: PostFailureKind.invalidResponse);
        }
        entry.value = actual;
        entry.expectedVersion = response.interactionVersion;
      }
      attempted = true;
      final response = entry.pendingAction == PostInteractionAction.like
          ? await _interactionsApi.setPostLike(
              sessionToken: a.token,
              postId: id,
              liked: entry.desired!,
              version: entry.expectedVersion!,
            )
          : await _interactionsApi.setPostFavorite(
              sessionToken: a.token,
              postId: id,
              favorited: entry.desired!,
              version: entry.expectedVersion!,
            );
      final value = await _accept(a, response);
      if (_deletedPostIds.contains(id)) return;
      if (response.interactionVersion == null ||
          response.interactionVersion == entry.expectedVersion) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      _finishInteraction(entry, value);
    } catch (error) {
      if (epoch != _epoch) return;
      if (error is PostFailure &&
          {
            PostFailureKind.unauthorized,
            PostFailureKind.unavailable,
          }.contains(error.kind)) {
        _failure(error, a);
      }
      if (epoch != _epoch || a == null || !_current(a)) return;
      final conflict =
          error is PostFailure && error.code == 'INTERACTION_VERSION_CONFLICT';
      if (!attempted ||
          !alreadyUncertain &&
              error is PostFailure &&
              error.kind == PostFailureKind.rejected &&
              !conflict) {
        // No PUT started, or this first PUT was explicitly rejected. A later
        // rejection must never discard an earlier transport-unknown attempt.
        entry.retryAction = entry.pendingAction;
        entry.retryDesired = entry.pendingAction == PostInteractionAction.like
            ? entry.queuedLike ?? entry.desired
            : entry.queuedFavorite ?? entry.desired;
        entry.queuedLike = null;
        entry.queuedFavorite = null;
        entry.pendingAction = null;
        entry.desired = null;
        entry.expectedVersion = null;
        entry.writeError = '操作未成功，已恢复原状态，请重试。';
      } else {
        entry.uncertain = true;
        entry.writeError = '结果尚未确认，请重试核对。';
        try {
          await _reconcileInteraction(a, id, entry);
        } catch (readError) {
          if (readError is PostFailure &&
              {
                PostFailureKind.unauthorized,
                PostFailureKind.unavailable,
              }.contains(readError.kind)) {
            _failure(readError, a);
          }
        }
      }
    } finally {
      if (epoch == _epoch) {
        entry.sending = false;
        entry.revision++;
        _notify();
        // One CAS write at a time per post; collapse rapid taps to the latest
        // explicit state, and never drain while an earlier outcome is unknown.
        if (!entry.unresolved && available && !_deletedPostIds.contains(id)) {
          for (final action in PostInteractionAction.values) {
            final desired = action == PostInteractionAction.like
                ? entry.queuedLike
                : entry.queuedFavorite;
            if (action == PostInteractionAction.like) {
              entry.queuedLike = null;
            } else {
              entry.queuedFavorite = null;
            }
            if (desired == null) continue;
            final actual = action == PostInteractionAction.like
                ? entry.value!.likedByMe
                : entry.value!.favoritedByMe;
            if (desired == actual) continue;
            _beginInteraction(entry, action, desired);
            await _writeInteraction(id, entry, epoch);
            break;
          }
        }
        if (epoch == _epoch &&
            entry.refreshPending &&
            !entry.unresolved &&
            !_deletedPostIds.contains(id)) {
          entry.refreshPending = false;
          await loadInteractions([id], single: true);
        }
      }
    }
  }
}
