import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../identity/identity_switcher.dart';
import '../messaging/direct_message_models.dart';
import '../messaging/direct_message_composer.dart';
import '../posts/post_models.dart';
import '../posts/post_images.dart';
import 'governance_controller.dart';
import 'inbox_models.dart';
import 'notification_screens.dart';
import 'notification_thumbnail.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({
    super.key,
    required this.controller,
    this.onOpenPost,
    this.onOpenComment,
    this.onManageIdentities,
    this.loadImages,
  });
  final GovernanceController controller;
  final Future<void> Function(String)? onOpenPost;
  final Future<void> Function(String, String)? onOpenComment;
  final Future<void> Function()? onManageIdentities;
  final PostImagesLoader? loadImages;
  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  static const categories = ['all', 'reply', 'like', 'system'];
  static const labels = ['全部', '回复', '收到的赞', '系统通知'];
  final pages = PageController(), anchor = GlobalKey();
  final items = <String, List<InboxNotice>>{},
      next = <String, String?>{},
      errors = <String, String>{},
      loading = <String>{},
      requests = <String, int>{};
  int selected = 0, epoch = 0, totalUnread = 0;
  double tabDrag = 0;
  int tabDragStart = 0;
  final identityUnread = <String, int>{};
  bool onlyUnread = false,
      menuOpen = false,
      directoryLoading = false,
      directoryReady = false;
  String? directoryError;
  Object? window;
  String? viewIdentity;
  Route<dynamic>? menuRoute;
  GovernanceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    window = (c.accountId, c.authorityVersion);
    viewIdentity = c.selectedIdentityId;
    c.addListener(changed);
    unawaited(initialize());
  }

  void changed() {
    final current = (c.accountId, c.authorityVersion);
    if (current != window) {
      window = current;
      viewIdentity = c.selectedIdentityId;
      epoch++;
      items.clear();
      next.clear();
      errors.clear();
      loading.clear();
      requests.clear();
      totalUnread = 0;
      identityUnread.clear();
      directoryReady = false;
      directoryLoading = false;
      directoryError = null;
      menuOpen = false;
      dismissMenu();
      if (c.available) unawaited(initialize());
    } else if (viewIdentity != c.selectedIdentityId) {
      viewIdentity = c.selectedIdentityId;
      epoch++;
      items.clear();
      next.clear();
      loading.clear();
      requests.clear();
      errors.clear();
      totalUnread = 0;
      if (c.available && viewIdentity != null) {
        unawaited(load(categories[selected]));
      }
    }
    if (mounted) setState(() {});
  }

  void dismissMenu() {
    final route = menuRoute;
    menuRoute = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  @override
  void dispose() {
    epoch++;
    dismissMenu();
    c.removeListener(changed);
    pages.dispose();
    super.dispose();
  }

  bool current(int ticket, Object? owner, String? identity) =>
      mounted &&
      ticket == epoch &&
      owner == (c.accountId, c.authorityVersion) &&
      c.available &&
      identity == c.selectedIdentityId;
  Future<void> initialize() async {
    if (!c.available || directoryLoading) return;
    final owner = window;
    setState(() {
      directoryLoading = true;
      directoryError = null;
    });
    try {
      final loaded = await c.loadIdentities();
      if (!mounted || owner != window || !c.available) return;
      if (!loaded) {
        setState(() => directoryError = '身份暂时无法读取，请重试');
        return;
      }
      directoryReady = true;
      if (c.selectedIdentityId == null && c.identities.isNotEmpty) {
        viewIdentity = c.identities.first.id;
        c.selectInboxIdentity(c.identities.first.id);
      }
      await load(categories[selected]);
    } finally {
      if (mounted && owner == window) setState(() => directoryLoading = false);
    }
  }

  Future<void> load(String category, {bool more = false}) async {
    if (!c.available ||
        !directoryReady ||
        loading.contains(category) ||
        more && next[category] == null) {
      return;
    }
    final ticket = epoch,
        owner = (c.accountId, c.authorityVersion),
        identity = c.selectedIdentityId,
        request = (requests[category] ?? 0) + 1;
    requests[category] = request;
    setState(() {
      loading.add(category);
      errors.remove(category);
    });
    try {
      final raw = await c.requestInbox(
        'GET',
        '/api/v1/notifications',
        query: {
          'category': category,
          'unreadOnly': '$onlyUnread',
          'limit': '30',
          if (identity != null) 'identityId': identity,
          if (more) 'cursor': next[category]!,
        },
      );
      if (!current(ticket, owner, identity) ||
          request != requests[category] ||
          raw == null) {
        return;
      }
      final response = PostJson.record(raw, {'items', 'nextCursor'});
      final rows = response['items'];
      if (rows is! List || rows.length > 30) {
        throw const FormatException('Invalid notification page');
      }
      final parsed = [for (final row in rows) InboxNotice.parse(row, identity)];
      final cursor = response['nextCursor'];
      if (cursor != null &&
          (cursor is! String || cursor.isEmpty || cursor.length > 2048)) {
        throw const FormatException('Invalid notification cursor');
      }
      final merged = <String, InboxNotice>{
        if (more)
          for (final n in items[category] ?? <InboxNotice>[]) n.id: n,
        for (final n in parsed) n.id: n,
      };
      items[category] = merged.values.toList();
      next[category] = cursor as String?;
      await counts(ticket, owner, identity);
    } on Object {
      if (current(ticket, owner, identity) && request == requests[category]) {
        errors[category] = '通知暂时无法读取，请重试';
      }
    } finally {
      if (current(ticket, owner, identity) && request == requests[category]) {
        loading.remove(category);
        setState(() {});
      }
    }
  }

  Future<void> counts(int ticket, Object? owner, String? identity) async {
    final raw = await c.requestInbox(
      'GET',
      '/api/v1/notifications/unread-counts',
      query: {if (identity != null) 'identityId': identity},
    );
    if (!current(ticket, owner, identity) || raw == null) return;
    final m = PostJson.record(raw, {
      'all',
      'reply',
      'like',
      'system',
      'identityUnread',
    });
    for (final category in categories) {
      PostJson.integer(m, category, 0, 9007199254740991);
    }
    final unread = m['identityUnread'];
    if (unread is! Map<String, dynamic> || unread.length > 3) {
      throw const FormatException('Invalid identity unread counts');
    }
    final parsed = <String, int>{};
    for (final entry in unread.entries) {
      if (!c.identities.any((i) => i.id == entry.key) ||
          entry.value is! int ||
          entry.value < 0) {
        throw const FormatException('Invalid identity unread');
      }
      parsed[entry.key] = entry.value as int;
    }
    totalUnread = m['all'] as int;
    identityUnread
      ..clear()
      ..addAll(parsed);
    c.updateInboxUnread(
      (m['system'] as int) > 0 || parsed.values.any((n) => n > 0),
    );
  }

  Future<void> switchIdentity() async {
    if (menuOpen || c.identities.isEmpty) return;
    final ticket = epoch, owner = window;
    setState(() => menuOpen = true);
    final result = await showHhIdentityMenu(
      context: context,
      anchorKey: anchor,
      identities: [
        for (final i in c.identities)
          IdentitySwitchItem(
            DmIdentity(id: i.id, name: i.nickname, avatar: i.avatar),
            unread: identityUnread[i.id] ?? 0,
          ),
      ],
      selectedId: c.selectedIdentityId ?? '',
      canAdd: widget.onManageIdentities != null,
      keyPrefix: 'notification',
      onRoute: (route) {
        menuRoute = route;
        if (!mounted || ticket != epoch) dismissMenu();
      },
    );
    menuRoute = null;
    if (!mounted) return;
    setState(() => menuOpen = false);
    if (ticket != epoch || owner != window || result == null) return;
    if (result == '@add') {
      await widget.onManageIdentities?.call();
      if (mounted && c.available) await initialize();
      return;
    }
    if (result == c.selectedIdentityId) return;
    epoch++;
    items.clear();
    next.clear();
    errors.clear();
    loading.clear();
    requests.clear();
    viewIdentity = result;
    c.selectInboxIdentity(result);
    setState(() => totalUnread = 0);
    await load(categories[selected]);
  }

  Future<void> open(InboxNotice notice) async {
    final ticket = epoch, owner = window, identity = c.selectedIdentityId;
    try {
      final read = await c.requestInbox(
        'POST',
        '/api/v1/notifications/${notice.id}/read',
        query: {if (identity != null) 'identityId': identity},
        body: {'seenVersion': notice.version},
      );
      if (!current(ticket, owner, identity) || read == null) return;
      final m = PostJson.record(read, {'id', 'readVersion'});
      if (m['id'] != notice.id || m['readVersion'] != notice.version) {
        throw const FormatException('Invalid read acknowledgement');
      }
      if (!mounted) return;
      if (notice.system case final system?) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SystemNoticeDetailScreen(
              controller: c,
              noticeId: system.id,
              targetIdentityId: system.identityId,
              onOpenPost: widget.onOpenPost,
              onOpenComment: widget.onOpenComment,
            ),
          ),
        );
      } else if (notice.postId case final post?) {
        if (notice.commentId case final comment?) {
          await widget.onOpenComment?.call(post, comment);
        } else {
          await widget.onOpenPost?.call(post);
        }
      }
      if (current(ticket, owner, c.selectedIdentityId)) {
        items.clear();
        next.clear();
        loading.clear();
        requests.clear();
        await load(categories[selected]);
      }
    } on Object {
      if (mounted && current(ticket, owner, identity)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开，请重试')));
      }
    }
  }

  void changePage(int index) {
    if (selected == index) return;
    setState(() => selected = index);
    if (!items.containsKey(categories[index])) {
      unawaited(load(categories[index]));
    }
  }

  void goPage(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      pages.jumpToPage(index);
    } else {
      pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget tabStrip(HhTelegramPalette p) => GestureDetector(
    key: const ValueKey('notification-tabs'),
    onHorizontalDragStart: (_) {
      tabDrag = 0;
      tabDragStart = selected;
    },
    onHorizontalDragUpdate: (d) {
      tabDrag += d.delta.dx;
      final width = pages.position.viewportDimension;
      pages.position.jumpTo(
        (tabDragStart - tabDrag / width).clamp(0, categories.length - 1) *
            width,
      );
    },
    onHorizontalDragEnd: (d) {
      final velocity = d.primaryVelocity ?? 0;
      final move =
          tabDrag.abs() > pages.position.viewportDimension * .17 ||
          velocity.abs() > 400;
      final direction = velocity.abs() > 400 ? velocity : tabDrag;
      final delta = move ? (direction < 0 ? 1 : -1) : 0;
      goPage((tabDragStart + delta).clamp(0, categories.length - 1));
    },
    onHorizontalDragCancel: () => goPage(tabDragStart),
    child: SizedBox(
      height: 52,
      child: AnimatedBuilder(
        animation: pages,
        builder: (context, _) {
          final position = pages.hasClients
              ? (pages.page ?? selected.toDouble())
              : selected.toDouble();
          return Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < categories.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: selected == i,
                        label: labels[i],
                        child: InkWell(
                          key: ValueKey('notification-tab:${categories[i]}'),
                          onTap: () => goPage(i),
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Transform.scale(
                                    scale:
                                        .94 +
                                        .14 *
                                            (1 - (position - i).abs()).clamp(
                                              0,
                                              1,
                                            ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          labels[i],
                                          style: TextStyle(
                                            fontSize: 14,

                                            fontWeight: FontWeight.w500,
                                            color: Color.lerp(
                                              p.secondary,
                                              p.accent,
                                              (1 - (position - i).abs()).clamp(
                                                0,
                                                1,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (i == 0 && totalUnread > 0) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            totalUnread > 99
                                                ? '99+'
                                                : '$totalUnread',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: p.accent,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(height: .5, color: p.line),
              ),
              LayoutBuilder(
                builder: (context, box) => Align(
                  alignment: Alignment.bottomLeft,
                  child: Transform.translate(
                    offset: Offset(
                      box.maxWidth / categories.length * position,
                      0,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 13),
                      width: box.maxWidth / categories.length - 26,
                      height: 3,
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  Widget panel(String category, HhTelegramPalette p) {
    final rows = items[category] ?? <InboxNotice>[];
    return RefreshIndicator(
      onRefresh: () => directoryReady ? load(category) : initialize(),
      child: ListView(
        key: PageStorageKey((
          'notifications',
          c.accountId,
          c.authorityVersion,
          c.selectedIdentityId,
          category,
          onlyUnread,
        )),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category == 'all'
                        ? '通知记录'
                        : labels[categories.indexOf(category)],
                    style: TextStyle(fontSize: 13, color: p.secondary),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    epoch++;
                    loading.clear();
                    requests.clear();
                    items.clear();
                    next.clear();
                    setState(() => onlyUnread = !onlyUnread);
                    unawaited(load(category));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: onlyUnread,
                          onChanged: (_) {
                            epoch++;
                            loading.clear();
                            requests.clear();
                            items.clear();
                            next.clear();
                            setState(() => onlyUnread = !onlyUnread);
                            unawaited(load(category));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '仅看未读',
                        style: TextStyle(fontSize: 11, color: p.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (directoryError case final error?)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(error),
                  TextButton(onPressed: initialize, child: const Text('重试')),
                ],
              ),
            ),
          if (errors[category] case final error?)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(error),
                  TextButton(
                    onPressed: () => load(category),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (rows.isEmpty &&
              !loading.contains(category) &&
              !directoryLoading &&
              directoryError == null &&
              !errors.containsKey(category))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 90, horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.notifications_none, size: 36, color: p.accent),
                  const SizedBox(height: 20),
                  Text(
                    onlyUnread ? '未读消息，都看完了' : '暂时没有新通知',
                    style: TextStyle(color: p.secondary),
                  ),
                ],
              ),
            ),
          for (final notice in rows) notificationRow(notice, p),
          if (loading.contains(category) || directoryLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (next[category] != null)
            TextButton(
              onPressed: () => load(category, more: true),
              child: const Text('加载更多'),
            ),
        ],
      ),
    );
  }

  String time(DateTime value) {
    final now = DateTime.now(), difference = now.difference(value);
    if (difference.isNegative) return '刚刚';
    if (difference.inMinutes < 1) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
    if (difference.inHours < 24) return '${difference.inHours} 小时前';
    return '${value.toLocal().month} 月 ${value.toLocal().day} 日';
  }

  Widget notificationRow(InboxNotice n, HhTelegramPalette p) => InkWell(
    onTap: () => open(n),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n.actor case final actor?)
            HhDmAvatar(identity: actor, size: 44)
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: p.selection,
                shape: BoxShape.circle,
              ),
              child: Icon(
                n.kind == 'like'
                    ? Icons.favorite_outline
                    : Icons.notifications_none,
                color: p.accent,
                size: 24,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 15),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.actor?.name ?? (n.kind == 'like' ? '收到的赞' : '社区通知'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          time(n.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.secondary),
                        ),
                      ),
                      if (n.unread) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: p.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    n.kind == 'like' && n.newLikes > 0
                        ? '${n.title} · 新增 ${n.newLikes} 个'
                        : n.title,
                    style: TextStyle(fontSize: 12, color: p.secondary),
                  ),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      n.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.65,
                        color: p.ink,
                      ),
                    ),
                  ],
                  if (n.sourceTitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: p.background,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        n.sourceTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: p.secondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (n.available &&
              n.hasPostImage &&
              n.postId != null &&
              widget.loadImages != null) ...[
            const SizedBox(width: 12),
            NotificationThumbnail(
              key: ValueKey((n.id, c.accountId, c.authorityVersion)),
              postId: n.postId!,
              load: widget.loadImages!,
            ),
          ],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context),
        identity = c.identities
            .where((i) => i.id == c.selectedIdentityId)
            .firstOrNull;
    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: p.header,
              padding: const EdgeInsets.fromLTRB(24, 8, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '通知',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: p.action,
                      ),
                    ),
                  ),
                  if (identity != null)
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: HhIdentitySwitcher(
                          controlKey: const ValueKey('notification-identity'),
                          identity: DmIdentity(
                            id: identity.id,
                            name: identity.nickname,
                            avatar: identity.avatar,
                          ),
                          anchor: anchor,
                          onTap: switchIdentity,
                          menuOpen: menuOpen,
                          otherUnread: identityUnread.entries.any(
                            (entry) =>
                                entry.key != identity.id && entry.value > 0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(color: p.header, child: tabStrip(p)),
            Expanded(
              child: PageView(
                controller: pages,
                onPageChanged: changePage,
                children: [
                  for (final category in categories) panel(category, p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
