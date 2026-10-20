import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../design_system/telegram_theme.dart';
import 'feed_api.dart';
import 'post_controller.dart';
import 'post_images.dart';
import 'post_screens.dart';
import 'x_feed.dart';
import 'x_feed_controls.dart';

/// Production owner: directory, preferences, pagination and protected media.
class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.controller,
    required this.channels,
    required this.composeChannel,
    required this.onManageIdentities,
    required this.onAuthenticationRequired,
    this.onOpenPersonal,
    this.onOpenMessages,
    this.initialChannelId,
    this.loadImages,
  });
  final String? initialChannelId;
  final PostController controller;
  final List<Channel> channels;
  final Channel composeChannel;
  final Future<void> Function() onManageIdentities;
  final VoidCallback onAuthenticationRequired;
  final VoidCallback? onOpenPersonal, onOpenMessages;
  final PostImagesLoader? loadImages;
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final int _epoch;
  int _publication = 0;
  bool _published = false;
  bool _starting = true;
  Timer? _notice;
  final _scroll = ScrollController();
  PostController get c => widget.controller;
  bool get current => mounted && c.available && c.authorityVersion == _epoch;
  List<FeedChannelView> get channels => [
    for (final channel in widget.channels)
      FeedChannelView(channel.id, channel.name, switch (channel.code) {
        'vent' => Icons.chat_bubble_outline,
        'warning' => Icons.warning_amber,
        'recommendation' => Icons.thumb_up_outlined,
        'buddy' => Icons.people_outline,
        'emotion' => Icons.favorite_border,
        'mutual_help' => Icons.volunteer_activism_outlined,
        _ => Icons.memory_outlined,
      }),
  ];
  @override
  void initState() {
    super.initState();
    _epoch = c.authorityVersion;
    _publication = c.latestPublicationNotice?.sequence ?? 0;
    c.addListener(_changed);
    // Starting a new route must not synchronously notify still-mounted sibling
    // routes during Navigator's build. Hide any prior timeline until this read.
    scheduleMicrotask(() {
      if (!current) return;
      setState(() => _starting = false);
      unawaited(c.loadTimeline(channelId: widget.initialChannelId));
    });
  }

  void _changed() {
    if (!mounted) return;
    final notice = c.latestPublicationNotice;
    if (current && notice != null && notice.sequence > _publication) {
      _publication = notice.sequence;
      if (c.timelineChannelId == null ||
          notice.channelId == c.timelineChannelId) {
        _published = true;
        _notice?.cancel();
        _notice = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _published = false);
        });
        // Keep the current reading position; explicit refresh gets new posts.
        if (!_scroll.hasClients || _scroll.offset < 20) {
          unawaited(c.loadTimeline(channelId: c.timelineChannelId));
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _notice?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick(BuildContext context) => showFeedChannelPicker(
    context,
    channels: channels,
    authority: c,
    isCurrent: () => current,
    selected: c.timelineChannelId,
    onSelected: (id) {
      if (!current || c.preferencesSaving) return;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      unawaited(c.loadTimeline(channelId: id));
    },
  );
  Future<void> _filter(BuildContext context) => showFeedBlockFilter(
    context,
    channels: channels,
    authority: c,
    blocked: () => c.blockedChannelIds,
    saving: () => c.preferencesSaving || c.timelineLoading,
    ready: () => c.feedPreferencesReady,
    onRetry: () => c.loadTimeline(channelId: c.timelineChannelId),
    isCurrent: () => current,
    error: () => c.preferencesError,
    onChanged: (ids) {
      if (current) unawaited(c.saveBlockedChannels(ids));
    },
  );
  Future<void> _compose(BuildContext context) async {
    if (!current) return;
    var channel = widget.channels
        .where((p) => p.id == c.timelineChannelId)
        .firstOrNull;
    if (channel == null) {
      String? chosen;
      await showFeedChannelPicker(
        context,
        channels: channels,
        authority: c,
        isCurrent: () => current,
        selected: widget.composeChannel.id,
        includeRecommended: false,
        onSelected: (id) => chosen = id,
      );
      if (!mounted || !context.mounted || !current || chosen == null) return;
      channel = widget.channels.where((p) => p.id == chosen).firstOrNull;
    }
    if (channel == null || !context.mounted) return;
    if (c.timelineChannelId != channel.id) {
      await c.loadTimeline(channelId: channel.id);
    }
    if (!context.mounted || !current) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PostComposerScreen(
          controller: c,
          editor: c.newDraft(channel!.id),
          channelName: channel.name,
          onManageIdentities: widget.onManageIdentities,
          onAuthenticationRequired: widget.onAuthenticationRequired,
        ),
      ),
    );
  }

  void _open(BuildContext context, String id, String channelId) {
    if (!current) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          controller: c,
          postId: id,
          loadImages: widget.loadImages,
          channelName: widget.channels
              .where((p) => p.id == channelId)
              .firstOrNull
              ?.name,
          onAuthenticationRequired: widget.onAuthenticationRequired,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: HhTelegramTheme.create(
      Theme.of(context).brightness,
      fontFamily: 'Roboto',
    ),
    child: Builder(
      builder: (context) {
        if (!current) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: widget.onAuthenticationRequired,
                child: const Text('登录或核对会话'),
              ),
            ),
          );
        }
        final posts = _starting ? const <FeedPost>[] : c.timelineItems;
        final selectedChannel = widget.channels
            .where((channel) => channel.id == c.timelineChannelId)
            .firstOrNull;
        return HhXPostFeed(
          channelTitle: widget.composeChannel.name,
          feedTitle: selectedChannel?.name ?? '推荐',
          composeTooltip: selectedChannel == null
              ? '选择通道写帖子'
              : '发布到${selectedChannel.name}',
          blockedCount: c.blockedChannelIds.length,
          posts: const [],
          mediaBuilder: (_, _) => const SizedBox.shrink(),
          onPost: (_) {},
          onAuthor: (_) {},
          onAction: (_, _) {},
          onMedia: (_, _) {},
          onMenu: (_) {},
          onBack: () => _pick(context),
          onSearch: () =>
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('搜索功能待开放'))),
          onFilter: () => _filter(context),
          onCompose: () => _compose(context),
          onDestination: (destination) {
            switch (destination) {
              case FeedDestination.home:
                Navigator.of(context).pop();
              case FeedDestination.personal:
                widget.onOpenPersonal?.call();
              case FeedDestination.messages:
                widget.onOpenMessages?.call();
            }
          },
          content: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => c.loadTimeline(channelId: c.timelineChannelId),
                child: ListView(
                  controller: _scroll,
                  key: const ValueKey('production-feed'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (_starting || c.timelineLoading || c.preferencesSaving)
                      const LinearProgressIndicator(),
                    if (!_starting && c.timelineError != null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(c.timelineError!),
                            TextButton(
                              onPressed: () => c.loadTimeline(
                                channelId: c.timelineChannelId,
                              ),
                              child: const Text('重新加载'),
                            ),
                          ],
                        ),
                      ),
                    if (!_starting &&
                        !c.timelineLoading &&
                        !c.preferencesSaving &&
                        c.timelineError == null &&
                        posts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 80,
                          horizontal: 24,
                        ),
                        child: Column(
                          children: [
                            const Text('暂无可显示的帖子'),
                            if (c.blockedChannelIds.isNotEmpty)
                              TextButton(
                                onPressed: () => _filter(context),
                                child: const Text('调整屏蔽设置'),
                              ),
                          ],
                        ),
                      ),
                    for (final post in posts) ...[
                      HhXPostItem(
                        key: ValueKey('post:${post.postId}'),
                        post: FeedPostView(
                          id: post.postId,
                          authorId: '',
                          authorName: post.author.displayName,
                          elapsed:
                              '${post.publishedAt.toLocal().month}月${post.publishedAt.toLocal().day}日',
                          title: post.title,
                          body: post.body,
                          views: c.postViewCount(post.postId),
                          comments: c
                              .interaction(post.postId)
                              .value
                              ?.commentCount,
                          likes: c.interaction(post.postId).likes,
                          favorites: c
                              .interaction(post.postId)
                              .value
                              ?.favoriteCount,
                          liked: c.interaction(post.postId).liked,
                          bookmarked: c.interaction(post.postId).favorited,
                          availableActions: {
                            FeedAction.comment,
                            if (c.interaction(post.postId).canChange) ...{
                              FeedAction.like,
                              FeedAction.bookmark,
                            },
                          },
                          busyActions: {
                            if (c.interaction(post.postId).sending)
                              c.interaction(post.postId).pendingAction ==
                                      PostInteractionAction.like
                                  ? FeedAction.like
                                  : FeedAction.bookmark,
                          },
                        ),
                        mediaBuilder: (_, _) => const SizedBox.shrink(),
                        mediaSection:
                            post.imageCount > 0 && widget.loadImages != null
                            ? PostImagesSection(
                                key: ValueKey('feed-images:${post.postId}'),
                                postId: post.postId,
                                feedPreview: true,
                                expectedCount: post.imageCount,
                                loadImages: widget.loadImages!,
                                authority: c,
                                isCurrent: () =>
                                    current && !c.isPostDeleted(post.postId),
                              )
                            : null,
                        onPost: () =>
                            _open(context, post.postId, post.channelId),
                        onAuthor: () {},
                        onMenu: () =>
                            _open(context, post.postId, post.channelId),
                        onAction: (action) {
                          if (!current) return;
                          switch (action) {
                            case FeedAction.comment:
                              _open(context, post.postId, post.channelId);
                            case FeedAction.like:
                              unawaited(
                                c.changeInteraction(
                                  post.postId,
                                  PostInteractionAction.like,
                                ),
                              );
                            case FeedAction.bookmark:
                              unawaited(
                                c.changeInteraction(
                                  post.postId,
                                  PostInteractionAction.favorite,
                                ),
                              );
                            case FeedAction.share:
                              break;
                          }
                        },
                        onMedia: (_) {},
                      ),
                      for (final notice in [
                        (c.interaction(post.postId).writeError, true),
                        (c.interaction(post.postId).readError, false),
                      ])
                        if (notice.$1 case final error?)
                          Padding(
                            padding: const EdgeInsets.only(left: 64, right: 16),
                            child: Row(
                              children: [
                                Expanded(child: Text(error)),
                                TextButton(
                                  key: ValueKey(
                                    'interaction-${notice.$2 ? '' : 'read-'}retry:${post.postId}',
                                  ),
                                  onPressed: c.interaction(post.postId).sending
                                      ? null
                                      : () {
                                          if (!current) return;
                                          if (notice.$2) {
                                            unawaited(
                                              c.retryInteraction(post.postId),
                                            );
                                          } else {
                                            unawaited(
                                              c.loadInteractions([
                                                post.postId,
                                              ], single: true),
                                            );
                                          }
                                        },
                                  child: Text(notice.$2 ? '重试' : '重新读取'),
                                ),
                              ],
                            ),
                          ),
                      const Divider(height: 1, thickness: .5),
                    ],
                    if (c.timelineCursor != null && !c.timelineLoading)
                      TextButton(
                        onPressed: () => c.loadTimeline(
                          channelId: c.timelineChannelId,
                          more: true,
                        ),
                        child: const Text('加载更多'),
                      ),
                  ],
                ),
              ),
              if (_published)
                const Positioned(
                  top: 12,
                  left: 80,
                  right: 80,
                  child: Material(
                    color: Color(0xFF2678B6),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '发布成功！',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
