import '../design_system/detail_components.dart';
import 'x_feed.dart';
import '../comments/comment_runtime.dart';
import '../comments/comment_views.dart';
import '../comments/comment_models.dart';

import 'dart:async';

import '../messaging/dm_runtime.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../channels/channel.dart';
import '../identity/identity_api.dart';
import '../reports/report_screens.dart';
import '../storage/post_store.dart';
import 'post_controller.dart';
import 'post_reposts_widgets.dart';
import 'post_models.dart';
import 'post_images.dart';
import 'post_protocol.dart';
import 'post_theme.dart';
import 'post_upload_models.dart';

import 'package:hnuhole_image_viewer/image_viewer.dart';

part 'post_composer_photos.dart';
part 'personal_profile.dart';

class ChannelPostsScreen extends StatefulWidget {
  const ChannelPostsScreen({
    super.key,
    required this.controller,
    required this.channel,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
    this.onOpenPersonal,
    this.loadImages,
  });
  final PostController controller;
  final Channel channel;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  final VoidCallback? onOpenPersonal;
  final PostImagesLoader? loadImages;
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
        announceTitle: true,
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
                        loadImages: widget.loadImages,
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
      widget.controller.clearEditorMedia(widget.editor);
    }
    if (mounted) setState(() {});
  }

  bool get _composing =>
      _title.value.composing.isValid && !_title.value.composing.isCollapsed ||
      _body.value.composing.isValid && !_body.value.composing.isCollapsed;
  Future<void> _next() async {
    if (!_current ||
        _leaving ||
        _composing ||
        _retryPreparing ||
        widget.editor.mediaBusy) {
      return;
    }
    try {
      PostContentRules.validate(
        _title.text,
        _body.text,
        imageCount: widget.editor.images.length,
      );
      if (widget.editor.images.any((image) => !image.ready)) {
        throw const FormatException('Unreadable image');
      }
    } on FormatException {
      setState(
        () => _validation = widget.editor.images.any((image) => !image.ready)
            ? '请重新选择或移除无法读取的图片。'
            : '请填写标题，并提供正文或图片；标题最多15字，正文最多3000字。',
      );
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
    if (_leaving || widget.editor.mediaBusy) return;
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
                    onPressed:
                        _current &&
                            !_leaving &&
                            !_composing &&
                            !widget.editor.mediaBusy
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
                              _ComposerPhotos(
                                controller: widget.controller,
                                editor: widget.editor,
                                onChanged: _edit,
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
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _validation!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
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
                              selected: widget.editor.identityId == identity.id,
                              selectedColor: PostTheme.ink,
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
    this.navigation,
    this.showNavigation = true,
    required this.controller,
    required this.channelNames,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
    this.onOpenSettings,
    this.onPublishedToChannel,
    this.onChooseChannel,
    this.loadImages,
  });
  final Widget? navigation;
  final bool showNavigation;
  final PostController controller;
  final Map<String, String> channelNames;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  final VoidCallback? onOpenSettings;
  final ValueChanged<String>? onPublishedToChannel;
  final VoidCallback? onChooseChannel;
  final PostImagesLoader? loadImages;
  @override
  State<PersonalPostsScreen> createState() => _PersonalPostsScreenState();
}

class _PersonalPostsScreenState extends State<PersonalPostsScreen>
    with _PersonalProfile {
  @override
  late final _PostAuthority _authority;
  @override
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _authority = _PostAuthority(widget.controller);
    widget.controller.addListener(_changed);
    unawaited(widget.controller.loadPersonal());
  }

  void _changed() {
    if (mounted) {
      profileIdentityChanged();
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    disposeProfile();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Future<void> _open(PersonalPostItem item) async {
    if (!_authority.current) return;
    if (item.post != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(
            controller: widget.controller,
            loadImages: widget.loadImages,
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

  @override
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

  @override
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

  @override
  void _chooseChannel() {
    if (widget.onChooseChannel != null) {
      widget.onChooseChannel!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PostTheme.of(context).copyWith(scaffoldBackgroundColor: Colors.white),
    child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: !_authority.current
            ? _AccessClosed(onAuthenticate: widget.onAuthenticationRequired)
            : _profileContent(),
      ),
      bottomNavigationBar: widget.showNavigation ? widget.navigation : null,
    ),
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
                      if (!resultUnknown &&
                          item.local?.data['images'] is List &&
                          (item.local!.data['images'] as List).isNotEmpty &&
                          item.state == 'ACCEPTED')
                        _PostImageUploadStatus(
                          controller: widget.controller,
                          item: item,
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
    this.initialCommentId,
    this.initialCommentInput,
    this.initialCommentOriginal,
    this.loadImages,
    this.onAuthenticationRequired,
  });
  final PostController controller;
  final String postId;
  final String? channelName;
  final String? initialCommentId;
  final CommentRejectedInput? initialCommentInput;
  final Uint8List? initialCommentOriginal;
  final PostImagesLoader? loadImages;
  final VoidCallback? onAuthenticationRequired;
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final _PostAuthority _authority;
  final _bodyKey = GlobalKey();
  bool _viewRecorded = false, _viewScheduled = false;
  void _scheduleView() {
    if (_viewRecorded || _viewScheduled || !widget.controller.supportsFeed) {
      return;
    }
    _viewScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewScheduled = false;
      if (!mounted ||
          !_authority.current ||
          _post == null ||
          _deleted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final render = _bodyKey.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) return;
      final rect = render.localToGlobal(Offset.zero) & render.size;
      final viewport = Offset.zero & MediaQuery.sizeOf(context);
      if (!rect.overlaps(viewport)) return;
      _viewRecorded = true;
      unawaited(widget.controller.registerVisiblePost(widget.postId));
    });
  }

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
      if (route?.isActive == true) {
        final navigator = Navigator.of(context);
        if (route!.isCurrent && navigator.canPop()) {
          navigator.pop();
        } else if (!route.isCurrent) {
          // A viewer may cover this detail. Remove this exact deleted route;
          // its child lease closes independently without popping another page.
          navigator.removeRoute(route);
        }
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
      unawaited(
        widget.controller.loadInteractions([widget.postId], single: true),
      );
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
          centerTitle: false,
          title: Text(
            '帖子',
            style: detailType(context, 20, weight: FontWeight.w500),
          ),
          leading: BackButton(onPressed: () => Navigator.maybePop(context)),
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
            : CommentScope.maybeOf(context) == null
            ? _detail(context, _post!)
            : CommentPostPane(
                key: ValueKey(
                  'comments:${widget.postId}:${_authority.version}',
                ),
                runtime: CommentScope.maybeOf(context)!,
                postId: widget.postId,
                postBody: _post!.body,
                initialCommentId: widget.initialCommentId,
                initialInput: widget.initialCommentInput,
                initialOriginal: widget.initialCommentOriginal,
                continuous: true,
                onBodyScroll: _scheduleView,
                body: _detail(context, _post!, embedded: true),
                onCountChanged: () {
                  if (_authority.current) {
                    unawaited(
                      widget.controller.loadInteractions([
                        widget.postId,
                      ], single: true),
                    );
                  }
                },
              ),
      ),
    ),
  );
  Widget _postMenu() =>
      !_authority.current ||
          _deleted ||
          !(_canDelete || GovernanceScope.maybeOf(context) != null)
      ? const SizedBox(width: 48)
      : PopupMenuButton<String>(
          tooltip: '帖子操作',
          enabled: !_deleting,
          icon: const DetailChromeIcon(
            DetailChrome.more,
            color: detailIconInk,
            size: 22,
          ),
          itemBuilder: (context) => [
            if (_post != null &&
                GovernanceScope.maybeOf(context)?.available == true)
              const PopupMenuItem(value: 'report', child: Text('举报帖子')),
            if (_canDelete)
              const PopupMenuItem(value: 'delete', child: Text('删除帖子')),
          ],
          onSelected: (action) {
            if (action == 'delete') {
              unawaited(_delete());
              return;
            }
            final governance = GovernanceScope.maybeOf(context);
            if (governance == null || _post == null || !_authority.current) {
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportScreen(
                  controller: governance,
                  postId: widget.postId,
                  title: _post!.title,
                ),
              ),
            );
          },
        );

  Widget _detail(
    BuildContext context,
    PostDetail post, {
    bool embedded = false,
  }) {
    _scheduleView();
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(8, 17, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => unawaited(DmScope.contact(context, widget.postId)),
                child: DetailAvatar(
                  name: post.author.displayName,
                  avatar: post.author.avatar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: post.author.inactiveMessage == null
                          ? () => unawaited(
                              DmScope.contact(context, widget.postId),
                            )
                          : () {
                              if (!_authority.current) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(post.author.inactiveMessage!),
                                ),
                              );
                            },
                      child: Text(
                        post.author.displayName,
                        style: detailType(context, 17, weight: FontWeight.w500),
                      ),
                    ),
                    if (widget.channelName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.channelName!,
                        style: detailType(context, 14, color: PostTheme.muted),
                      ),
                    ],
                  ],
                ),
              ),
              _postMenu(),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            post.title,
            style: detailType(context, 18, weight: FontWeight.w500),
          ),
          const SizedBox(height: 9),
          SelectableText(
            key: _bodyKey,
            post.body,
            style: detailType(context, 16, height: 1.5),
          ),
          if (widget.loadImages case final loader? when post.imageCount > 0)
            PostImagesSection(
              postId: post.postId,
              expectedCount: post.imageCount,
              loadImages: loader,
              authority: widget.controller,
              isCurrent: () =>
                  _authority.current &&
                  !_deleted &&
                  !widget.controller.isPostDeleted(widget.postId),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_postDate(post.publishedAt)} · ',
                    style: detailType(context, 13.5, color: PostTheme.muted),
                  ),
                  TextSpan(
                    text:
                        '${(widget.controller.supportsFeed ? widget.controller.postViewCount(widget.postId) : null) ?? '—'}',
                    style: detailType(context, 13.5, weight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' 次浏览',
                    style: detailType(context, 13.5, color: PostTheme.muted),
                  ),
                ],
              ),
            ),
          ),
          if (widget.controller.errorMessage != null)
            Text(widget.controller.errorMessage!),
          if (widget.controller.supportsInteractions) _interactionBar(),
        ],
      ),
    );
    if (embedded) return content;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _scheduleView();
        return false;
      },
      child: SingleChildScrollView(
        key: PageStorageKey(
          'detail:${_authority.account}:${_authority.version}:${widget.postId}',
        ),
        child: content,
      ),
    );
  }

  void _changeInteraction(PostInteractionAction action) {
    if (!mounted || !_authority.current) return;
    unawaited(widget.controller.changeInteraction(widget.postId, action));
  }

  Widget _interactionBar() {
    final c = widget.controller;
    final state = c.interaction(widget.postId);
    final favorites = state.value == null
        ? null
        : state.value!.favoriteCount +
              (state.favorited != state.value!.favoritedByMe
                  ? (state.favorited ? 1 : -1)
                  : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = [
              Builder(
                builder: (context) => DetailAction(
                  action: FeedAction.comment,
                  label: '评论',
                  count: '${state.value?.commentCount ?? '—'}',
                  onPressed: CommentScope.maybeOf(context) == null
                      ? null
                      : () => CommentPostPane.composeFrom(context),
                ),
              ),
              DetailAction(
                buttonKey: ValueKey('detail-like:${widget.postId}'),
                action: FeedAction.like,
                label: state.liked ? '取消点赞' : '点赞',
                selected: state.liked,
                count: '${state.likes ?? '—'}',
                onPressed: state.canChange
                    ? () => _changeInteraction(PostInteractionAction.like)
                    : null,
              ),
              DetailAction(
                buttonKey: ValueKey('detail-favorite:${widget.postId}'),
                action: FeedAction.bookmark,
                label: state.favorited ? '取消收藏' : '收藏',
                selected: state.favorited,
                count: '${favorites ?? '—'}',
                onPressed: state.canChange
                    ? () => _changeInteraction(PostInteractionAction.favorite)
                    : null,
              ),
              PostRepostButton(controller: c, postId: widget.postId),
              const DetailAction(action: FeedAction.share, label: '分享（暂未开放）'),
            ];
            if (MediaQuery.textScalerOf(context).scale(14) > 21 ||
                constraints.maxWidth < 300) {
              return Wrap(
                children: [
                  for (final action in actions)
                    SizedBox(width: constraints.maxWidth / 2, child: action),
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: actions,
            );
          },
        ),
        for (final notice in [
          (state.writeError, true),
          (state.readError, false),
        ])
          if (notice.$1 case final error?)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(error),
                TextButton(
                  onPressed: state.sending
                      ? null
                      : () {
                          if (!mounted || !_authority.current) return;
                          if (notice.$2) {
                            unawaited(c.retryInteraction(widget.postId));
                          } else {
                            unawaited(
                              c.loadInteractions([widget.postId], single: true),
                            );
                          }
                        },
                  child: Text(notice.$2 ? '重试' : '重新读取'),
                ),
              ],
            ),
      ],
    );
  }
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
      backgroundColor: PostTheme.cardTint,
      foregroundColor: PostTheme.muted,
      child: Icon(Icons.person_outline_rounded, size: radius * 1.2),
    ),
  );
}

class _PageState extends StatelessWidget {
  const _PageState({
    required this.title,
    this.announceTitle = false,
    this.message,
    this.action,
    this.onAction,
    this.actionIcon,
  });
  final String title;
  final bool announceTitle;
  final String? message, action;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: announceTitle,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
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
            if (actionIcon != null)
              IconButton(
                tooltip: action,
                onPressed: onAction,
                icon: Icon(actionIcon, size: 32, color: Colors.black),
              )
            else
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
