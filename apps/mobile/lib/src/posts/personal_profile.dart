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
          backgroundColor: HhTelegramPalette.of(context).surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            '确认移除？',
            style: TextStyle(color: HhTelegramPalette.of(context).ink),
          ),
          content: Text(
            '仅移除“${_repostIdentityNames[identityId] ?? '此身份'}”保存的这条记录。',
          ),
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
      backgroundColor: HhTelegramPalette.of(context).surface,
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
                  leading: Icon(
                    Icons.article_outlined,
                    color: HhTelegramPalette.of(context).secondary,
                  ),
                  title: Text(
                    '查看帖子',
                    style: TextStyle(color: HhTelegramPalette.of(context).ink),
                  ),
                  enabled: available,
                  onTap: () => choose('view'),
                ),
                ListTile(
                  key: ValueKey('report-repost:$identityId/$postId'),
                  leading: Icon(
                    Icons.flag_outlined,
                    color: HhTelegramPalette.of(context).secondary,
                  ),
                  title: Text(
                    '举报帖子',
                    style: TextStyle(color: HhTelegramPalette.of(context).ink),
                  ),
                  enabled: available && governance?.available == true,
                  onTap: () => choose('report'),
                ),
                ListTile(
                  key: ValueKey('cancel-repost:$identityId/$postId'),
                  leading: Icon(
                    Icons.remove_circle_outline,
                    color: HhTelegramPalette.of(context).secondary,
                  ),
                  title: Text(
                    '移除',
                    style: TextStyle(color: HhTelegramPalette.of(context).ink),
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
          final post = item.post;
          return Column(
            key: ValueKey('personal-repost:${item.key}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    tooltip: '移除',
                    color: const Color(0xFF229ED9),
                    onPressed: state.unresolved
                        ? null
                        : () =>
                              _confirmUndoRepost(item.postId, item.identityId),
                    icon: const PostRepostIcon(),
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
  final _profileIdentityAnchor = GlobalKey();
  bool _identityMenuOpen = false;
  Route<dynamic>? _identityMenuRoute;

  void _dismissProfileIdentityMenu() {
    final route = _identityMenuRoute;
    _identityMenuRoute = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  void profileIdentityChanged() {
    final id = widget.controller.personalIdentity?.id;
    if (id == _profileIdentityId) return;
    _profileIdentityId = id;
    ++_identityEpoch;
    _dismissProfileIdentityMenu();
    _hot = _sorting = false;
    _replies.clear();
    _replyLoaded = _replyLoading = false;
    _replyError = null;
    _offsets.remove(0);
    _offsets.remove(1);
    if (_tab == 1 && id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _authority.current) unawaited(_loadReplies());
      });
    }
  }

  Future<void> _chooseIdentity() async {
    if (_identityMenuOpen || !_authority.current) return;
    final controller = widget.controller;
    final epoch = _identityEpoch;
    final anchor =
        _profileIdentityAnchor.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect =
        anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
    final p = HhTelegramPalette.of(context);
    setState(() => _identityMenuOpen = true);
    final id = await showMenu<String>(
      context: context,
      positionBuilder: (context, constraints) {
        final current = anchor.attached && overlay.attached
            ? anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size
            : rect;
        return RelativeRect.fromRect(
          Rect.fromLTWH(current.right, current.bottom + 6, 0, 0),
          Offset.zero & constraints.biggest,
        );
      },
      constraints: const BoxConstraints(minWidth: 208, maxWidth: 260),
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
        reverseDuration: Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 40,
          child: Builder(
            builder: (context) {
              _identityMenuRoute = ModalRoute.of(context);
              if (!mounted || !_authority.current || epoch != _identityEpoch) {
                _dismissProfileIdentityMenu();
                return const SizedBox.shrink();
              }
              return Text(
                '切换身份',
                style: TextStyle(fontSize: 13, color: p.secondary),
              );
            },
          ),
        ),
        for (final identity in controller.personalIdentities)
          PopupMenuItem<String>(
            key: ValueKey('profile-identity-${identity.id}'),
            value: identity.id,
            height: 56,
            child: Row(
              children: [
                HhDmAvatar(
                  identity: DmIdentity(
                    id: identity.id,
                    name: identity.nickname,
                    avatar: identity.avatar,
                  ),
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    identity.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: p.ink),
                  ),
                ),
                if (identity.id == controller.personalIdentity?.id)
                  Icon(Icons.check_rounded, color: p.accent, size: 20),
              ],
            ),
          ),
      ],
    );
    _identityMenuRoute = null;
    if (!mounted) return;
    setState(() => _identityMenuOpen = false);
    if (id == null || !_authority.current || epoch != _identityEpoch) return;
    await controller.selectPersonalIdentity(id);
  }

  Widget _profileIdentityChip(String name) {
    final c = widget.controller;
    final p = HhTelegramPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 224, minHeight: 48),
      child: Tooltip(
        message: '切换身份',
        child: Semantics(
          label: '切换身份，当前$name',
          button: true,
          excludeSemantics: true,
          onTap: _chooseIdentity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('personal-profile'),
              onTap: c.personalIdentities.isEmpty ? null : _chooseIdentity,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Material(
                  key: _profileIdentityAnchor,
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: p.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedRotation(
                          turns: _identityMenuOpen ? .25 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: p.secondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: p.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        HhDmAvatar(
                          identity: DmIdentity(
                            id: c.personalIdentity?.id ?? '',
                            name: name,
                            avatar: c.personalIdentity?.avatar ?? 'default-v1',
                          ),
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hot = false, _sorting = false, _searching = false;
  String _query = '';
  final _offsets = <int, double>{};
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

  void disposeProfile() => _dismissProfileIdentityMenu();

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
              padding: const EdgeInsets.fromLTRB(24, 8, 14, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '我的',
                        key: const ValueKey('profile-title'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: HhTelegramPalette.of(context).action,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _profileIdentityChip(name),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: '搜索我的帖子',
                        icon: Icon(
                          Icons.search,
                          size: 28,
                          color: HhTelegramPalette.of(context).ink,
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
                        icon: Icon(
                          Icons.settings_outlined,
                          size: 28,
                          color: HhTelegramPalette.of(context).ink,
                        ),
                        onPressed: widget.onOpenSettings,
                      ),
                    ],
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
      color: HhTelegramPalette.of(context).surface,
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
                          HhTelegramPalette.of(context).secondary,
                          HhTelegramPalette.of(context).ink,
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
                                    if (i == 2)
                                      IconTheme(
                                        data: IconThemeData(color: color),
                                        child: PostRepostIcon(
                                          size: 16 + 5 * progress,
                                        ),
                                      )
                                    else
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
            child: Container(
              height: .5,
              color: HhTelegramPalette.of(context).line,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedAlign(
              alignment: Alignment(-1 + selected / 2, 0),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: .2,
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 2,
                    child: ColoredBox(color: HhTelegramPalette.of(context).ink),
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
