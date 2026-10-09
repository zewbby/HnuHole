import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../identity/identity_api.dart';
import 'post_controller.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_theme.dart';

class ChannelPostsScreen extends StatefulWidget {
  const ChannelPostsScreen({
    super.key,
    required this.controller,
    required this.channel,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
    this.onOpenPersonal,
  });
  final PostController controller;
  final Channel channel;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  final VoidCallback? onOpenPersonal;
  @override
  State<ChannelPostsScreen> createState() => _ChannelPostsScreenState();
}

class _ChannelPostsScreenState extends State<ChannelPostsScreen> {
  final _scroll = ScrollController();
  final _cardKeys = <String, GlobalKey>{};
  List<String> _lastPostIds = [];
  int _lastPublicationSequence = 0;
  bool _publicationVisible = false;
  Timer? _publicationTimer;
  late final _PostAuthority _authority;
  @override
  void initState() {
    super.initState();
    _authority = _PostAuthority(widget.controller);
    _lastPublicationSequence =
        widget.controller.latestPublicationNotice?.sequence ?? 0;
    widget.controller.addListener(_changed);
    unawaited(widget.controller.loadFeed(widget.channel.id));
  }

  void _changed() {
    if (!mounted) return;
    final notice = widget.controller.latestPublicationNotice;
    if (!_authority.current) {
      _publicationVisible = false;
      _publicationTimer?.cancel();
    } else if (notice != null && notice.sequence > _lastPublicationSequence) {
      _lastPublicationSequence = notice.sequence;
      if (notice.channelId == widget.channel.id) {
        _publicationVisible = true;
        _publicationTimer?.cancel();
        _publicationTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _publicationVisible = false);
        });
      }
    }
    final ids = widget.controller.feedItems.map((p) => p.postId).toList();
    final changedAtFront =
        _lastPostIds.isNotEmpty &&
        ids.isNotEmpty &&
        ids.first != _lastPostIds.first &&
        ids.contains(_lastPostIds.first);
    String? anchor;
    double? anchorY, previousOffset;
    if (_authority.current &&
        changedAtFront &&
        _scroll.hasClients &&
        _scroll.offset > 20) {
      previousOffset = _scroll.offset;
      for (final id in _lastPostIds) {
        if (!ids.contains(id)) continue;
        final render = _cardKeys[id]?.currentContext?.findRenderObject();
        if (render is! RenderBox || !render.attached) continue;
        final y = render.localToGlobal(Offset.zero).dy;
        if (y >= 100 && (anchorY == null || y < anchorY)) {
          anchor = id;
          anchorY = y;
        }
      }
    }
    _lastPostIds = ids;
    setState(() {});
    if (anchor != null) {
      final id = anchor, oldY = anchorY!, offset = previousOffset!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_authority.current ||
            !_scroll.hasClients ||
            (_scroll.offset - offset).abs() > 1) {
          return;
        }
        final render = _cardKeys[id]?.currentContext?.findRenderObject();
        if (render is! RenderBox || !render.attached) return;
        // 已滚离顶部时补偿新帖插入高度，保持原可见帖子而不强拉回顶部。
        final target = (offset + render.localToGlobal(Offset.zero).dy - oldY)
            .clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            );
        if ((target - _scroll.offset).abs() > 1) _scroll.jumpTo(target);
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _publicationTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _compose() async {
    if (!_authority.current) return;
    final editor = widget.controller.newDraft(widget.channel.id);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PostComposerScreen(
          controller: widget.controller,
          editor: editor,
          channelName: widget.channel.name,
          onManageIdentities: widget.onManageIdentities,
          onAuthenticationRequired: widget.onAuthenticationRequired,
        ),
      ),
    );
    // 返回保留列表位置；新公开事实由刷新取得，不重建 ScrollController。
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PostTheme.of(context),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(widget.channel.name)),
        body: !_authority.current
            ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '最新发布',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: PostTheme.background,
                            child: _feed(context),
                          ),
                        ),
                        if (_publicationVisible)
                          Positioned(
                            top: 12,
                            left: 24,
                            right: 24,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Semantics(
                                liveRegion: true,
                                child: Material(
                                  color: PostTheme.accent,
                                  borderRadius: BorderRadius.circular(8),
                                  elevation: 2,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      '发布成功！',
                                      style: TextStyle(
                                        color: PostTheme.surface,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PostTheme.line)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.home_outlined), Text('首页')],
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _authority.current ? _compose : null,
                  child: const Icon(Icons.add, semanticLabel: '新建帖子', size: 30),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _authority.current
                        ? widget.onOpenPersonal
                        : null,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.person_outline), Text('我的')],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _feed(BuildContext context) {
    final c = widget.controller;
    if (c.currentChannelId != widget.channel.id ||
        c.feedLoading && c.feedItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: '正在加载帖子'),
      );
    }
    if (c.feedItems.isEmpty && c.feedError != null) {
      return _PageState(
        title: '暂时无法加载帖子',
        message: '请稍后重试',
        action: '重新加载',
        onAction: () => c.loadFeed(widget.channel.id),
      );
    }
    if (c.feedItems.isEmpty) {
      return const _PageState(title: '这里还没有帖子', message: '点下方「＋」，发布第一篇帖子。');
    }
    return RefreshIndicator(
      onRefresh: () => c.loadFeed(widget.channel.id),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final single =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(16) > 22;
          final cards = [
            for (final post in c.feedItems)
              _PostCardWidget(
                post: post,
                key: _cardKeys.putIfAbsent(post.postId, () => GlobalKey()),
                onOpen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailScreen(
                        controller: c,
                        postId: post.postId,
                        channelName: widget.channel.name,
                        onAuthenticationRequired:
                            widget.onAuthenticationRequired,
                      ),
                    ),
                  );
                },
              ),
          ];
          return CustomScrollView(
            controller: _scroll,
            key: PageStorageKey(
              'feed:${_authority.account}:${_authority.version}:${widget.channel.id}',
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: single
                    ? SliverList.separated(
                        itemCount: cards.length,
                        itemBuilder: (_, i) => cards[i],
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                      )
                    : SliverToBoxAdapter(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var column = 0; column < 2; column++) ...[
                              if (column == 1) const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  children: [
                                    for (
                                      var i = column;
                                      i < cards.length;
                                      i += 2
                                    )
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: cards[i],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
              if (c.feedError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(c.feedError!, textAlign: TextAlign.center),
                  ),
                ),
              SliverToBoxAdapter(
                child: _LoadMore(
                  loading: c.feedLoading,
                  hasMore: c.feedCursor != null,
                  onPressed: () => c.loadFeed(widget.channel.id, more: true),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({
    super.key,
    required this.controller,
    required this.editor,
    required this.channelName,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
  });
  final PostController controller;
  final PostDraftEditor editor;
  final String channelName;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  late final TextEditingController _title, _body;
  Timer? _autoSave;
  bool _leaving = false, _allowPop = false, _retryPreparing = false;
  ManagedIdentity? _retryIdentity;
  String? _validation;
  bool get _current => widget.controller.editorCurrent(widget.editor);
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.editor.title);
    _body = TextEditingController(text: widget.editor.body);
    _title.addListener(_edit);
    _body.addListener(_edit);
    widget.controller.addListener(_changed);
    if (widget.editor.isRetry) unawaited(_prepareRetry());
  }

  Future<void> _prepareRetry() async {
    _retryPreparing = true;
    final identities = await widget.controller.prepareComposer(widget.editor);
    if (!mounted || !_current) return;
    setState(() {
      _retryPreparing = false;
      _retryIdentity = identities
          .where((i) => i.id == widget.editor.identityId)
          .firstOrNull;
    });
  }

  void _edit() {
    if (!_current) return;
    widget.editor.title = _title.text;
    widget.editor.body = _body.text;
    widget.editor.saved = false;
    _autoSave?.cancel();
    _autoSave = Timer(const Duration(milliseconds: 700), () {
      // 不裁剪 IME 组合输入；完成组合后再持久编辑内容。
      if (mounted && _current && !_composing && !_leaving) {
        unawaited(widget.controller.saveDraft(widget.editor));
      }
    });
    if (mounted) setState(() => _validation = null);
  }

  void _changed() {
    if (!_current) {
      _autoSave?.cancel();
      // 会话变更当场清 UI 缓冲；普通退出不删除原账号持久草稿。
      _title.removeListener(_edit);
      _body.removeListener(_edit);
      _title.clear();
      _body.clear();
    }
    if (mounted) setState(() {});
  }

  bool get _composing =>
      _title.value.composing.isValid && !_title.value.composing.isCollapsed ||
      _body.value.composing.isValid && !_body.value.composing.isCollapsed;
  Future<void> _next() async {
    if (!_current || _leaving || _composing || _retryPreparing) return;
    try {
      PostContentRules.validate(_title.text, _body.text);
    } on FormatException {
      setState(() => _validation = '请填写标题和正文，标题最多15字，正文最多3000字。');
      return;
    }
    FocusScope.of(context).unfocus();
    _autoSave?.cancel();
    if (widget.editor.isRetry) {
      setState(() => _leaving = true);
      final stored = await widget.controller.publish(widget.editor);
      if (!mounted || !_current) return;
      setState(() {
        _leaving = false;
        if (stored) _allowPop = true;
      });
      if (stored) Navigator.of(context).pop(true);
      return;
    }
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _PostConfirmScreen(
          controller: widget.controller,
          editor: widget.editor,
          channelName: widget.channelName,
          onManageIdentities: widget.onManageIdentities,
          onAuthenticationRequired: widget.onAuthenticationRequired,
        ),
      ),
    );
    if (!mounted || !_current) return;
    if (published == true) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    if (!_current) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
      return;
    }
    setState(() => _leaving = true);
    _autoSave?.cancel();
    final saved = await widget.controller.saveDraft(widget.editor);
    if (!mounted || !_current) return;
    setState(() => _leaving = false);
    if (saved) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } else {
      await _saveFailed();
    }
  }

  Future<void> _saveFailed() async {
    final authority = _PostAuthority(widget.controller);
    final retry = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Theme(
        data: PostTheme.of(context),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Dialog(
            backgroundColor: PostTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: authority.current
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '草稿保存失败',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '内容还在当前页面。\n放弃将丢失未保存的修改。',
                              textAlign: TextAlign.center,
                              style: PostTheme.dialogBody,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('放弃'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('重试'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const Text('会话已变化，请重新登录。'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || !_current || !authority.current) return;
    if (retry == true) {
      await _leave();
    } else if (retry == false) {
      final discarded = await widget.controller.discardDraft(widget.editor);
      if (!mounted || !_current || !discarded) return;
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _autoSave?.cancel();
    widget.controller.removeListener(_changed);
    _title.removeListener(_edit);
    _body.removeListener(_edit);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PostTheme.of(context),
    child: Builder(
      builder: (context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 56 + MediaQuery.textScalerOf(context).scale(13),
            leading: IconButton(
              tooltip: '返回',
              onPressed: _leave,
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.editor.isRetry ? '编辑草稿' : '写帖子',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: PostTheme.muted),
                ),
              ],
            ),
            actions: [
              if (!widget.editor.isRetry)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(
                    onPressed: _current && !_leaving && !_composing
                        ? _next
                        : null,
                    child: const Text('下一步'),
                  ),
                ),
            ],
          ),
          body: !_current
              ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
              : SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.editor.isRetry)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 20),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error,
                                        color: PostTheme.failure,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '上次发布未成功，内容已保留。',
                                          style: TextStyle(
                                            color: PostTheme.muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const Text(
                                '标题',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: PostTheme.muted,
                                ),
                              ),
                              TextField(
                                key: const ValueKey('post-title-input'),
                                controller: _title,
                                minLines: 1,
                                maxLines: null,
                                textInputAction: TextInputAction.newline,
                                enabled: !_leaving,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '写一个标题',
                                  border: InputBorder.none,
                                ),
                              ),
                              if (_title.text.characters.length >= 12)
                                Text(
                                  '${_title.text.characters.length}/15',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: _title.text.characters.length > 15
                                        ? Theme.of(context).colorScheme.error
                                        : PostTheme.muted,
                                  ),
                                ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(),
                              ),
                              const Text(
                                '正文',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: PostTheme.muted,
                                ),
                              ),
                              TextField(
                                key: const ValueKey('post-body-input'),
                                controller: _body,
                                minLines: widget.editor.isRetry ? 4 : 8,
                                maxLines: null,
                                enabled: !_leaving,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.7,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '想说的话，写在这里',
                                  border: InputBorder.none,
                                ),
                              ),
                              if (_body.text.characters.length >= 2700)
                                Text(
                                  '${_body.text.characters.length}/3000',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: _body.text.characters.length > 3000
                                        ? Theme.of(context).colorScheme.error
                                        : PostTheme.muted,
                                  ),
                                ),
                              if (widget.editor.isRetry) ...[
                                const Divider(),
                                const SizedBox(height: 20),
                                const Text(
                                  '发言身份',
                                  style: TextStyle(color: PostTheme.muted),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const _IdentityAvatar(radius: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _retryIdentity?.nickname ?? '原发送身份',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.lock_outline, size: 20),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 20),
                                const Text(
                                  '通道',
                                  style: TextStyle(color: PostTheme.muted),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.channelName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.lock_outline, size: 20),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '身份和通道保持不变',
                                  style: TextStyle(color: PostTheme.muted),
                                ),
                              ],
                              if (_validation != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _validation!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.editor.saving
                                ? '正在保存草稿'
                                : widget.editor.saved
                                ? '草稿已保存'
                                : '尚有未保存修改',
                            style: const TextStyle(color: PostTheme.muted),
                          ),
                        ),
                      ),
                      if (widget.editor.error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Text(
                            widget.editor.error!,
                            style: const TextStyle(color: PostTheme.errorInk),
                          ),
                        ),
                      if (widget.editor.isRetry)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  _current &&
                                      !_leaving &&
                                      !_composing &&
                                      !_retryPreparing
                                  ? _next
                                  : null,
                              child: Text(_leaving ? '正在保存发布操作' : '确认重试'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
}

class _PostConfirmScreen extends StatefulWidget {
  const _PostConfirmScreen({
    required this.controller,
    required this.editor,
    required this.channelName,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
  });
  final PostController controller;
  final PostDraftEditor editor;
  final String channelName;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  @override
  State<_PostConfirmScreen> createState() => _PostConfirmScreenState();
}

class _PostConfirmScreenState extends State<_PostConfirmScreen> {
  List<ManagedIdentity> _identities = [];
  bool _loading = true, _publishing = false;
  bool get _current => widget.controller.editorCurrent(widget.editor);
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(_prepare());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    if (!_current) return;
    setState(() => _loading = true);
    final identities = await widget.controller.prepareComposer(widget.editor);
    if (!mounted || !_current) return;
    setState(() {
      _identities = identities;
      _loading = false;
    });
  }

  Future<void> _manage() async {
    if (!_current || _publishing) return;
    await widget.onManageIdentities();
    if (mounted && _current) await _prepare();
  }

  Future<void> _pick() async {
    if (!_current || _publishing || _loading || widget.editor.isRetry) return;
    if (_identities.isEmpty) {
      await _manage();
      return;
    }
    final authority = _PostAuthority(widget.controller);
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: PostTheme.surface,
      builder: (context) => Theme(
        data: PostTheme.of(context),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => authority.current
              ? SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .8,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '选择发言身份',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '关闭身份选择',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final identity in _identities)
                            ListTile(
                              leading: const _IdentityAvatar(),
                              title: Text(identity.nickname),
                              trailing: widget.editor.identityId == identity.id
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: PostTheme.accent,
                                    )
                                  : const Icon(
                                      Icons.radio_button_unchecked,
                                      color: PostTheme.muted,
                                    ),
                              onTap: () =>
                                  Navigator.of(context).pop(identity.id),
                            ),
                          const Divider(),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop('manage'),
                            child: const Text('管理身份'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(
                  height: 120,
                  child: Center(child: Text('会话已变化，请重新登录。')),
                ),
        ),
      ),
    );
    if (!mounted || !_current || !authority.current) return;
    if (selection == 'manage') {
      await _manage();
      return;
    }
    if (selection != null &&
        _identities.any((identity) => identity.id == selection)) {
      setState(() {
        widget.editor.identityId = selection;
        widget.editor.saved = false;
      });
    }
  }

  Future<void> _publish() async {
    if (!_current ||
        _publishing ||
        _loading ||
        widget.editor.identityId == null) {
      return;
    }
    setState(() => _publishing = true);
    final saved = await widget.controller.publish(widget.editor);
    if (!mounted || !_current) return;
    if (saved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _publishing = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _identities
        .where((identity) => identity.id == widget.editor.identityId)
        .firstOrNull;
    return Theme(
      data: PostTheme.of(context),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            toolbarHeight: 56 + MediaQuery.textScalerOf(context).scale(13),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('发布确认'),
                Text(
                  widget.channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: PostTheme.muted),
                ),
              ],
            ),
          ),
          body: !_current
              ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
              : SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            const Text(
                              '标题',
                              style: TextStyle(color: PostTheme.muted),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.editor.title,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Divider(),
                            const SizedBox(height: 24),
                            const Text(
                              '发言身份',
                              style: TextStyle(color: PostTheme.muted),
                            ),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(),
                              ),
                            if (!_loading)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const _IdentityAvatar(radius: 26),
                                title: Text(
                                  selected?.nickname ??
                                      (widget.editor.isRetry
                                          ? '原发送身份'
                                          : _identities.isEmpty
                                          ? '先设置一个身份'
                                          : '请选择身份'),
                                ),
                                subtitle: widget.editor.isRetry
                                    ? const Text('重试保留原身份和通道')
                                    : const Text('用于本次发布'),
                                trailing: widget.editor.isRetry
                                    ? null
                                    : const Icon(Icons.expand_more),
                                onTap: _pick,
                              ),
                            const Divider(),
                            if (!_loading &&
                                _identities.isEmpty &&
                                !widget.editor.isRetry)
                              TextButton(
                                onPressed: _manage,
                                child: const Text('设置身份'),
                              ),
                            if (widget.editor.error != null)
                              Text(
                                widget.editor.error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                !_loading &&
                                    !_publishing &&
                                    widget.editor.identityId != null
                                ? _publish
                                : null,
                            child: Text(_publishing ? '正在保存发布操作' : '确认发布'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class PersonalPostsScreen extends StatefulWidget {
  const PersonalPostsScreen({
    super.key,
    required this.controller,
    required this.channelNames,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
    this.onOpenSettings,
    this.onPublishedToChannel,
    this.onChooseChannel,
  });
  final PostController controller;
  final Map<String, String> channelNames;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  final VoidCallback? onOpenSettings;
  final ValueChanged<String>? onPublishedToChannel;
  final VoidCallback? onChooseChannel;
  @override
  State<PersonalPostsScreen> createState() => _PersonalPostsScreenState();
}

class _PersonalPostsScreenState extends State<PersonalPostsScreen> {
  late final _PostAuthority _authority;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _authority = _PostAuthority(widget.controller);
    widget.controller.addListener(_changed);
    unawaited(widget.controller.loadPersonal());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(PersonalPostItem item) async {
    if (!_authority.current) return;
    if (item.post != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(
            controller: widget.controller,
            postId: item.post!.postId,
            channelName: widget.channelNames[item.post!.channelId],
            onAuthenticationRequired: widget.onAuthenticationRequired,
          ),
        ),
      );
    } else if (item.isDraft) {
      final editor = await widget.controller.restoreDraft(item.id);
      if (!mounted || !_authority.current || editor == null) return;
      final published = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PostComposerScreen(
            controller: widget.controller,
            editor: editor,
            channelName: widget.channelNames[editor.channelId] ?? '原通道',
            onManageIdentities: widget.onManageIdentities,
            onAuthenticationRequired: widget.onAuthenticationRequired,
          ),
        ),
      );
      if (mounted && _authority.current && published == true) {
        widget.onPublishedToChannel?.call(editor.channelId);
        return;
      }
    } else if (item.task?.state == PostTaskState.failed &&
        item.task?.canRetry == true &&
        !{'SUBMITTED', 'UNKNOWN', 'RESULT_EXPIRED'}.contains(item.state)) {
      final editor = await widget.controller.editFailedTask(item.task!.taskId);
      if (!mounted || !_authority.current || editor == null) return;
      final published = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PostComposerScreen(
            controller: widget.controller,
            editor: editor,
            channelName: widget.channelNames[editor.channelId] ?? '原通道',
            onManageIdentities: widget.onManageIdentities,
            onAuthenticationRequired: widget.onAuthenticationRequired,
          ),
        ),
      );
      if (mounted && _authority.current && published == true) {
        widget.onPublishedToChannel?.call(editor.channelId);
      }
    } else {
      final publishedChannel = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => _PostTaskScreen(
            controller: widget.controller,
            itemId: item.id,
            channelNames: widget.channelNames,
            onManageIdentities: widget.onManageIdentities,
            onAuthenticationRequired: widget.onAuthenticationRequired,
          ),
        ),
      );
      if (mounted && _authority.current && publishedChannel != null) {
        widget.onPublishedToChannel?.call(publishedChannel);
      }
    }
  }

  Future<void> _deleteDraft(PersonalPostItem item) async {
    if (!item.isDraft || !_authority.current) return;
    final confirmed = await _confirmScoped(
      context,
      widget.controller,
      title: '确认删除这篇草稿？',
      message: '',
      action: '删除草稿',
    );
    if (!mounted || !_authority.current || confirmed != true) return;
    final editor = await widget.controller.restoreDraft(item.id);
    if (!mounted || !_authority.current || editor == null) return;
    await widget.controller.discardDraft(editor);
  }

  Future<void> _deleteFailedTask(PersonalPostItem item) async {
    final task = item.task;
    if (!_authority.current ||
        task?.canHide != true ||
        widget.controller.busy ||
        {'SUBMITTED', 'UNKNOWN', 'RESULT_EXPIRED'}.contains(item.state)) {
      return;
    }
    final confirmed = await _confirmScoped(
      context,
      widget.controller,
      title: '删除这篇失败草稿？',
      message: '',
      action: '删除失败入口',
    );
    if (!mounted || !_authority.current || confirmed != true) return;
    await widget.controller.hideTask(task!.taskId);
  }

  void _chooseChannel() {
    if (widget.onChooseChannel != null) {
      widget.onChooseChannel!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PostTheme.of(context),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('我的'),
          actions: [
            if (widget.onOpenSettings != null)
              IconButton(
                tooltip: '设置',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        body: !_authority.current
            ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
            : _content(),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PostTheme.line)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _chooseChannel,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.home_outlined), Text('首页')],
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _authority.current ? _chooseChannel : null,
                  child: const Icon(
                    Icons.add,
                    size: 30,
                    semanticLabel: '选择通道写帖子',
                  ),
                ),
                Expanded(
                  child: Semantics(
                    selected: true,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.person), Text('我的')],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content() {
    final c = widget.controller;
    return RefreshIndicator(
      onRefresh: c.loadPersonal,
      child: CustomScrollView(
        controller: _scroll,
        key: PageStorageKey(
          'personal-posts:${_authority.account}:${_authority.version}',
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.personalIdentity != null) ...[
                    Row(
                      children: [
                        const _IdentityAvatar(radius: 30),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.personalIdentity!.nickname,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '仅自己可见',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: PostTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    '自己的帖子',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: PostTheme.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (c.personalLoading && c.personalItems.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(semanticsLabel: '正在加载自己的帖子'),
              ),
            )
          else if (c.personalItems.isEmpty && c.personalError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _PageState(
                title: '暂时无法加载自己的帖子',
                message: c.personalError,
                action: '重新加载',
                onAction: c.loadPersonal,
              ),
            )
          else if (c.personalItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _PageState(
                title: '还没有自己的帖子',
                message: '从通道开始，写下第一篇帖子。',
                action: '去选择通道',
                onAction: _chooseChannel,
              ),
            )
          else
            SliverToBoxAdapter(
              child: ColoredBox(
                color: PostTheme.background,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = [
                        for (final item in c.personalItems)
                          item.post != null
                              ? _PostCardWidget(
                                  key: ValueKey(item.id),
                                  post: item.post!,
                                  onOpen: () => _open(item),
                                )
                              : _PersonalCard(
                                  key: ValueKey(item.id),
                                  item: item,
                                  channelName:
                                      widget.channelNames[item.channelId] ??
                                      '原通道',
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
                      ];
                      return _PostWaterfall(
                        cards: cards,
                        single:
                            constraints.maxWidth < 360 ||
                            MediaQuery.textScalerOf(context).scale(16) > 22,
                      );
                    },
                  ),
                ),
              ),
            ),
          if (c.personalItems.isNotEmpty)
            SliverToBoxAdapter(
              child: ColoredBox(
                color: PostTheme.background,
                child: Column(
                  children: [
                    if (c.personalError != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          c.personalError!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    _LoadMore(
                      loading: c.personalLoading,
                      hasMore: c.personalHasMore,
                      onPressed: () => c.loadPersonal(more: true),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 内容自然撑高；错落双列与正式 My 图保持一致，不强制等高。
class _PostWaterfall extends StatelessWidget {
  const _PostWaterfall({required this.cards, required this.single});
  final List<Widget> cards;
  final bool single;
  @override
  Widget build(BuildContext context) => single
      ? Column(
          children: [
            for (final card in cards)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: card),
          ],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < 2; column++) ...[
              if (column == 1) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    for (var i = column; i < cards.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: cards[i],
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
}

class _PersonalCard extends StatelessWidget {
  const _PersonalCard({
    super.key,
    required this.item,
    required this.channelName,
    required this.onOpen,
    this.onDeleteDraft,
    this.onDeleteTask,
  });
  final PersonalPostItem item;
  final String channelName;
  final VoidCallback onOpen;
  final VoidCallback? onDeleteDraft, onDeleteTask;
  @override
  Widget build(BuildContext context) {
    final unknown = {
      'SUBMITTED',
      'UNKNOWN',
      'RESULT_EXPIRED',
    }.contains(item.state);
    final failed = !unknown && item.task?.state == PostTaskState.failed;
    final pending = !unknown && item.task?.state == PostTaskState.accepted;
    final label = unknown
        ? _localPostState(item.state)
        : pending
        ? '发布中'
        : failed
        ? '发布未成功'
        : _localPostState(item.state);
    return Material(
      color: pending || failed ? PostTheme.cardTint : PostTheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onDeleteDraft ?? onDeleteTask,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.title.isEmpty ? '未命名草稿' : item.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (item.isDraft || failed) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: PostTheme.accent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '草稿',
                        style: TextStyle(
                          color: PostTheme.surface,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (failed) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.error,
                        color: PostTheme.failure,
                        semanticLabel: '发布未成功',
                      ),
                    ],
                  ],
                ),
                if (failed)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '发布未成功',
                      style: TextStyle(color: PostTheme.accent),
                    ),
                  ),
              ] else if (pending)
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: '发布中',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(color: PostTheme.accent),
                      ),
                    ),
                  ],
                )
              else
                Text(label, style: const TextStyle(color: PostTheme.muted)),
              const SizedBox(height: 12),
              Text(
                '$channelName · ${_postDate(item.sortAt)}',
                style: const TextStyle(
                  color: PostTheme.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (onDeleteDraft != null || onDeleteTask != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: onDeleteDraft != null ? '删除草稿' : '删除失败入口',
                    onPressed: onDeleteDraft ?? onDeleteTask,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostTaskScreen extends StatefulWidget {
  const _PostTaskScreen({
    required this.controller,
    required this.itemId,
    required this.channelNames,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
  });
  final PostController controller;
  final String itemId;
  final Map<String, String> channelNames;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  @override
  State<_PostTaskScreen> createState() => _PostTaskScreenState();
}

class _PostTaskScreenState extends State<_PostTaskScreen> {
  late final _PostAuthority _authority;
  @override
  void initState() {
    super.initState();
    _authority = _PostAuthority(widget.controller);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  PersonalPostItem? get _item => widget.controller.personalItems
      .where((item) => item.id == widget.itemId)
      .firstOrNull;
  Future<void> _retry(PostTask task) async {
    final editor = await widget.controller.editFailedTask(task.taskId);
    if (!mounted || !_authority.current || editor == null) return;
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PostComposerScreen(
          controller: widget.controller,
          editor: editor,
          channelName: widget.channelNames[editor.channelId] ?? '原通道',
          onManageIdentities: widget.onManageIdentities,
          onAuthenticationRequired: widget.onAuthenticationRequired,
        ),
      ),
    );
    if (mounted && _authority.current && published == true) {
      Navigator.of(context).pop(editor.channelId);
    }
  }

  Future<void> _recover(PersonalPostItem item) async {
    final editor = await widget.controller.recoverUnaccepted(item.id);
    if (!mounted || !_authority.current || editor == null) return;
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PostComposerScreen(
          controller: widget.controller,
          editor: editor,
          channelName: widget.channelNames[editor.channelId] ?? '原通道',
          onManageIdentities: widget.onManageIdentities,
          onAuthenticationRequired: widget.onAuthenticationRequired,
        ),
      ),
    );
    if (mounted && _authority.current && published == true) {
      Navigator.of(context).pop(editor.channelId);
    }
  }

  Future<void> _discardUnaccepted(PersonalPostItem item) async {
    final confirmed = await _confirmScoped(
      context,
      widget.controller,
      title: '放弃未受理文字',
      message: '服务端已明确未受理原操作。放弃后删除本机文字，原操作的核对凭据仍保留。',
      action: '放弃文字',
    );
    if (!mounted || !_authority.current || confirmed != true) return;
    await widget.controller.discardUnaccepted(item.id);
  }

  Future<void> _hide(PostTask task) async {
    final confirmed = await _confirmScoped(
      context,
      widget.controller,
      title: '删除失败入口',
      message: '删除后不会恢复到自己的帖子中。',
      action: '删除',
    );
    if (!mounted || !_authority.current || confirmed != true) return;
    await widget.controller.hideTask(task.taskId);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item, task = item?.task;
    final resultUnknown =
        item != null &&
        {'SUBMITTED', 'UNKNOWN', 'RESULT_EXPIRED'}.contains(item.state);
    return Theme(
      data: PostTheme.of(context),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('发布任务')),
          body: !_authority.current
              ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
              : item == null
              ? const _PageState(title: '此任务已从列表移除', message: '返回自己的帖子查看当前结果。')
              : SafeArea(
                  top: false,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        task == null || resultUnknown
                            ? _localPostState(item.state)
                            : switch (task.state) {
                                PostTaskState.failed => '发布失败',
                                PostTaskState.accepted => '处理中',
                                PostTaskState.published => '已发布',
                                PostTaskState.cancelled => '已取消',
                              },
                        style: const TextStyle(color: PostTheme.muted),
                      ),
                      const SizedBox(height: 24),
                      if (task?.content != null)
                        SelectableText(
                          task!.content!.body,
                          style: const TextStyle(fontSize: 17, height: 1.7),
                        ),
                      if (task == null && item.body.isNotEmpty)
                        SelectableText(
                          item.body,
                          style: const TextStyle(fontSize: 17, height: 1.7),
                        ),
                      if (task == null || resultUnknown)
                        Text(
                          item.state == 'RESULT_EXPIRED'
                              ? '原结果已无法完整核对，请停止重复发布。'
                              : {
                                  'REJECTED',
                                  'NOT_ACCEPTED',
                                }.contains(item.state)
                              ? '服务端已明确拒绝原操作，未产生新发布效果。'
                              : '原操作尚未得到权威结果，请先核对。',
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: widget.controller.busy
                            ? null
                            : () => widget.controller.reconcile(item.id),
                        child: const Text('核对原操作'),
                      ),
                      if ({'SUBMITTED', 'UNKNOWN'}.contains(item.state))
                        TextButton(
                          onPressed: widget.controller.busy
                              ? null
                              : () => widget.controller.seal(item.id),
                          child: const Text('停止尚未受理的原操作'),
                        ),
                      if (task == null &&
                          {'REJECTED', 'NOT_ACCEPTED'}.contains(item.state) &&
                          item.local?.intents.lastOrNull?.operation ==
                              'CREATE' &&
                          item.local?.data['abandoned'] != true) ...[
                        OutlinedButton(
                          onPressed: widget.controller.busy
                              ? null
                              : () => _recover(item),
                          child: const Text('恢复为新草稿'),
                        ),
                        TextButton(
                          onPressed: widget.controller.busy
                              ? null
                              : () => _discardUnaccepted(item),
                          child: const Text('放弃未受理文字'),
                        ),
                      ],
                      if (!resultUnknown && task?.canCancel == true)
                        OutlinedButton(
                          onPressed: widget.controller.busy
                              ? null
                              : () =>
                                    widget.controller.cancelTask(task!.taskId),
                          child: const Text('取消本次发布'),
                        ),
                      if (!resultUnknown && task?.canRetry == true)
                        OutlinedButton(
                          onPressed: widget.controller.busy
                              ? null
                              : () => _retry(task!),
                          child: const Text('修改文字重试'),
                        ),
                      if (!resultUnknown && task?.canHide == true)
                        TextButton(
                          onPressed: widget.controller.busy
                              ? null
                              : () => _hide(task!),
                          child: const Text('删除失败入口'),
                        ),
                      if (widget.controller.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(widget.controller.errorMessage!),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.controller,
    required this.postId,
    this.channelName,
    this.onAuthenticationRequired,
  });
  final PostController controller;
  final String postId;
  final String? channelName;
  final VoidCallback? onAuthenticationRequired;
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final _PostAuthority _authority;
  PostDetail? _post;
  bool _loading = true, _canDelete = false, _deleting = false, _deleted = false;
  bool _returnScheduled = false;
  @override
  void initState() {
    super.initState();
    _authority = _PostAuthority(widget.controller);
    widget.controller.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (!mounted) return;
    if (_authority.current && widget.controller.isPostDeleted(widget.postId)) {
      _returnAfterDeletion();
      return;
    }
    setState(() {
      if (!_authority.current) _post = null;
    });
  }

  void _returnAfterDeletion() {
    if (!mounted || !_authority.current || _returnScheduled) return;
    setState(() {
      _deleted = true;
      _post = null;
      _canDelete = false;
    });
    _returnScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_authority.current) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent == true && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _load() async {
    if (!_authority.current) return;
    setState(() => _loading = true);
    final post = await widget.controller.loadDetail(widget.postId);
    if (!mounted || !_authority.current) return;
    setState(() {
      _post = post;
      _loading = false;
    });
    if (post != null) {
      final canDelete = await widget.controller.canDelete(widget.postId);
      if (mounted && _authority.current) setState(() => _canDelete = canDelete);
    }
  }

  Future<void> _delete() async {
    if (!_authority.current || !_canDelete || _deleting) return;
    final confirmed = await _confirmScoped(
      context,
      widget.controller,
      title: '确认删除这篇帖子？',
      message: '',
      action: '删除帖子',
    );
    if (!mounted || !_authority.current || confirmed != true) return;
    setState(() => _deleting = true);
    final deleted = await widget.controller.deletePost(widget.postId);
    if (!mounted || !_authority.current) return;
    setState(() {
      _deleting = false;
      if (deleted) _post = null;
    });
    if (deleted) _returnAfterDeletion();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PostTheme.of(context),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.channelName ?? '帖子'),
          actions: [
            if (_authority.current && _canDelete && !_deleted)
              IconButton(
                tooltip: '删除帖子',
                onPressed: _deleting ? null : _delete,
                icon: const Icon(Icons.more_horiz),
              ),
          ],
        ),
        body: !_authority.current
            ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
            : _deleted
            ? const SizedBox.shrink()
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : _post == null
            ? _PageState(
                title: '帖子不存在或暂时无法读取',
                message: widget.controller.errorMessage,
                action: '重新核对',
                onAction: _load,
              )
            : _detail(context, _post!),
      ),
    ),
  );
  Widget _detail(BuildContext context, PostDetail post) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      key: PageStorageKey(
        'detail:${_authority.account}:${_authority.version}:${widget.postId}',
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final author = _AuthorWidget(author: post.author);
                  final title = Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  );
                  if (constraints.maxWidth < 340 ||
                      MediaQuery.textScalerOf(context).scale(16) > 22) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 12), author],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 16),
                      Flexible(child: author),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                _postDate(post.publishedAt),
                style: const TextStyle(fontSize: 14, color: PostTheme.muted),
              ),
              const SizedBox(height: 32),
              SelectableText(
                post.body,
                style: const TextStyle(fontSize: 17, height: 1.8),
              ),
              if (widget.controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(widget.controller.errorMessage!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PostCardWidget extends StatelessWidget {
  const _PostCardWidget({super.key, required this.post, required this.onOpen});
  final PostCard post;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Material(
    color: PostTheme.surface,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: PostTheme.cardTint,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              child: Text(
                post.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthorWidget(author: post.author),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Text(
                    _postDate(post.publishedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: PostTheme.muted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AuthorWidget extends StatelessWidget {
  const _AuthorWidget({required this.author});
  final PostAuthor author;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: author.inactiveMessage == null
        ? null
        : () => ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(author.inactiveMessage!))),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _IdentityAvatar(radius: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              author.displayName,
              style: const TextStyle(fontSize: 13, color: PostTheme.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _IdentityAvatar extends StatelessWidget {
  const _IdentityAvatar({this.radius = 20});
  final double radius;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE4EAF0),
      foregroundColor: PostTheme.muted,
      child: Icon(Icons.person_outline_rounded, size: radius * 1.2),
    ),
  );
}

class _PageState extends StatelessWidget {
  const _PageState({
    required this.title,
    this.message,
    this.action,
    this.onAction,
  });
  final String title;
  final String? message, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: PostTheme.muted,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.loading,
    required this.hasMore,
    required this.onPressed,
  });
  final bool loading, hasMore;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: loading
          ? const CircularProgressIndicator()
          : hasMore
          ? TextButton(onPressed: onPressed, child: const Text('加载更多'))
          : const Text('已显示当前内容', style: TextStyle(color: PostTheme.muted)),
    ),
  );
}

class _AccessClosed extends StatelessWidget {
  const _AccessClosed({this.onAuthenticate});
  final VoidCallback? onAuthenticate;
  @override
  Widget build(BuildContext context) => _PageState(
    title: '请重新核对登录状态',
    message: '原账号的草稿和发布任务保留，登录后继续核对。',
    action: onAuthenticate == null ? null : '登录或恢复',
    onAction: onAuthenticate,
  );
}

// 页面与弹窗各自捕获scope；旧请求或用户迟到点按不能操作新账号。
class _PostAuthority {
  _PostAuthority(this.controller)
    : account = controller.accountId,
      version = controller.authorityVersion;
  final PostController controller;
  final String? account;
  final int version;
  bool get current =>
      controller.available &&
      account != null &&
      controller.accountId == account &&
      controller.authorityVersion == version;
}

Future<bool?> _confirmScoped(
  BuildContext context,
  PostController controller, {
  required String title,
  required String message,
  required String action,
}) {
  final authority = _PostAuthority(controller);
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => Theme(
      data: PostTheme.of(context),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Dialog(
          backgroundColor: PostTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: authority.current
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: PostTheme.dialogQuestion,
                            ),
                          ),
                          if (message.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                message,
                                textAlign: TextAlign.center,
                                style: PostTheme.dialogBody,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('取消'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Semantics(
                                  label: action,
                                  child: FilledButton(
                                    key: const ValueKey(
                                      'scoped-confirm-action',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: PostTheme.destructive,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('确认'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : const Text('会话已变化，请重新登录。', textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _postDate(DateTime date) {
  final local = date.toLocal();
  return '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _localPostState(String state) => switch (state) {
  'REJECTED' || 'NOT_ACCEPTED' => '未受理',
  'RESULT_EXPIRED' => '原结果无法完整核对',
  'ACCEPTED' => '发布中',
  'FAILED' => '发布未成功',
  'CANCELLED' => '已取消',
  'PUBLISHED' => '已发布',
  'DRAFT' => '草稿',
  _ => '结果未知',
};
