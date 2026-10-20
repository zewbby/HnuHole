part of 'post_controller.dart';

enum PostInteractionAction { like, favorite }

/// One account-scoped entry is shared by feed and every open detail.
class PostInteractionState {
  PostInteractions? value;
  bool loading = false, sending = false, refreshPending = false;
  PostInteractionAction? pendingAction;
  bool? desired;
  String? error;
  int revision = 0;
  bool get unresolved => pendingAction != null;
  bool get canChange => value != null && !unresolved;
  bool get liked => pendingAction == PostInteractionAction.like
      ? desired!
      : value?.likedByMe ?? false;
  bool get favorited => pendingAction == PostInteractionAction.favorite
      ? desired!
      : value?.favoritedByMe ?? false;
  int? get likes => value == null
      ? null
      : value!.likeCount +
            (pendingAction == PostInteractionAction.like &&
                    desired != value!.likedByMe
                ? (desired! ? 1 : -1)
                : 0);
}

extension PostInteractionsController on PostController {
  PostInteractionsApi get _interactionsApi => _api as PostInteractionsApi;
  PostInteractionState interaction(String id) =>
      _interactions.putIfAbsent(id, PostInteractionState.new);

  void _invalidateInteractionReads() {
    for (final entry in _interactions.values) {
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
      entry.error = null;
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
          entry.error = null;
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
          entry.error = '互动数据暂时无法读取，请重试。';
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
    entry.pendingAction = action;
    entry.desired = action == PostInteractionAction.like
        ? !entry.value!.likedByMe
        : !entry.value!.favoritedByMe;
    // Synchronous lock, before authority/storage awaits: rapid taps cannot queue toggles.
    entry.revision++;
    entry.loading = false;
    await _writeInteraction(id, entry, _epoch);
  }

  Future<void> retryInteraction(String id) async {
    if (!supportsInteractions || !available || _deletedPostIds.contains(id)) {
      return;
    }
    final entry = interaction(id);
    if (entry.sending) return;
    if (entry.unresolved) {
      // Reassert exactly the same desired value. An older timed-out PUT can
      // still commit after a GET, so a mismatching GET never unlocks reversal.
      await _writeInteraction(id, entry, _epoch);
    } else {
      await loadInteractions([id], single: true);
    }
  }

  Future<void> _writeInteraction(
    String id,
    PostInteractionState entry,
    int epoch,
  ) async {
    if (entry.sending || epoch != _epoch) return;
    entry.sending = true;
    entry.error = null;
    _notify();
    _PostAuthority? a;
    try {
      a = await _authority();
      if (epoch != _epoch) return;
      final response = entry.pendingAction == PostInteractionAction.like
          ? await _interactionsApi.setPostLike(
              sessionToken: a.token,
              postId: id,
              liked: entry.desired!,
            )
          : await _interactionsApi.setPostFavorite(
              sessionToken: a.token,
              postId: id,
              favorited: entry.desired!,
            );
      final value = await _accept(a, response);
      if (_deletedPostIds.contains(id)) return;
      entry.value = value;
      entry.pendingAction = null;
      entry.desired = null;
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
      if (error is PostFailure && error.kind == PostFailureKind.rejected) {
        // A definite server rejection did not apply this PUT.
        entry.pendingAction = null;
        entry.desired = null;
        entry.error = '操作未成功，已恢复原状态，请重试。';
      } else {
        entry.error = '结果尚未确认，请重试核对。';
        try {
          final actual = await _accept(
            a,
            await _interactionsApi.postInteractions(
              sessionToken: a.token,
              postId: id,
            ),
          );
          final matches = entry.pendingAction == PostInteractionAction.like
              ? actual.likedByMe == entry.desired
              : actual.favoritedByMe == entry.desired;
          if (matches && !_deletedPostIds.contains(id)) {
            entry.value = actual;
            entry.pendingAction = null;
            entry.desired = null;
            entry.error = null;
          }
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
        if (entry.refreshPending &&
            !entry.unresolved &&
            !_deletedPostIds.contains(id)) {
          entry.refreshPending = false;
          await loadInteractions([id], single: true);
        }
      }
    }
  }
}
