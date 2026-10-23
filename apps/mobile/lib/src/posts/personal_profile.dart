part of 'post_screens.dart';

mixin _PersonalProfile on State<PersonalPostsScreen> {
  _PostAuthority get _authority;
  ScrollController get _scroll;
  Future<void> _open(PersonalPostItem item);
  Future<void> _deleteDraft(PersonalPostItem item);
  Future<void> _deleteFailedTask(PersonalPostItem item);
  void _chooseChannel();
  int _tab = 0;
  bool _repostsOpened = false;
  Map<String, String> _repostIdentityNames = {};
  String? _repostIdentityError;

  Future<void> _loadRepostNames() async {
    try {
      final identities = await widget.controller.repostIdentities(
        authorityVersion: _authority.version,
      );
      if (!mounted || !_authority.current) return;
      setState(() {
        _repostIdentityNames = {
          for (final identity in identities) identity.id: identity.nickname,
        };
        _repostIdentityError = null;
      });
    } catch (_) {
      if (mounted && _authority.current) {
        setState(() => _repostIdentityError = '转帖身份读取失败，请重试');
      }
    }
  }

  Future<void> _refreshReposts() async {
    if (!_authority.current || !widget.controller.supportsReposts) return;
    _repostsOpened = true;
    await Future.wait([
      _loadRepostNames(),
      widget.controller.loadReposts(authorityVersion: _authority.version),
    ]);
  }

  PostDetail? _repostOriginal(String postId, String identityId) => widget
      .controller
      .repostItems
      .where((item) => item.postId == postId && item.identityId == identityId)
      .firstOrNull
      ?.post;

  Future<void> _confirmUndoRepost(String postId, String identityId) async {
    final c = widget.controller;
    if (!_authority.current || c.repostState(postId).unresolved) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: c,
        builder: (_, __) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('撤销转帖？', style: TextStyle(color: Colors.black)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              key: ValueKey('confirm-undo-repost:$identityId/$postId'),
              onPressed: !_authority.current || c.repostState(postId).unresolved
                  ? null
                  : () {
                      if (!_authority.current ||
                          c.repostState(postId).unresolved) {
                        return;
                      }
                      Navigator.of(dialogContext).pop(true);
                    },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || !_authority.current) return;
    await c.setRepost(
      postId,
      identityId,
      false,
      authorityVersion: _authority.version,
    );
  }

  Future<void> _showRepostMenu(String postId, String identityId) async {
    if (!_authority.current) return;
    final c = widget.controller;
    final governance = GovernanceScope.maybeOf(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (_, __) {
            final available =
                _authority.current &&
                _repostOriginal(postId, identityId) != null;
            void choose(String value) {
              if (!_authority.current) return;
              if (value == 'undo' && c.repostState(postId).unresolved) return;
              if (value != 'undo' && !available) return;
              Navigator.of(sheetContext).pop(value);
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: ValueKey('view-repost:$identityId/$postId'),
                  leading: const Icon(
                    Icons.article_outlined,
                    color: Color(0xFF536971),
                  ),
                  title: const Text(
                    '查看帖子',
                    style: TextStyle(color: Colors.black),
                  ),
                  enabled: available,
                  onTap: () => choose('view'),
                ),
                ListTile(
                  key: ValueKey('report-repost:$identityId/$postId'),
                  leading: const Icon(
                    Icons.flag_outlined,
                    color: Color(0xFF536971),
                  ),
                  title: const Text(
                    '举报帖子',
                    style: TextStyle(color: Colors.black),
                  ),
                  enabled: available && governance?.available == true,
                  onTap: () => choose('report'),
                ),
                ListTile(
                  key: ValueKey('cancel-repost:$identityId/$postId'),
                  leading: const Icon(Icons.repeat, color: Color(0xFF536971)),
                  title: const Text(
                    '取消转载',
                    style: TextStyle(color: Colors.black),
                  ),
                  enabled:
                      _authority.current && !c.repostState(postId).unresolved,
                  onTap: () => choose('undo'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (action == null || !mounted || !_authority.current) return;
    if (action == 'undo') {
      await _confirmUndoRepost(postId, identityId);
      return;
    }
    final post = _repostOriginal(postId, identityId);
    if (post == null) return;
    if (action == 'view') {
      await _open(
        PersonalPostItem(
          id: '$identityId/$postId',
          title: post.title,
          sortAt: post.publishedAt,
          post: post,
        ),
      );
    } else if (action == 'report' && governance?.available == true) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportScreen(
            controller: governance!,
            postId: postId,
            title: post.title,
          ),
        ),
      );
    }
  }

  List<Widget> _repostSlivers() {
    final c = widget.controller;
    if (!c.supportsReposts) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('转帖服务暂不可用')),
        ),
      ];
    }
    final items = c.repostItems;
    return [
      if (c.repostListLoading)
        const SliverToBoxAdapter(child: LinearProgressIndicator()),
      if (_repostIdentityError case final error?)
        SliverToBoxAdapter(
          child: TextButton(onPressed: _loadRepostNames, child: Text(error)),
        ),
      for (final id in c.unresolvedRepostIds)
        SliverToBoxAdapter(
          child: ListTile(
            title: Text(c.repostState(id).sending ? '正在保存转帖…' : '转帖结果尚未确认'),
            trailing: TextButton(
              onPressed: c.repostState(id).sending
                  ? null
                  : () =>
                        c.retryRepost(id, authorityVersion: _authority.version),
              child: const Text('重试核对'),
            ),
          ),
        ),
      if (c.repostListError case final error?)
        SliverToBoxAdapter(
          child: TextButton(onPressed: _refreshReposts, child: Text(error)),
        ),
      if (!c.repostListLoading &&
          c.repostListError == null &&
          c.unresolvedRepostIds.isEmpty &&
          items.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('暂无转帖')),
        ),
      SliverList.builder(
        itemCount: items.length,
        findChildIndexCallback: (key) {
          final index = items.indexWhere(
            (item) => key == ValueKey('personal-repost:${item.key}'),
          );
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) {
          final item = items[index];
          final state = c.repostState(item.postId);
          final name = _repostIdentityNames[item.identityId];
          final post = item.post;
          return Column(
            key: ValueKey('personal-repost:${item.key}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Text(
                  name == null ? '正在核对转帖身份' : '以“$name”转帖',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (post == null)
                ListTile(
                  title: const Text('原帖已不可用'),
                  subtitle: const Text('无法查看原帖内容'),
                  trailing: IconButton(
                    tooltip: '帖子更多操作',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () =>
                        _showRepostMenu(item.postId, item.identityId),
                  ),
                )
              else
                _ProfilePost(
                  key: ValueKey('repost-original:${item.key}'),
                  onMenu: () => _showRepostMenu(item.postId, item.identityId),
                  repostAction: IconButton(
                    key: ValueKey('repost-undo:${item.key}'),
                    tooltip: '撤销转帖',
                    color: const Color(0xFF229ED9),
                    onPressed: state.unresolved
                        ? null
                        : () =>
                              _confirmUndoRepost(item.postId, item.identityId),
                    icon: const Icon(Icons.repeat, size: 20),
                  ),
                  post: post,
                  initialDetail: post,
                  own: false,
                  controller: c,
                  loadImages: widget.loadImages,
                  onOpen: () {
                    if (!_authority.current) return;
                    _open(
                      PersonalPostItem(
                        id: item.key,
                        title: post.title,
                        sortAt: item.repostedAt,
                        post: post,
                      ),
                    );
                  },
                ),
              if (state.error != null && !state.unresolved)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(state.error!),
                ),
              const Divider(height: 1),
            ],
          );
        },
      ),
      if (c.repostCursor != null)
        SliverToBoxAdapter(
          child: TextButton(
            key: const ValueKey('reposts-load-more'),
            onPressed: c.repostListLoading || c.unresolvedRepostIds.isNotEmpty
                ? null
                : () => c.loadReposts(
                    authorityVersion: _authority.version,
                    more: true,
                  ),
            child: const Text('加载更多'),
          ),
        ),
    ];
  }

  String? _profileIdentityId;
  int _identityEpoch = 0;

  void profileIdentityChanged() {
    final id = widget.controller.personalIdentity?.id;
    if (id == _profileIdentityId) return;
    _profileIdentityId = id;
    ++_identityEpoch;
    _hot = _sorting = false;
    _replies.clear();
    _replyLoaded = _replyLoading = false;
    _replyError = null;
    _offsets.remove(0);
    _offsets.remove(1);
    _scheduleExpiry();
    if (_tab == 1 && id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _authority.current) unawaited(_loadReplies());
      });
    }
  }

  Future<void> _chooseIdentity() async {
    final controller = widget.controller;
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => !_authority.current
            ? const SizedBox.shrink()
            : SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '切换身份',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final identity in controller.personalIdentities)
                      ListTile(
                        key: ValueKey('profile-identity-${identity.id}'),
                        leading: DetailAvatar(
                          name: identity.nickname,
                          avatar: identity.avatar,
                          radius: 20,
                        ),
                        title: Text(identity.nickname),
                        trailing: identity.id == controller.personalIdentity?.id
                            ? const Icon(Icons.check, color: Colors.black)
                            : null,
                        onTap: () => Navigator.pop(context, identity.id),
                      ),
                  ],
                ),
              ),
      ),
    );
    if (id == null || !mounted || !_authority.current) return;
    await controller.selectPersonalIdentity(id);
  }

  bool _hot = false, _sorting = false, _searching = false;
  String _query = '';
  Map<String, dynamic> _profile = {};
  Timer? _expiry;
  bool _started = false, _profileReady = false;
  final _offsets = <int, double>{};
  String? _profileError;
  final _replies = <CommentRow>[];
  bool _replyLoading = false, _replyLoaded = false;
  String? _replyError;
  final _collections = <int, List<PostCard>>{};
  final _collectionCursors = <int, String?>{};
  final _collectionErrors = <int, String>{};
  final _collectionLoading = <int>{};

  Future<void> _loadCollection(int tab, {bool more = false}) async {
    if (_collectionLoading.contains(tab) || !_authority.current) return;
    setState(() {
      _collectionLoading.add(tab);
      _collectionErrors.remove(tab);
    });
    try {
      final page = await widget.controller.loadPersonalCollection(
        favorites: tab == 4,
        cursor: more ? _collectionCursors[tab] : null,
      );
      if (!mounted || !_authority.current) return;
      await widget.controller.loadInteractions(
        page.items.map((e) => e.postId).toList(),
      );
      if (!mounted || !_authority.current) return;
      setState(() {
        final items = more
            ? List<PostCard>.of(_collections[tab] ?? [])
            : <PostCard>[];
        final seen = items.map((p) => p.postId).toSet();
        items.addAll(page.items.where((p) => seen.add(p.postId)));
        _collections[tab] = items;
        _collectionCursors[tab] = page.nextCursor;
      });
    } catch (_) {
      if (mounted && _authority.current) {
        setState(() => _collectionErrors[tab] = '暂时无法读取，请重试');
      }
    } finally {
      if (mounted) setState(() => _collectionLoading.remove(tab));
    }
  }

  List<PostCard> _collectionItems(int tab) => (_collections[tab] ?? []).where((
    p,
  ) {
    if (widget.controller.isPostDeleted(p.postId)) return false;
    if (!widget.controller.supportsInteractions) return true;
    final value = widget.controller.interaction(p.postId).value;
    return value == null || (tab == 4 ? value.favoritedByMe : value.likedByMe);
  }).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_readProfile());
    }
  }

  void disposeProfile() => _expiry?.cancel();
  Map<String, dynamic> get _identityMood {
    final id = widget.controller.personalIdentity?.id;
    final moods = _profile['identityMoods'];
    if (moods is Map && moods[id] is Map) {
      return Map<String, dynamic>.from(moods[id]);
    }
    return widget.controller.personalIdentity?.isOriginal == true
        ? _profile
        : {};
  }

  String get _mood {
    final expiry = DateTime.tryParse(
      _identityMood['moodExpiresAt'] as String? ?? '',
    );
    return expiry != null && expiry.isAfter(DateTime.now())
        ? _identityMood['mood'] as String? ?? ''
        : '';
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final expiry = DateTime.tryParse(
      _identityMood['moodExpiresAt'] as String? ?? '',
    );
    if (expiry != null && expiry.isAfter(DateTime.now())) {
      _expiry = Timer(expiry.difference(DateTime.now()), () {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _readProfile() async {
    try {
      final value = await widget.controller.readPersonalProfileState();
      if (!mounted || !_authority.current) return;
      setState(() {
        _profile = value;
        _profileReady = true;
        _profileError = null;
      });
      _scheduleExpiry();
    } catch (_) {
      if (mounted && _authority.current) {
        setState(() => _profileError = '心情读取失败，点击重试');
      }
    }
  }

  Future<void> _editMood() async {
    if (!_profileReady && _profileError == null) return;
    if (_profileError != null) {
      await _readProfile();
      return;
    }
    final moodIdentity = widget.controller.personalIdentity?.id;
    final moodEpoch = _identityEpoch;
    if (moodIdentity == null) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '取消编辑心情',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (_, animation, secondary, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .25, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
      pageBuilder: (_, animation, secondary) => _MoodEditor(
        initial: _mood,
        authority: widget.controller,
        isCurrent: () => _authority.current && moodEpoch == _identityEpoch,
        onSave: (text) async {
          if (!_authority.current || moodEpoch != _identityEpoch) {
            throw StateError('身份已变化');
          }
          final value = {
            ..._profile,
            'identityMoods': {
              ...?_profile['identityMoods'] as Map?,
              moodIdentity: {
                'mood': text,
                'moodExpiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 24))
                    .toIso8601String(),
              },
            },
          };
          await widget.controller.savePersonalProfileState(value);
          if (!mounted || !_authority.current || moodEpoch != _identityEpoch) {
            throw StateError('身份已变化');
          }
          setState(() => _profile = value);
          _scheduleExpiry();
        },
      ),
    );
  }

  Future<void> _sort(bool hot) async {
    if (hot && !widget.controller.supportsInteractions) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('热度数据暂不可用')));
      return;
    }
    if (_sorting || widget.controller.personalLoading) return;
    final identityEpoch = _identityEpoch;
    setState(() {
      _hot = hot;
      _sorting = hot;
    });
    if (!hot) return;
    try {
      while (mounted &&
          _authority.current &&
          identityEpoch == _identityEpoch &&
          widget.controller.personalHasMore) {
        await widget.controller.loadPersonal(more: true);
        if (widget.controller.personalError != null) throw StateError('读取失败');
      }
      if (!mounted || identityEpoch != _identityEpoch) return;
      final ids = widget.controller.personalItems
          .where((e) => e.post != null)
          .map((e) => e.post!.postId)
          .toList();
      for (var i = 0; i < ids.length; i += 20) {
        await widget.controller.loadInteractions(
          ids.sublist(i, (i + 20).clamp(0, ids.length)),
        );
      }
      if (ids.any((id) => widget.controller.interaction(id).error != null)) {
        throw StateError('热度读取失败');
      }
    } catch (_) {
      if (mounted && _authority.current && identityEpoch == _identityEpoch) {
        setState(() => _hot = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法获取完整热度，请重试')));
      }
    } finally {
      if (mounted && identityEpoch == _identityEpoch) {
        setState(() => _sorting = false);
      }
    }
  }

  Future<void> _loadReplies() async {
    final identityId = widget.controller.personalIdentity?.id;
    if (_replyLoading || identityId == null) return;
    final identityEpoch = _identityEpoch;
    final runtime = CommentScope.maybeOf(context);
    if (runtime == null) {
      setState(() => _replyError = '回复服务暂不可用');
      return;
    }
    setState(() {
      _replyLoading = true;
      _replyError = null;
    });
    final epoch = runtime.authorityVersion;
    try {
      final rows = <CommentRow>[];
      {
        String? cursor;
        do {
          if (!mounted ||
              !_authority.current ||
              !runtime.current(epoch) ||
              identityEpoch != _identityEpoch) {
            return;
          }
          final page = await runtime.request(
            'GET',
            '/api/v1/me/comments',
            query: {
              'identityId': identityId,
              if (cursor != null) 'cursor': cursor,
            },
          );
          rows.addAll((page['items'] as List).map(CommentRow.new));
          cursor = page['nextCursor'] as String?;
        } while (cursor != null);
      }
      if (!mounted ||
          !_authority.current ||
          !runtime.current(epoch) ||
          identityEpoch != _identityEpoch) {
        return;
      }
      rows.sort(
        (a, b) => (b.data['publishedAt'] as String).compareTo(
          a.data['publishedAt'] as String,
        ),
      );
      setState(() {
        _replies
          ..clear()
          ..addAll(rows);
        _replyLoaded = true;
      });
    } catch (_) {
      if (mounted && _authority.current && identityEpoch == _identityEpoch) {
        setState(() => _replyError = '回复加载失败，点击重试');
      }
    } finally {
      if (mounted && identityEpoch == _identityEpoch) {
        setState(() => _replyLoading = false);
      }
    }
  }

  Widget _profileContent() {
    final c = widget.controller;
    final name =
        c.personalIdentity?.nickname ??
        (c.personalProfileError != null
            ? '个人资料暂不可用'
            : c.personalProfileLoading
            ? '正在加载个人资料…'
            : '我的身份');
    final items = c.personalItems
        .where(
          (e) =>
              c.personalIdentity != null &&
              (_query.isEmpty || e.title.contains(_query)),
        )
        .toList();
    if (_hot) {
      items.sort((a, b) {
        if (a.post == null || b.post == null) {
          return a.post == null
              ? (b.post == null ? b.sortAt.compareTo(a.sortAt) : -1)
              : 1;
        }
        int score(PersonalPostItem item) {
          final v = c.interaction(item.post!.postId).value;
          return (v?.likeCount ?? 0) +
              (v?.commentCount ?? 0) +
              (v?.favoriteCount ?? 0);
        }

        final result = score(b).compareTo(score(a));
        return result == 0 ? b.sortAt.compareTo(a.sortAt) : result;
      });
    }
    return RefreshIndicator(
      onRefresh: () async {
        await _readProfile();
        if (_tab == 2) {
          await _refreshReposts();
        } else if (_tab == 1) {
          await _loadReplies();
        } else if (_tab >= 3) {
          await _loadCollection(_tab);
        } else {
          await c.loadPersonal();
          if (_hot) await _sort(true);
        }
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: '搜索我的帖子',
                        icon: const Icon(
                          Icons.search,
                          size: 28,
                          color: Colors.black,
                        ),
                        onPressed: c.personalLoading
                            ? null
                            : () async {
                                final searchIdentity = c.personalIdentity?.id;
                                setState(() {
                                  _searching = !_searching;
                                  _tab = 0;
                                  if (!_searching) _query = '';
                                });
                                while (mounted &&
                                    _authority.current &&
                                    _searching &&
                                    c.personalIdentity?.id == searchIdentity &&
                                    c.personalHasMore) {
                                  await c.loadPersonal(more: true);
                                  if (c.personalError != null) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text('部分帖子加载失败，请下拉重试'),
                                            ),
                                          );
                                    }
                                    break;
                                  }
                                }
                              },
                      ),
                      IconButton(
                        tooltip: '设置',
                        icon: const Icon(
                          Icons.settings_outlined,
                          size: 28,
                          color: Colors.black,
                        ),
                        onPressed: widget.onOpenSettings,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 96,
                    child: Row(
                      key: const ValueKey('personal-profile'),
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 104,
                          height: 96,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: 4,
                                left: -8,
                                child: IconButton(
                                  tooltip: '切换身份',
                                  onPressed: c.personalIdentities.isEmpty
                                      ? null
                                      : _chooseIdentity,
                                  icon: const Icon(
                                    Icons.swap_horiz,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: DetailAvatar(
                                  name: name,
                                  avatar:
                                      c.personalIdentity?.avatar ??
                                      'default-v1',
                                  radius: 30,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Material(
                                  color: Colors.white,
                                  elevation: 2,
                                  shadowColor: Colors.black12,
                                  shape: const _MoodBubbleBorder(),
                                  child: InkWell(
                                    key: const ValueKey('personal-mood'),
                                    customBorder: const _MoodBubbleBorder(),
                                    onTap: _editMood,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        18,
                                        10,
                                        10,
                                      ),
                                      child: _profileError != null
                                          ? const Icon(Icons.refresh)
                                          : _mood.isEmpty
                                          ? const Icon(
                                              Icons.add,
                                              color: Colors.black,
                                            )
                                          : Text(
                                              _mood,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 14,
                                                height: 1.3,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '搜索我的帖子',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ProfileTabs(
              selected: _tab,
              hot: _hot,
              onSort: _sort,
              onSelect: (index) {
                final previous = _scroll.hasClients ? _scroll.offset : 0.0;
                _offsets[_tab] = previous;
                setState(() => _tab = index);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scroll.hasClients) {
                    _scroll.jumpTo(
                      (_offsets[index] ?? previous.clamp(0.0, 212.0)).clamp(
                        0.0,
                        _scroll.position.maxScrollExtent,
                      ),
                    );
                  }
                });
                if (index == 2 && !_repostsOpened) unawaited(_refreshReposts());
                if (index == 1 && !_replyLoaded) unawaited(_loadReplies());
                if (index >= 3 && !_collections.containsKey(index)) {
                  unawaited(_loadCollection(index));
                }
              },
            ),
          ),
          if (_sorting)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_tab == 0) ...[
            if (c.personalLoading && items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(semanticsLabel: '正在加载自己的帖子'),
                ),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _PageState(
                  title: c.personalError != null
                      ? '暂时无法加载自己的帖子'
                      : _query.isNotEmpty
                      ? '没有匹配的帖子'
                      : '还没有自己的帖子',
                  message: c.personalError,
                  action: c.personalError != null ? '重新加载' : '选择通道发帖',
                  actionIcon: c.personalError == null ? Icons.add : null,
                  onAction: c.personalError != null
                      ? c.loadPersonal
                      : _chooseChannel,
                ),
              ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return item.post != null
                    ? _ProfilePost(
                        key: ValueKey(item.id),
                        post: item.post!,
                        controller: c,
                        loadImages: widget.loadImages,
                        onOpen: () => _open(item),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: _PersonalCard(
                          key: ValueKey(item.id),
                          item: item,
                          channelName:
                              widget.channelNames[item.channelId] ?? '原通道',
                          onOpen: () => _open(item),
                          onDeleteDraft: item.isDraft
                              ? () => _deleteDraft(item)
                              : null,
                          onDeleteTask:
                              item.task?.canHide == true &&
                                  !{
                                    'SUBMITTED',
                                    'UNKNOWN',
                                    'RESULT_EXPIRED',
                                  }.contains(item.state)
                              ? () => _deleteFailedTask(item)
                              : null,
                        ),
                      );
              },
            ),
            if (items.isNotEmpty)
              SliverToBoxAdapter(
                child: _LoadMore(
                  loading: c.personalLoading,
                  hasMore: c.personalHasMore,
                  onPressed: () => c.loadPersonal(more: true),
                ),
              ),
          ] else if (_tab == 1) ...[
            if (_replyLoading)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (_replyError != null)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: _loadReplies,
                  child: Text(_replyError!),
                ),
              ),
            if (!_replyLoading && _replies.isEmpty && _replyError == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('还没有回复')),
              ),
            SliverList.builder(
              itemCount: _replies.length,
              itemBuilder: (context, index) {
                final row = _replies[index];
                void openReply() => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PostDetailScreen(
                      controller: c,
                      postId: row.post,
                      initialCommentId: row.id,
                      loadImages: widget.loadImages,
                      onAuthenticationRequired: widget.onAuthenticationRequired,
                    ),
                  ),
                );
                return HhXPostItem(
                  post: FeedPostView(
                    id: row.id,
                    authorId: '',
                    authorName: row.nickname,
                    elapsed: _postDate(
                      DateTime.parse(row.data['publishedAt'] as String),
                    ),
                    title: row.body,
                    comments: row.replyCount,
                    likes: row.likes,
                    liked: row.liked,
                    channelCode: '',
                    availableActions: const {FeedAction.comment},
                  ),
                  avatarBuilder: (_, __) => DetailAvatar(
                    name: row.nickname,
                    avatar: row.avatar,
                    radius: 21,
                  ),
                  mediaBuilder: (_, __) => const SizedBox.shrink(),
                  mediaSection:
                      row.data['image'] != null &&
                          CommentScope.maybeOf(context) != null
                      ? CommentImageView(
                          runtime: CommentScope.maybeOf(context)!,
                          row: row,
                        )
                      : null,
                  onPost: openReply,
                  onAuthor: () {},
                  onMenu: openReply,
                  onMedia: (_) => openReply(),
                  onAction: (_) => openReply(),
                );
              },
            ),
          ] else if (_tab == 2)
            ..._repostSlivers()
          else ...[
            if (_collectionLoading.contains(_tab) &&
                !_collections.containsKey(_tab))
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (_collectionErrors[_tab] case final error?)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () => _loadCollection(_tab),
                  child: Text(error),
                ),
              ),
            if (!_collectionLoading.contains(_tab) &&
                !_collectionErrors.containsKey(_tab) &&
                _collectionItems(_tab).isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(_tab == 3 ? '还没有喜欢的帖子' : '还没有收藏的帖子')),
              ),
            SliverList.builder(
              itemCount: _collectionItems(_tab).length,
              itemBuilder: (_, index) {
                final post = _collectionItems(_tab)[index];
                return _ProfilePost(
                  key: ValueKey(('collection', _tab, post.postId)),
                  post: post,
                  controller: c,
                  loadImages: widget.loadImages,
                  own: false,
                  onOpen: () => _open(
                    PersonalPostItem(
                      id: post.postId,
                      title: post.title,
                      sortAt: post.publishedAt,
                      post: post,
                    ),
                  ),
                );
              },
            ),
            if (_collectionCursors[_tab] != null)
              SliverToBoxAdapter(
                child: _LoadMore(
                  loading: _collectionLoading.contains(_tab),
                  hasMore: true,
                  onPressed: () => _loadCollection(_tab, more: true),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileTabs extends SliverPersistentHeaderDelegate {
  _ProfileTabs({
    required this.selected,
    required this.hot,
    required this.onSelect,
    required this.onSort,
  });
  final int selected;
  final bool hot;
  final ValueChanged<int> onSelect;
  final ValueChanged<bool> onSort;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  bool shouldRebuild(_ProfileTabs old) => true;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    const labels = ['帖子', '回复', '转帖', '喜欢', '收藏'];
    const icons = [
      Icons.article_outlined,
      Icons.chat_bubble_outline,
      Icons.repeat,
      Icons.favorite_border,
      Icons.bookmark_border,
    ];
    return Material(
      color: Colors.white,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    selected: selected == i,
                    button: true,
                    label: labels[i],
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('profile-tab-$i'),
                      tween: Tween(end: selected == i ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, _) {
                        final color = Color.lerp(
                          const Color(0xFF929292),
                          Colors.black,
                          progress,
                        )!;
                        final label = SizedBox(
                          height: 56,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icons[i],
                                      size: 16 + 5 * progress,
                                      color: color,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          labels[i],
                                          style: TextStyle(
                                            fontSize: 11 + 3 * progress,
                                            fontWeight: selected == i
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: color,
                                          ),
                                        ),
                                        if (i == 0)
                                          Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 12 + 2 * progress,
                                            color: color,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                        if (i == 0 && selected == 0) {
                          return PopupMenuButton<bool>(
                            tooltip: '帖子排序',
                            initialValue: hot,
                            onSelected: onSort,
                            padding: EdgeInsets.zero,
                            itemBuilder: (_) => [
                              CheckedPopupMenuItem(
                                value: false,
                                checked: !hot,
                                child: const Text('最新'),
                              ),
                              CheckedPopupMenuItem(
                                value: true,
                                checked: hot,
                                child: const Text('最热'),
                              ),
                            ],
                            child: label,
                          );
                        }
                        return InkWell(onTap: () => onSelect(i), child: label);
                      },
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: .5, color: const Color(0xFFEAEAEA)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedAlign(
              alignment: Alignment(-1 + selected / 2, 0),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: const FractionallySizedBox(
                widthFactor: .2,
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 2,
                    child: ColoredBox(color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodEditor extends StatefulWidget {
  const _MoodEditor({
    required this.initial,
    required this.onSave,
    required this.authority,
    required this.isCurrent,
  });
  final String initial;
  final Future<void> Function(String) onSave;
  final Listenable authority;
  final bool Function() isCurrent;
  @override
  State<_MoodEditor> createState() => _MoodEditorState();
}

class _MoodEditorState extends State<_MoodEditor> {
  late final _text = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.authority.addListener(_changed);
  }

  void _changed() {
    if (mounted && !widget.isCurrent()) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.authority.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !widget.isCurrent()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_text.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '此刻的心情',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('mood-input'),
            controller: _text,
            enabled: !_saving,
            autofocus: true,
            maxLength: 12,
            maxLines: 2,
            style: const TextStyle(color: Colors.black, fontSize: 18),
            decoration: InputDecoration(
              hintText: '用一句话，记录现在',
              errorText: _error,
              border: InputBorder.none,
            ),
          ),
          const Text(
            '24 小时后自动消失',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '完成'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ProfilePost extends StatefulWidget {
  const _ProfilePost({
    super.key,
    required this.post,
    required this.controller,
    required this.onOpen,
    this.loadImages,
    this.own = true,
    this.initialDetail,
    this.onMenu,
    this.repostAction,
  });
  final PostDetail? initialDetail;
  final bool own;
  final PostCard post;
  final PostController controller;
  final VoidCallback onOpen;
  final VoidCallback? onMenu;
  final Widget? repostAction;
  final PostImagesLoader? loadImages;
  @override
  State<_ProfilePost> createState() => _ProfilePostState();
}

class _ProfilePostState extends State<_ProfilePost> {
  late final _authority = _PostAuthority(widget.controller);
  PostDetail? _detail;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    final detail =
        widget.initialDetail ??
        await widget.controller.loadDetail(widget.post.postId);
    if (!mounted || !_authority.current) return;
    setState(() {
      _detail = detail;
      _failed = detail == null;
    });
    await widget.controller.loadInteractions([
      widget.post.postId,
    ], single: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final detail = widget.initialDetail ?? _detail;
    final interaction = widget.controller.supportsInteractions
        ? widget.controller.interaction(p.postId)
        : PostInteractionState();
    return HhXPostItem(
      repostAction: widget.repostAction,
      post: FeedPostView(
        id: p.postId,
        authorId: '',
        authorName: p.author.displayName,
        elapsed: _postDate(p.publishedAt),
        title: p.title,
        body: detail?.body ?? '',
        comments: interaction.value?.commentCount,
        likes: interaction.likes,
        liked: interaction.liked,
        bookmarked: interaction.favorited,
        availableActions: {
          FeedAction.comment,
          if (interaction.canChange) ...[FeedAction.like, FeedAction.bookmark],
        },
        channelCode: '',
        isOwnAuthor: widget.own,
      ),
      avatarBuilder: (_, __) => DetailAvatar(
        name: p.author.displayName,
        avatar: p.author.avatar,
        radius: 21,
      ),
      mediaBuilder: (_, __) => const SizedBox.shrink(),
      mediaSection: _failed
          ? TextButton(onPressed: _load, child: const Text('内容加载失败，点击重试'))
          : detail != null && detail.imageCount > 0 && widget.loadImages != null
          ? PostImagesSection(
              postId: p.postId,
              loadImages: widget.loadImages!,
              authority: widget.controller,
              isCurrent: () =>
                  _authority.current &&
                  !widget.controller.isPostDeleted(p.postId),
              expectedCount: detail.imageCount,
              feedPreview: true,
            )
          : null,
      onPost: widget.onOpen,
      onAuthor: () {},
      onMenu: widget.onMenu ?? widget.onOpen,
      onMedia: (_) => widget.onOpen(),
      onAction: (action) {
        if (action == FeedAction.comment) {
          widget.onOpen();
          return;
        }
        if (action == FeedAction.like || action == FeedAction.bookmark) {
          unawaited(
            widget.controller.changeInteraction(
              p.postId,
              action == FeedAction.like
                  ? PostInteractionAction.like
                  : PostInteractionAction.favorite,
            ),
          );
        }
      },
    );
  }
}

/// White speech bubble whose tail points upward toward the adjacent avatar.
class _MoodBubbleBorder extends ShapeBorder {
  const _MoodBubbleBorder();
  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.only(top: 8);
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(rect.left, rect.top + 8, rect.right, rect.bottom),
          const Radius.circular(18),
        ),
      );
    final tail = Path()
      ..moveTo(rect.right - 38, rect.top + 10)
      ..lineTo(rect.right - 22, rect.top)
      ..lineTo(rect.right - 23, rect.top + 12)
      ..close();
    return Path.combine(PathOperation.union, body, tail);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      Paint()
        ..color = const Color(0xFFE4E4E4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }
}
