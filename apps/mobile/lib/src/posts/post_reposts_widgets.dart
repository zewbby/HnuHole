import 'dart:async';

import 'package:flutter/material.dart';

import 'post_controller.dart';
import 'post_reposts_api.dart';
import 'post_images.dart';

/// Shares PostController with feed/detail/personal. Captures the route's authority.
class PostRepostButton extends StatefulWidget {
  const PostRepostButton({
    super.key,
    required this.controller,
    required this.postId,
  });
  final PostController controller;
  final String postId;
  @override
  State<PostRepostButton> createState() => _PostRepostButtonState();
}

class _PostRepostButtonState extends State<PostRepostButton> {
  late final int epoch = widget.controller.authorityVersion;
  late final PostController routeController = widget.controller;
  bool opening = false;
  PostController get c => widget.controller;
  bool get current =>
      mounted &&
      identical(c, routeController) &&
      c.available &&
      epoch == c.authorityVersion;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (current) {
        unawaited(c.loadRepostState(widget.postId, authorityVersion: epoch));
      }
    });
  }

  @override
  void didUpdateWidget(covariant PostRepostButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      scheduleMicrotask(() {
        if (current) {
          unawaited(c.loadRepostState(widget.postId, authorityVersion: epoch));
        }
      });
    }
  }

  Future<void> open() async {
    if (!current || opening) return;
    setState(() => opening = true);
    try {
      final identities = await c.repostIdentities(authorityVersion: epoch);
      if (!mounted || !current) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AnimatedBuilder(
          animation: c,
          builder: (_, _) {
            if (!current) return const AlertDialog(content: Text('请重新登录'));
            final state = c.repostState(widget.postId);
            return AlertDialog(
              title: const Text('选择转帖身份'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (identities.isEmpty) const Text('请先在设置中创建身份。'),
                  for (final identity in identities)
                    ListTile(
                      title: Text(identity.nickname),
                      subtitle: Text(
                        state.value?.contains(identity.id) == true
                            ? '已转帖，点击取消'
                            : '以此身份转帖',
                      ),
                      trailing: state.value?.contains(identity.id) == true
                          ? const Icon(Icons.check)
                          : null,
                      onTap: state.unresolved
                          ? null
                          : () async {
                              if (!current) return;
                              await c.setRepost(
                                widget.postId,
                                identity.id,
                                !(state.value?.contains(identity.id) ?? false),
                                authorityVersion: epoch,
                              );
                            },
                    ),
                  if (state.sending)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('正在保存…'),
                    ),
                  if (state.error != null) Text(state.error!),
                  if (state.error != null)
                    TextButton(
                      onPressed: state.sending
                          ? null
                          : () => c.retryRepost(
                              widget.postId,
                              authorityVersion: epoch,
                            ),
                      child: Text(state.unresolved ? '重试核对' : '重新读取'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      );
    } catch (_) {
      if (mounted && current) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('身份读取失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, _) {
      if (!current || !c.supportsReposts) return const SizedBox.shrink();
      final state = c.repostState(widget.postId);
      final label = state.unresolved
          ? '转帖待确认'
          : state.reposted
          ? '已转帖'
          : '转帖';
      return TextButton.icon(
        key: ValueKey('repost:${widget.postId}'),
        onPressed: current && !opening ? open : null,
        icon: Icon(
          Icons.repeat,
          size: 18,
          color: state.reposted ? Theme.of(context).colorScheme.primary : null,
        ),
        label: Text(label),
      );
    },
  );
}

/// Optional full tab body. A sliver-based personal page can consume repostItems
/// directly instead. onOpen must navigate to the original postId.
class PersonalRepostsList extends StatefulWidget {
  const PersonalRepostsList({
    super.key,
    required this.controller,
    required this.onOpen,
    this.loadImages,
  });
  final PostController controller;
  final ValueChanged<RepostedPost> onOpen;
  final PostImagesLoader? loadImages;
  @override
  State<PersonalRepostsList> createState() => _PersonalRepostsListState();
}

class _PersonalRepostsListState extends State<PersonalRepostsList> {
  late final int epoch = widget.controller.authorityVersion;
  Map<String, String> identityNames = {};
  String? identityError;
  PostController get c => widget.controller;
  bool get current => mounted && c.available && c.authorityVersion == epoch;
  Future<void> _refresh() async {
    if (!current) return;
    final names = _loadIdentityNames();
    await c.loadReposts(authorityVersion: epoch);
    await names;
  }

  Future<void> _loadIdentityNames() async {
    try {
      final identities = await c.repostIdentities(authorityVersion: epoch);
      if (current) {
        setState(() {
          identityNames = {
            for (final identity in identities) identity.id: identity.nickname,
          };
          identityError = null;
        });
      }
    } catch (_) {
      if (current) setState(() => identityError = '转帖身份读取失败，请重试。');
    }
  }

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (current) unawaited(_refresh());
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, _) {
      if (!current) return const Center(child: Text('请重新登录'));
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (identityError case final error?)
              ListTile(
                title: Text(error),
                trailing: TextButton(
                  onPressed: _loadIdentityNames,
                  child: const Text('重新读取身份'),
                ),
              ),
            if (c.repostListLoading) const LinearProgressIndicator(),
            for (final id in c.unresolvedRepostIds)
              ListTile(
                title: Text(c.repostState(id).sending ? '正在保存转帖…' : '转帖结果尚未确认'),
                trailing: TextButton(
                  onPressed: c.repostState(id).sending
                      ? null
                      : () => c.retryRepost(id, authorityVersion: epoch),
                  child: const Text('重试核对'),
                ),
              ),
            if (c.repostListError case final error?)
              ListTile(
                title: Text(error),
                trailing: TextButton(
                  onPressed: () => c.loadReposts(authorityVersion: epoch),
                  child: const Text('重试'),
                ),
              ),
            if (!c.repostListLoading &&
                c.unresolvedRepostIds.isEmpty &&
                c.repostListError == null &&
                c.repostItems.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Text('暂无转帖')),
            for (final item in c.repostItems)
              Column(
                key: ValueKey(item.key),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      identityNames.containsKey(item.identityId)
                          ? '以“${identityNames[item.identityId]}”转帖'
                          : '正在核对转帖身份',
                    ),
                  ),
                  ListTile(
                    title: Text(item.post?.title ?? '原帖已不可用'),
                    subtitle: Text(
                      item.post == null
                          ? '无法查看原帖内容'
                          : item.post!.author.displayName,
                    ),
                    onTap: item.post == null
                        ? null
                        : () {
                            if (current) widget.onOpen(item);
                          },
                  ),
                  if (item.post case final post?)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        post.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (item.post != null &&
                      item.post!.imageCount > 0 &&
                      widget.loadImages != null)
                    PostImagesSection(
                      postId: item.postId,
                      expectedCount: item.post!.imageCount,
                      loadImages: widget.loadImages!,
                      authority: c,
                      isCurrent: () => current && !c.isPostDeleted(item.postId),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('转帖于 ${item.repostedAt.toLocal()}'),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: ValueKey('cancel-repost:${item.key}'),
                      onPressed: c.repostState(item.postId).unresolved
                          ? null
                          : () => c.setRepost(
                              item.postId,
                              item.identityId,
                              false,
                              authorityVersion: epoch,
                            ),
                      child: const Text('取消此转帖'),
                    ),
                  ),
                  if (c.repostState(item.postId).error case final error?)
                    ListTile(
                      title: Text(error),
                      trailing: TextButton(
                        onPressed: c.repostState(item.postId).sending
                            ? null
                            : () => c.retryRepost(
                                item.postId,
                                authorityVersion: epoch,
                              ),
                        child: const Text('重试核对'),
                      ),
                    ),
                  const Divider(),
                ],
              ),
            if (c.repostCursor != null)
              TextButton(
                onPressed: c.repostListLoading
                    ? null
                    : () => c.loadReposts(authorityVersion: epoch, more: true),
                child: const Text('加载更多'),
              ),
          ],
        ),
      );
    },
  );
}
