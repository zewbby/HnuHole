import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../navigation/app_navigation.dart';
import '../navigation/feed_chrome.dart';
import 'feed_refresh.dart';
export '../navigation/app_navigation.dart' show AppDestination;

enum FeedAction { comment, like, bookmark, share }

typedef FeedDestination = AppDestination;

@immutable
class FeedMediaView {
  const FeedMediaView({
    required this.id,
    required this.description,
    this.caption,
  });
  final String id, description;
  final String? caption;
}

/// Read-only presentation projection. Public author identity is not an account.
/// Mutation, count authority, media access and navigation belong to the owner.
@immutable
class FeedPostView {
  const FeedPostView({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.elapsed,
    required this.title,
    this.body = '',
    this.availableActions = const {FeedAction.comment},
    this.comments,
    this.likes,
    this.favorites,
    this.views,
    this.channelCode = 'buddy',
    this.liked = false,
    this.bookmarked = false,
    this.isOwnAuthor = false,
    this.media = const [],
    this.busyActions = const {},
  });
  final String id, authorId, authorName, elapsed, title;
  final String body;
  final Set<FeedAction> availableActions;
  final int? comments, likes, favorites;
  final int? views;
  final String channelCode;
  final bool liked, bookmarked, isOwnAuthor;
  final List<FeedMediaView> media;
  final Set<FeedAction> busyActions;

  FeedPostView copyWith({int? likes, bool? liked, bool? bookmarked}) =>
      FeedPostView(
        id: id,
        authorId: authorId,
        authorName: authorName,
        elapsed: elapsed,
        title: title,
        body: body,
        availableActions: availableActions,
        comments: comments,
        likes: likes ?? this.likes,
        favorites: favorites,
        views: views,
        channelCode: channelCode,
        liked: liked ?? this.liked,
        bookmarked: bookmarked ?? this.bookmarked,
        isOwnAuthor: isOwnAuthor,
        media: media,
        busyActions: busyActions,
      );
}

typedef FeedMediaBuilder = Widget Function(BuildContext, FeedMediaView);
typedef FeedAvatarBuilder = Widget? Function(BuildContext, FeedPostView);

TextStyle _text(
  BuildContext context,
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  fontSize: size,
  height: 1.3,
  fontWeight: weight,
  color: color ?? HhTelegramPalette.of(context).ink,
);

/// Confirmed single-column presentation, hosted by the authorized feed screen.
class HhXPostFeed extends StatelessWidget {
  const HhXPostFeed({
    super.key,
    required this.channelTitle,
    required this.posts,
    required this.mediaBuilder,
    this.content,
    this.showNavigation = true,
    this.onRefresh,
    this.onLatest,
    this.latestSelected = false,
    this.refreshEnabled = true,
    this.loading = false,
    this.avatarBuilder,
    this.accountAvatar,
    this.feedTitle,
    this.composeTooltip,
    this.blockedCount = 0,
    required this.onPost,
    required this.onAuthor,
    required this.onAction,
    required this.onMedia,
    required this.onMenu,
    required this.onBack,
    required this.onSearch,
    required this.onFilter,
    required this.onCompose,
    required this.onDestination,
  });
  final Widget? content;
  final bool showNavigation;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLatest;
  final bool latestSelected;
  final bool refreshEnabled, loading;
  final String channelTitle;
  final List<FeedPostView> posts;
  final FeedMediaBuilder mediaBuilder;
  final FeedAvatarBuilder? avatarBuilder;
  final Widget? accountAvatar;
  final String? feedTitle;
  final String? composeTooltip;
  final int blockedCount;
  final ValueChanged<FeedPostView> onPost, onMenu;
  final ValueChanged<String> onAuthor;
  final void Function(FeedPostView, FeedAction) onAction;
  final void Function(FeedPostView, int) onMedia;
  final VoidCallback onBack, onSearch, onFilter, onCompose;
  final ValueChanged<FeedDestination> onDestination;

  @override
  Widget build(BuildContext context) => _FeedChromeHost(feed: this);

  Widget _build(BuildContext context, FeedChromeController chrome) {
    final p = HhTelegramPalette.of(context);
    Widget page(double pull, bool refreshing) => Column(
      children: [
        AnimatedBuilder(
          animation: chrome,
          builder: (context, _) => FeedChromeMotion(
            visible: chrome.visible,
            builder: (context, progress, child) => ClipRect(
              child: Align(
                key: const ValueKey('feed-header-visibility'),
                alignment: Alignment.bottomCenter,
                heightFactor: progress,
                child: IgnorePointer(
                  ignoring: !chrome.visible,
                  child: ExcludeSemantics(
                    excluding: !chrome.visible,
                    child: child,
                  ),
                ),
              ),
            ),
            child: Column(
              key: const ValueKey('feed-header'),
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 72 + pull,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FeedSmileMark(pull: pull, loading: loading || refreshing),
                      Positioned(
                        left: 12,
                        child: IconButton(
                          key: const ValueKey('feed-account'),
                          tooltip: '我的',
                          onPressed: () =>
                              onDestination(FeedDestination.personal),
                          icon: SizedBox(
                            width: 36,
                            height: 36,
                            child: ClipOval(
                              child:
                                  accountAvatar ??
                                  ColoredBox(
                                    color: p.action,
                                    child: const Icon(
                                      Icons.person_outline_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        child: IconButton(
                          key: const ValueKey('feed-search'),
                          tooltip: '搜索当前通道',
                          onPressed: onSearch,
                          icon: Icon(
                            Icons.search_rounded,
                            size: 28,
                            color: p.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final large =
                        MediaQuery.textScalerOf(context).scale(17) > 22;
                    final channel = DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: latestSelected
                                ? Colors.transparent
                                : p.accent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: TextButton(
                        key: const ValueKey('feed-channel-picker'),
                        onPressed: onBack,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                feedTitle ?? channelTitle,
                                style: _text(
                                  context,
                                  17,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: p.secondary,
                              size: 21,
                            ),
                          ],
                        ),
                      ),
                    );
                    final filter = TextButton(
                      key: const ValueKey('feed-block-filter'),
                      onPressed: onFilter,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '筛选',
                            style: _text(
                              context,
                              16,
                              color: blockedCount == 0 ? p.secondary : p.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (blockedCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: p.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$blockedCount',
                                style: _text(
                                  context,
                                  10,
                                  color: p.onAccent,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            )
                          else
                            Icon(
                              Icons.add_rounded,
                              size: 21,
                              color: p.secondary,
                            ),
                        ],
                      ),
                    );
                    final latest = Semantics(
                      selected: latestSelected,
                      child: DecoratedBox(
                        key: const ValueKey('feed-latest-indicator'),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: latestSelected
                                  ? p.accent
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: TextButton(
                          key: const ValueKey('feed-latest'),
                          onPressed: onLatest,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: Text(
                            '最新',
                            style: _text(
                              context,
                              17,
                              color: latestSelected ? p.ink : p.secondary,
                              weight: latestSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                    if (large) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: channel),
                              filter,
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: latest,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 4, child: channel),
                        Expanded(flex: 4, child: Center(child: latest)),
                        Expanded(flex: 2, child: filter),
                      ],
                    );
                  },
                ),
                Divider(height: 1, thickness: .5, color: p.line),
              ],
            ),
          ),
        ),
        Expanded(
          child:
              content ??
              (posts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '暂无可显示的帖子',
                              style: _text(
                                context,
                                17,
                                weight: FontWeight.w600,
                              ),
                            ),
                            if (blockedCount > 0)
                              TextButton(
                                onPressed: onFilter,
                                child: const Text('调整屏蔽设置'),
                              ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('x-feed'),
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: posts.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, thickness: .5, color: p.line),
                      itemBuilder: (context, index) => HhXPostItem(
                        key: ValueKey('post:${posts[index].id}'),
                        post: posts[index],
                        mediaBuilder: mediaBuilder,
                        avatarBuilder: avatarBuilder,
                        onPost: () => onPost(posts[index]),
                        onAuthor: () => onAuthor(posts[index].authorId),
                        onMenu: () => onMenu(posts[index]),
                        onAction: (action) => onAction(posts[index], action),
                        onMedia: (media) => onMedia(posts[index], media),
                      ),
                    )),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: p.surface,
      extendBody: true,
      body: Builder(
        builder: (bodyContext) => MediaQuery(
          data: MediaQuery.of(bodyContext).copyWith(
            padding: MediaQuery.paddingOf(bodyContext)
                .copyWith(bottom: MediaQuery.paddingOf(context).bottom),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                bottom: false,
                child: onRefresh == null
                    ? page(0, false)
                    : FeedRefresh(
                        chrome: chrome,
                        enabled: refreshEnabled,
                        onRefresh: onRefresh!,
                        builder: (context, pull, refreshing) =>
                            page(pull, refreshing),
                      ),
              ),
              Positioned(
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: AnimatedBuilder(
                  animation: chrome,
                  builder: (context, _) => FeedChromeMotion(
                    visible: chrome.visible,
                    builder: (context, progress, _) => IgnorePointer(
                      ignoring: chrome.visible,
                      child: Opacity(
                        opacity: 1 - progress,
                        child: Transform.translate(
                          offset: Offset(0, progress * 64),
                          child: chrome.visible
                              ? const SizedBox(width: 60, height: 56)
                              : FeedComposeButton(
                                  onPressed: onCompose,
                                  tooltip: composeTooltip ?? '发布到$channelTitle',
                                  floating: true,
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
      ),
      bottomNavigationBar: showNavigation
          ? FeedNavigation(
              controller: chrome,
              selected: AppDestination.home,
              onSelected: onDestination,
              collapseSpace: true,
            )
          : null,
    );
  }
}

class _FeedChromeHost extends StatefulWidget {
  const _FeedChromeHost({required this.feed});
  final HhXPostFeed feed;

  @override
  State<_FeedChromeHost> createState() => _FeedChromeHostState();
}

class _FeedChromeHostState extends State<_FeedChromeHost> {
  final _local = FeedChromeController();
  late FeedChromeController _chrome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = FeedChromeScope.maybeOf(context) ?? _local;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = _chrome;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || chrome != _chrome) return;
      chrome.bind(
        this,
        widget.feed.onCompose,
        widget.feed.composeTooltip ?? '发布到${widget.feed.channelTitle}',
      );
    });
    return widget.feed._build(context, chrome);
  }

  @override
  void dispose() {
    _chrome.unbind(this);
    _local.dispose();
    super.dispose();
  }
}

class HhXPostItem extends StatelessWidget {
  const HhXPostItem({
    super.key,
    required this.post,
    required this.mediaBuilder,
    this.mediaSection,
    this.repostAction,
    this.avatarBuilder,
    required this.onPost,
    required this.onAuthor,
    required this.onMenu,
    required this.onAction,
    required this.onMedia,
  });
  final Widget? mediaSection;
  final Widget? repostAction;
  final FeedPostView post;
  final FeedMediaBuilder mediaBuilder;
  final FeedAvatarBuilder? avatarBuilder;
  final VoidCallback onPost, onAuthor, onMenu;
  final ValueChanged<FeedAction> onAction;
  final ValueChanged<int> onMedia;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return Material(
      color: p.surface,
      child: InkWell(
        onTap: onPost,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Semantics(
                      label: post.authorName,
                      button: !post.isOwnAuthor,
                      excludeSemantics: true,
                      onTap: post.isOwnAuthor ? null : onAuthor,
                      child: InkWell(
                        onTap: post.isOwnAuthor ? () {} : onAuthor,
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child:
                                  avatarBuilder?.call(context, post) ??
                                  Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF5CAFFA),
                                          Color(0xFF408ACF),
                                        ],
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      post.authorName.isEmpty
                                          ? '?'
                                          : post.authorName.characters.first,
                                      textScaler: TextScaler.noScaling,
                                      style: _text(
                                        context,
                                        18,
                                        color: Colors.white,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 40),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              InkWell(
                                onTap: post.isOwnAuthor ? () {} : onAuthor,
                                child: Text(
                                  post.authorName,
                                  style: _text(
                                    context,
                                    17,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (post.elapsed.isNotEmpty)
                                Text(
                                  '· ${post.elapsed}',
                                  style: _text(context, 14, color: p.secondary),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Text(post.title, style: _text(context, 17)),
                        ),
                        if (post.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            post.body,
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: _text(context, 17),
                          ),
                        ],
                        if (mediaSection != null) mediaSection!,
                        if (post.media.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: _media(context),
                          ),
                        ],
                        SizedBox(height: post.media.isEmpty ? 14 : 0),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wideText =
                                MediaQuery.textScalerOf(context).scale(12) >
                                    16 ||
                                constraints.maxWidth < 260;
                            final actions = [
                              _action(
                                context,
                                FeedAction.comment,
                                post.comments == null
                                    ? '—'
                                    : _count(post.comments!),
                                '评论',
                                false,
                              ),
                              _action(
                                context,
                                FeedAction.like,
                                post.likes == null ? '—' : _count(post.likes!),
                                post.liked ? '取消点赞' : '点赞',
                                post.liked,
                              ),
                              _action(
                                context,
                                FeedAction.bookmark,
                                null,
                                '${post.bookmarked ? '取消收藏' : '收藏'}${post.favorites == null ? '' : '，收藏数${post.favorites}'}',
                                post.bookmarked,
                              ),
                              _action(
                                context,
                                FeedAction.share,
                                null,
                                '分享',
                                false,
                              ),
                            ];
                            if (wideText) {
                              return Wrap(
                                children: [
                                  for (final action in [
                                    actions.first,
                                    if (repostAction != null) repostAction!,
                                    ...actions.skip(1),
                                  ])
                                    SizedBox(
                                      width: constraints.maxWidth / 2,
                                      child: action,
                                    ),
                                  SizedBox(
                                    width: constraints.maxWidth,
                                    child: _views(context),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                for (final action in [
                                  actions[0],
                                  if (repostAction != null) repostAction!,
                                  actions[1],
                                  _views(context),
                                  actions[2],
                                  actions[3],
                                ])
                                  Expanded(child: action),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 4,
              child: IconButton(
                key: ValueKey('menu:${post.id}'),
                tooltip: '帖子更多操作',
                onPressed: onMenu,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: p.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _media(BuildContext context) {
    final columns = post.media.length == 1 ? 1 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: post.media.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) => Semantics(
              label: post.media[index].description,
              button: true,
              child: InkWell(
                key: ValueKey('media:${post.id}:$index'),
                onTap: () => onMedia(index),
                child: mediaBuilder(context, post.media[index]),
              ),
            ),
          ),
        ),
        if (post.media.length == 1 && post.media.first.caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              post.media.first.caption!,
              style: _text(
                context,
                13.5,
                color: HhTelegramPalette.of(context).secondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _action(
    BuildContext context,
    FeedAction action,
    String? count,
    String label,
    bool selected,
  ) {
    final p = HhTelegramPalette.of(context);
    final color = selected
        ? action == FeedAction.like
              ? p.error
              : p.accent
        : p.secondary;
    final busy = post.busyActions.contains(action);
    final enabled = !busy && post.availableActions.contains(action);
    final stacked = MediaQuery.textScalerOf(context).scale(12) > 16;
    return Semantics(
      label: '$label${count == null ? '' : '，$count'}${busy ? '，处理中' : ''}',
      button: true,
      enabled: enabled,
      selected: selected,
      excludeSemantics: true,
      onTap: enabled ? () => onAction(action) : null,
      child: Tooltip(
        message: label,
        // Keep this recognizer even while enabled. If the button becomes busy
        // between pointer-down and pointer-up, its parent still absorbs the
        // gesture instead of letting the whole post's InkWell open the detail.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () {},
          child: TextButton(
            key: ValueKey('${action.name}:${post.id}'),
            onPressed: enabled ? () => onAction(action) : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final glyph = CustomPaint(
                  key: ValueKey('action-glyph:${action.name}:${post.id}'),
                  size: const Size(20, 20),
                  painter: _FeedActionGlyph(action, color, selected),
                );
                if (stacked) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      glyph,
                      if (count != null)
                        Text(count, style: _text(context, 12, color: color)),
                    ],
                  );
                }
                return SizedBox(
                  width: box.maxWidth,
                  height: 48,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      glyph,
                      if (count != null)
                        Positioned(
                          left: box.maxWidth / 2 + 13,
                          top: 16,
                          child: _actionCount(
                            context,
                            count,
                            color,
                            box.maxWidth,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _views(BuildContext context) {
    final color = HhTelegramPalette.of(context).secondary;
    final count = post.views == null ? '—' : _count(post.views!);
    return Semantics(
      key: ValueKey('views:${post.id}'),
      label: post.views == null ? '浏览量暂不可用' : '浏览量，${post.views}',
      excludeSemantics: true,
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CustomPaint(
                key: ValueKey('views-glyph:${post.id}'),
                size: const Size(20, 20),
                painter: _ViewsGlyph(color),
              ),
              Positioned(
                left: box.maxWidth / 2 + 13,
                top: 16,
                child: _actionCount(context, count, color, box.maxWidth),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCount(
    BuildContext context,
    String value,
    Color color,
    double cellWidth,
  ) => SizedBox(
    width: cellWidth > 24 ? cellWidth - 24 : 0,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, style: _text(context, 12, color: color)),
    ),
  );

  String _count(int value) => value < 1000
      ? '$value'
      : value < 1000000
      ? '${(value / 1000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}K'
      : '${(value / 1000000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}M';
}

class _ViewsGlyph extends CustomPainter {
  const _ViewsGlyph(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final bar in [(3.0, 9.0), (7.0, 4.0), (11.0, 7.0), (15.0, 1.5)]) {
      canvas.drawLine(
        Offset(bar.$1, bar.$2),
        Offset(bar.$1, size.height - 1.5),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ViewsGlyph oldDelegate) =>
      oldDelegate.color != color;
}

/// One stroke system for the compact feed actions; hit boxes remain 48dp.
class _FeedActionGlyph extends CustomPainter {
  const _FeedActionGlyph(this.action, this.color, this.selected);
  final FeedAction action;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (action) {
      case FeedAction.comment:
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..cubicTo(6.2, 3, 2.5, 6.5, 2.5, 11)
            ..cubicTo(2.5, 14.1, 4.2, 16.4, 7.1, 17.8)
            ..lineTo(7.1, 21)
            ..lineTo(11.2, 18.9)
            ..cubicTo(17.1, 19.2, 21.5, 15.9, 21.5, 11)
            ..cubicTo(21.5, 6.5, 17.8, 3, 12, 3)
            ..close(),
          pen,
        );
      case FeedAction.like:
        final heart = Path()
          ..moveTo(12, 21)
          ..cubicTo(9.8, 19.1, 2, 13.4, 2, 7.8)
          ..cubicTo(2, 2.4, 8.5, 1.3, 12, 6)
          ..cubicTo(15.5, 1.3, 22, 2.4, 22, 7.8)
          ..cubicTo(22, 13.4, 14.2, 19.1, 12, 21)
          ..close();
        if (selected) canvas.drawPath(heart, Paint()..color = color);
        canvas.drawPath(heart, pen);
      case FeedAction.bookmark:
        final bookmark = Path()
          ..moveTo(6, 3)
          ..lineTo(18, 3)
          ..lineTo(18, 21)
          ..lineTo(12, 17)
          ..lineTo(6, 21)
          ..close();
        if (selected) canvas.drawPath(bookmark, Paint()..color = color);
        canvas.drawPath(bookmark, pen);
      case FeedAction.share:
        canvas.drawLine(const Offset(7.1, 10.8), const Offset(16.8, 5.6), pen);
        canvas.drawLine(const Offset(7.1, 13.2), const Offset(16.8, 18.4), pen);
        for (final center in [
          const Offset(5, 12),
          const Offset(19, 4.5),
          const Offset(19, 19.5),
        ]) {
          canvas.drawCircle(center, 2.6, pen);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FeedActionGlyph oldDelegate) =>
      oldDelegate.action != action ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected;
}
