import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../identity/identity_api.dart';
import 'direct_message_composer.dart';
import 'direct_message_models.dart';

@immutable
class DmInboxEntry {
  const DmInboxEntry({
    required this.id,
    required this.selfIdentityId,
    required this.recipient,
    required this.preview,
    required this.time,
    this.unread = 0,
    this.privateNote,
    this.sourceTitle = '',
    this.localSearchText = '',
    this.pinned = false,
    this.hidden = false,
    this.outgoingState,
  });
  final String id, selfIdentityId, preview, time, sourceTitle, localSearchText;
  final DmIdentity recipient;
  final String? privateNote;
  final int unread;
  final bool pinned, hidden;
  final DmSendState? outgoingState;
}

@immutable
class DmInboxIdentity {
  const DmInboxIdentity(this.identity, {this.unread = 0});
  final DmIdentity identity;
  final int unread;
}

@immutable
class DmInboxTarget {
  const DmInboxTarget({
    required this.scopeKey,
    required this.identityId,
    required this.conversationId,
  });
  final String scopeKey, identityId, conversationId;
}

/// Read-only projection. Opening a row emits its exact target; this widget never
/// clears unread, reveals hidden conversations or changes delivery state.
class HhDmInboxScreen extends StatefulWidget {
  const HhDmInboxScreen({
    super.key,
    required this.scopeKey,
    required this.identity,
    required this.identities,
    required this.entries,
    required this.onOpen,
    required this.onIdentitySelected,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onSystemNotifications,
    this.systemUnread = 0,
    this.navigation,
    this.onManage,
    this.onSearchChanged,
    this.onAddIdentity,
  });

  /// Must include account/session generation AND the selected inbox identity.
  final String scopeKey;
  final DmIdentity identity;
  final List<DmInboxIdentity> identities;

  /// Canonical order is supplied by the owner, including the pinned partition.
  final List<DmInboxEntry> entries;
  final ValueChanged<DmInboxTarget> onOpen;
  final ValueChanged<DmInboxTarget>? onManage;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onAddIdentity;
  final ValueChanged<DmIdentity> onIdentitySelected;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry, onSystemNotifications;
  final int systemUnread;
  final Widget? navigation;

  @override
  State<HhDmInboxScreen> createState() => _HhDmInboxScreenState();
}

class _HhDmInboxScreenState extends State<HhDmInboxScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _offsets = <String, double>{};
  late List<String> _order;
  bool _pending = false;
  int _epoch = 0;
  final _identityAnchor = GlobalKey();
  bool _identityMenuOpen = false;
  Route<dynamic>? _identityMenuRoute;

  void _dismissIdentityMenu() {
    final route = _identityMenuRoute;
    if (route == null) return;
    _identityMenuRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  List<DmInboxEntry> get _owned => widget.entries
      .where((e) => e.selfIdentityId == widget.identity.id)
      .toList();
  @override
  void initState() {
    super.initState();
    _order = _owned.map((e) => e.id).toList();
  }

  @override
  void dispose() {
    _dismissIdentityMenu();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HhDmInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey ||
        oldWidget.identity.id != widget.identity.id) {
      _epoch++;
      _dismissIdentityMenu();
      _offsets[oldWidget.scopeKey] = _scroll.hasClients ? _scroll.offset : 0;
      _search.clear();
      FocusScope.of(context).unfocus();
      _pending = false;
      _order = _owned.map((e) => e.id).toList();
      final epoch = _epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _epoch && _scroll.hasClients) {
          _scroll.jumpTo(
            (_offsets[widget.scopeKey] ?? 0).clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    } else {
      final next = _owned.map((e) => e.id).toList();
      if (_scroll.hasClients && _scroll.offset > 40 && _search.text.isEmpty) {
        final previous = {
          for (final entry in oldWidget.entries) entry.id: entry,
        };
        final newContent = _owned.any((entry) {
          final old = previous[entry.id];
          return old == null ||
              entry.time != old.time ||
              entry.preview != old.preview ||
              entry.unread > old.unread;
        });
        _pending = _pending || newContent || next.join('|') != _order.join('|');
      } else {
        _order = next;
      }
    }
  }

  Future<void> _selectIdentity() async {
    if (_identityMenuOpen) return;
    FocusScope.of(context).unfocus();
    final epoch = _epoch;
    final anchor =
        _identityAnchor.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect =
        anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
    final p = HhTelegramPalette.of(context);
    setState(() => _identityMenuOpen = true);
    final chosen = await showMenu<String>(
      context: context,
      positionBuilder: (context, constraints) {
        final current = anchor.attached && overlay.attached
            ? anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size
            : rect;
        return RelativeRect.fromRect(
          Rect.fromLTWH(current.left, current.bottom + 6, current.width, 0),
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
              if (!mounted || epoch != _epoch) {
                _dismissIdentityMenu();
                return const SizedBox.shrink();
              }
              return Text(
                '切换身份',
                style: TextStyle(fontSize: 13, color: p.secondary),
              );
            },
          ),
        ),
        for (final item in widget.identities)
          PopupMenuItem<String>(
            key: ValueKey('inbox-identity:${item.identity.id}'),
            value: item.identity.id,
            height: 56,
            child: Row(
              children: [
                Badge(
                  isLabelVisible: item.unread > 0,
                  child: HhDmAvatar(identity: item.identity, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.identity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: p.ink),
                  ),
                ),
                if (item.identity.id == widget.identity.id)
                  Icon(Icons.check_rounded, color: p.accent, size: 20),
              ],
            ),
          ),
        for (
          var slot = widget.identities.length;
          slot < IdentityDirectory.maximumIdentities;
          slot++
        )
          PopupMenuItem<String>(
            key: ValueKey('inbox-add-identity:$slot'),
            value: '@add:$slot',
            enabled: widget.onAddIdentity != null,
            height: 56,
            child: Semantics(
              label: '添加身份',
              child: Center(
                child: Icon(Icons.add_rounded, color: p.accent, size: 26),
              ),
            ),
          ),
      ],
    );
    _identityMenuRoute = null;
    if (!mounted) return;
    setState(() => _identityMenuOpen = false);
    if (epoch != _epoch || chosen == null) return;
    if (chosen.startsWith('@add:')) {
      widget.onAddIdentity?.call();
    } else {
      final identity = widget.identities
          .where((i) => i.identity.id == chosen)
          .firstOrNull;
      if (identity != null) widget.onIdentitySelected(identity.identity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    final byId = {for (final entry in _owned) entry.id: entry};
    final entries = query.isEmpty
        ? [
            for (final id in _order)
              if (byId[id] case final entry? when !entry.hidden) entry,
          ]
        : _owned
              .where(
                (e) =>
                    '${e.recipient.name}\n${e.privateNote ?? ''}\n${e.sourceTitle}\n${e.localSearchText}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
    final headers = <Widget>[
      if (widget.onSystemNotifications != null)
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(Icons.notifications_none, color: p.accent),
            title: const Text('系统通知', style: TextStyle(fontSize: 16)),
            trailing: _Unread(count: widget.systemUnread),
            onTap: widget.onSystemNotifications,
          ),
        )
      else
        const SizedBox.shrink(),
      SizedBox(height: widget.onSystemNotifications == null ? 0 : 16),
      Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            if (widget.loading) const LinearProgressIndicator(minHeight: 2),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(widget.error!, style: TextStyle(color: p.error)),
                    if (widget.onRetry != null)
                      TextButton(
                        onPressed: widget.onRetry,
                        child: const Text('重新加载'),
                      ),
                  ],
                ),
              ),
            if (entries.isEmpty && !widget.loading && widget.error == null)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  query.isEmpty ? '还没有会话' : '没有找到相关会话',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.secondary),
                ),
              ),
          ],
        ),
      ),
    ];
    return Scaffold(
      backgroundColor: p.background,
      bottomNavigationBar: widget.navigation,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '私信',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 224,
                        minHeight: 48,
                      ),
                      child: Material(
                        key: _identityAnchor,
                        color: p.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(color: p.line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Tooltip(
                          message: '切换身份',
                          child: InkWell(
                            key: const ValueKey('dm-inbox-identity'),
                            onTap: _selectIdentity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
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
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          widget.identity.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: p.ink,
                                          ),
                                        ),
                                        Text(
                                          '当前身份',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: p.secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Badge(
                                    isLabelVisible: widget.identities.any(
                                      (i) =>
                                          i.identity.id != widget.identity.id &&
                                          i.unread > 0,
                                    ),
                                    child: HhDmAvatar(
                                      identity: widget.identity,
                                      size: 28,
                                    ),
                                  ),
                                ],
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                key: const ValueKey('dm-search'),
                controller: _search,
                onChanged: (value) {
                  setState(() {});
                  widget.onSearchChanged?.call(value);
                },
                style: TextStyle(fontSize: 16, color: p.ink),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: p.surface,
                  hintText: '搜索',
                  prefixIcon: const Icon(Icons.search, size: 24),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            setState(() => _search.clear());
                            widget.onSearchChanged?.call('');
                          },
                          icon: const Icon(Icons.close, size: 20),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    itemCount: entries.length + 4,
                    itemBuilder: (context, index) {
                      if (index < 3) return headers[index];
                      if (index == entries.length + 3) {
                        return Material(
                          color: p.surface,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          child: const SizedBox(height: 8),
                        );
                      }
                      final entry = entries[index - 3];
                      return Material(
                        color: p.surface,
                        child: InkWell(
                          key: ValueKey('conversation:${entry.id}'),
                          onTap: () => widget.onOpen(
                            DmInboxTarget(
                              scopeKey: widget.scopeKey,
                              identityId: widget.identity.id,
                              conversationId: entry.id,
                            ),
                          ),
                          onLongPress: widget.onManage == null
                              ? null
                              : () => widget.onManage!(
                                  DmInboxTarget(
                                    scopeKey: widget.scopeKey,
                                    identityId: widget.identity.id,
                                    conversationId: entry.id,
                                  ),
                                ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                HhDmAvatar(identity: entry.recipient, size: 50),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.privateNote ??
                                            entry.recipient.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
                                          color: p.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          if (entry.outgoingState != null &&
                                              entry.outgoingState !=
                                                  DmSendState.sent) ...[
                                            Icon(
                                              entry.outgoingState ==
                                                      DmSendState.failed
                                                  ? Icons.error_outline
                                                  : Icons.schedule,
                                              size: 15,
                                              color:
                                                  entry.outgoingState ==
                                                      DmSendState.failed
                                                  ? p.error
                                                  : p.secondary,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Expanded(
                                            child: Text(
                                              entry.preview,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: p.secondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      entry.time,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: entry.unread > 0
                                            ? p.accent
                                            : p.secondary,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    if (entry.unread > 0)
                                      _Unread(count: entry.unread)
                                    else if (entry.pinned)
                                      Icon(
                                        Icons.push_pin,
                                        size: 16,
                                        color: p.secondary,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_pending)
                    Positioned(
                      top: 4,
                      left: 48,
                      right: 48,
                      child: FilledButton.icon(
                        key: const ValueKey('dm-inbox-new'),
                        onPressed: () {
                          setState(() {
                            _pending = false;
                            _order = _owned.map((e) => e.id).toList();
                          });
                          _scroll.jumpTo(0);
                        },
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        label: const Text('有新消息'),
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
}

class _Unread extends StatelessWidget {
  const _Unread({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    if (count <= 0) return const SizedBox.shrink();
    return Semantics(
      label: '$count条未读',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.action,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
