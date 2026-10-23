import 'dart:async';

import 'package:flutter/material.dart';

import 'post_controller.dart';
import 'post_reposts_api.dart';
import 'post_images.dart';

/// Rounded two-arrow mark, shared by every post surface.
class PostRepostIcon extends StatelessWidget {
  const PostRepostIcon({super.key, this.size = 20});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _RepostPainter(IconTheme.of(context).color ?? Colors.black),
  );
}

class _RepostPainter extends CustomPainter {
  const _RepostPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(4, 15)
        ..lineTo(4, 8)
        ..quadraticBezierTo(4, 5, 7, 5)
        ..lineTo(18, 5)
        ..moveTo(15, 2)
        ..lineTo(18, 5)
        ..lineTo(15, 8),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(20, 9)
        ..lineTo(20, 16)
        ..quadraticBezierTo(20, 19, 17, 19)
        ..lineTo(6, 19)
        ..moveTo(9, 16)
        ..lineTo(6, 19)
        ..lineTo(9, 22),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RepostPainter oldDelegate) => color != oldDelegate.color;
}

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
              title: const Text('选择身份'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (identities.isEmpty) const Text('请先在设置中创建身份。'),
                  for (final identity in identities)
                    ListTile(
                      title: Text(identity.nickname),
                      trailing: state.value?.contains(identity.id) == true
                          ? const IconTheme(
                              data: IconThemeData(color: Color(0xFF229ED9)),
                              child: PostRepostIcon(),
                            )
                          : null,
                      onTap: state.unresolved
                          ? null
                          : () async {
                              if (!current) return;
                              final removing =
                                  state.value?.contains(identity.id) ?? false;
                              if (removing) {
                                final confirmed = await showDialog<bool>(
                                  context: dialogContext,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: Colors.white,
                                    surfaceTintColor: Colors.transparent,
                                    title: const Text('确认移除？'),
                                    content: Text(
                                      '仅移除“${identity.nickname}”保存的这条记录。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('确认'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true ||
                                    !current ||
                                    c.repostState(widget.postId).unresolved) {
                                  return;
                                }
                              }
                              await c.setRepost(
                                widget.postId,
                                identity.id,
                                !removing,
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
      return IconButton(
        key: ValueKey('repost:${widget.postId}'),
        tooltip: state.unresolved ? '重试核对' : '转帖',
        onPressed: current && !opening ? open : null,
        color: state.reposted ? const Color(0xFF229ED9) : null,
        icon: const PostRepostIcon(),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: ValueKey('cancel-repost:${item.key}'),
                      tooltip: '移除',
                      color: const Color(0xFF229ED9),
                      icon: const PostRepostIcon(),
                      onPressed: c.repostState(item.postId).unresolved
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: Colors.white,
                                  surfaceTintColor: Colors.transparent,
                                  title: const Text('确认移除？'),
                                  content: Text(
                                    '仅移除“${identityNames[item.identityId] ?? '此身份'}”保存的这条记录。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('确认'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true &&
                                  current &&
                                  !c.repostState(item.postId).unresolved) {
                                await c.setRepost(
                                  item.postId,
                                  item.identityId,
                                  false,
                                  authorityVersion: epoch,
                                );
                              }
                            },
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
