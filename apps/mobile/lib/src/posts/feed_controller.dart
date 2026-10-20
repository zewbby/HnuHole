part of 'post_controller.dart';

extension FeedController on PostController {
  FeedApi get _feedApi => _api as FeedApi;
  List<FeedPost> get timelineItems => List.unmodifiable(
    _timeline.where((p) => !_deletedPostIds.contains(p.postId)),
  );
  Set<String> get blockedChannelIds => Set.unmodifiable(_blockedChannels);
  int? postViewCount(String id) => _postViews[id];

  void _clearTimeline() {
    _interactions.clear();
    ++_timelineRequest;
    _timeline = [];
    _blockedChannels = {};
    _postViews.clear();
    _preferencesReady = false;
    timelineChannelId = timelineCursor = timelineError = preferencesError =
        null;
    timelineLoading = preferencesSaving = false;
    // A new account never waits behind the old account's pending network request.
    _preferenceWrites = Future.value();
  }

  Future<void> loadTimeline({
    String? channelId,
    bool more = false,
    bool recoverMissingInteractions = true,
  }) async {
    if (!supportsFeed || !available || preferencesSaving) return;
    if (more &&
        (timelineLoading ||
            timelineCursor == null ||
            channelId != timelineChannelId)) {
      return;
    }
    final request = ++_timelineRequest;
    final epoch = _epoch;
    final cursor = more ? timelineCursor : null;
    if (!more) {
      _invalidateInteractionReads();
      timelineChannelId = channelId;
      timelineCursor = null;
      _timeline = [];
    }
    timelineLoading = true;
    timelineError = null;
    _notify();
    _PostAuthority? a;
    try {
      a = await _authority();
      if (epoch != _epoch || request != _timelineRequest) return;
      if (!_preferencesReady || !more) {
        final reconciling = !_preferencesReady;
        final preferences = await _accept(
          a,
          await _feedApi.feedPreferences(sessionToken: a.token),
        );
        if (request != _timelineRequest) return;
        _blockedChannels = preferences.blockedChannelIds;
        _preferencesReady = true;
        if (reconciling) preferencesError = null;
      }
      final page = await _accept(
        a,
        await _feedApi.timeline(
          sessionToken: a.token,
          channelId: channelId,
          cursor: cursor,
        ),
      );
      if (request != _timelineRequest) return;
      if (page.items.any(
        (p) =>
            _blockedChannels.contains(p.channelId) ||
            channelId != null && p.channelId != channelId,
      )) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      final ids = (more ? _timeline : <FeedPost>[])
          .map((p) => p.postId)
          .toSet();
      _timeline = [
        if (more) ..._timeline,
        ...page.items.where(
          (p) => !_deletedPostIds.contains(p.postId) && ids.add(p.postId),
        ),
      ];
      for (final post in page.items) {
        final old = _postViews[post.postId] ?? 0;
        _postViews[post.postId] = post.viewCount > old ? post.viewCount : old;
      }
      timelineCursor = page.nextCursor;
      _notify();
      final found = await loadInteractions(
        page.items.map((p) => p.postId).toList(),
      );
      if (!found &&
          recoverMissingInteractions &&
          _current(a) &&
          request == _timelineRequest) {
        await loadTimeline(
          channelId: channelId,
          recoverMissingInteractions: false,
        );
      }
    } catch (error) {
      if (epoch != _epoch || request != _timelineRequest) return;
      _failure(error, a);
      if (a != null && _current(a)) {
        if (error is PostFailure && error.code == 'CURSOR_INVALID') {
          // Never append another scope to the current page or treat this as EOF.
          timelineCursor = null;
          _preferencesReady = false;
          timelineLoading = false;
          await loadTimeline(channelId: channelId);
          return;
        }
        timelineError = '暂时无法加载帖子，请重试。';
        if (!_preferencesReady) preferencesError = '暂时无法核对屏蔽设置，请重试。';
      }
    } finally {
      if (epoch == _epoch && request == _timelineRequest) {
        timelineLoading = false;
        _notify();
      }
    }
  }

  /// Serialize complete replacements; capture account at enqueue, not execution.
  Future<void> saveBlockedChannels(Set<String> ids) {
    final epoch = _epoch;
    final target = Set<String>.of(ids);
    final next = _preferenceWrites.then(
      (_) => _saveBlockedChannels(target, epoch),
    );
    _preferenceWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _saveBlockedChannels(Set<String> target, int epoch) async {
    if (!supportsFeed || !available || epoch != _epoch) return;
    final a = await _authority();
    if (epoch != _epoch || !_current(a)) return;
    preferencesSaving = true;
    preferencesError = null;
    ++_timelineRequest;
    timelineLoading = false;
    timelineCursor = null;
    _timeline = [];
    _notify();
    try {
      final result = await _accept(
        a,
        await _feedApi.saveFeedPreferences(
          sessionToken: a.token,
          blockedChannelIds: target,
        ),
      );
      _blockedChannels = result.blockedChannelIds;
      _preferencesReady = true;
    } catch (error) {
      if (!_current(a)) return;
      _failure(error, a);
      _preferencesReady = false;
      if (!_current(a)) return;
      // Even a timeout may have committed. Read before accepting another toggle.
      try {
        final actual = await _accept(
          a,
          await _feedApi.feedPreferences(sessionToken: a.token),
        );
        _blockedChannels = actual.blockedChannelIds;
        _preferencesReady = true;
        preferencesError = setEquals(target, _blockedChannels)
            ? null
            : '屏蔽设置未保存，已恢复服务器设置。';
      } catch (readError) {
        _failure(readError, a);
        if (_current(a)) preferencesError = '暂时无法核对屏蔽设置，请重试。';
      }
    } finally {
      if (_current(a)) {
        preferencesSaving = false;
        _notify();
      }
    }
    if (_current(a) && _preferencesReady) {
      await loadTimeline(channelId: timelineChannelId);
    } else if (_current(a)) {
      timelineError = '请先重新加载并核对屏蔽设置。';
      _notify();
    }
  }

  /// Called by the detail only after a frame containing the visible body.
  Future<void> registerVisiblePost(String postId) async {
    if (!supportsFeed || !available || _deletedPostIds.contains(postId)) return;
    final a = await _authority();
    try {
      final result = await _accept(
        a,
        await _feedApi.registerPostView(sessionToken: a.token, postId: postId),
      );
      if (_deletedPostIds.contains(postId)) return;
      final old = _postViews[postId] ?? 0;
      _postViews[postId] = result.viewCount > old ? result.viewCount : old;
      _notify();
    } catch (error) {
      // Reading remains available when counting fails. No local increment.
      if (error is PostFailure &&
          (error.kind == PostFailureKind.unauthorized ||
              error.kind == PostFailureKind.unavailable)) {
        _failure(error, a);
      }
    }
  }
}
