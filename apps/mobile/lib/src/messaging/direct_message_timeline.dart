import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import 'direct_message_bubble.dart';
import 'direct_message_models.dart';

/// A reversed local timeline keeps the reading offset when older rows arrive.
/// All receipt, unread and persistence decisions belong to the owner.
class HhDmTimeline extends StatefulWidget {
  const HhDmTimeline({
    super.key,
    required this.view,
    required this.imageBuilder,
    required this.onMenu,
    required this.onImage,
    required this.onRetry,
    required this.onReedit,
    this.onLoadOlder,
    this.onVisible,
    this.selectedMessage,
    this.selectedImage,
  });
  final DmConversationView view;
  final DmImageBuilder imageBuilder;
  final void Function(DmMessage, String?, BuildContext) onMenu;
  final ValueChanged<DmImage> onImage;
  final ValueChanged<DmMessage> onRetry, onReedit;
  final Future<void> Function(DmHistoryRequest)? onLoadOlder;
  final ValueChanged<List<String>>? onVisible;
  final String? selectedMessage, selectedImage;

  @override
  State<HhDmTimeline> createState() => _HhDmTimelineState();
}

class _HhDmTimelineState extends State<HhDmTimeline> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _anchors = <String, GlobalKey>{};
  var _epoch = 0;
  var _loading = false;
  var _failed = false;
  var _away = false;
  var _newMessages = 0;
  String? _attemptedCursor;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HhDmTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.view, next = widget.view;
    if (old.scopeKey != next.scopeKey) {
      _epoch++;
      _loading = _failed = _away = _attempted = false;
      _attemptedCursor = null;
      _newMessages = 0;
      _anchors.clear();
      _latest(animate: false);
      return;
    }
    if (old.historyCursor != next.historyCursor ||
        old.historyState != next.historyState) {
      _attempted = false;
      _failed = false;
    }
    // Prepending older history does not change the newest id. Do not follow it.
    final latestChanged =
        next.messages.isNotEmpty &&
        (old.messages.isEmpty || old.messages.last.id != next.messages.last.id);
    if (latestChanged && !_away) {
      _latest(animate: false);
    } else if (latestChanged) {
      final known = old.messages.map((m) => m.id).toSet();
      _newMessages += next.messages
          .where((m) => !m.outgoing && !known.contains(m.id))
          .length;
      _preserveAnchor();
    }
    final retained = next.messages.map((m) => m.id).toSet();
    _anchors.removeWhere((id, _) => !retained.contains(id));
  }

  void _preserveAnchor() {
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !_scroll.hasClients) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    for (final entry in _anchors.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y < top || y >= top + viewport.size.height) continue;
      final epoch = _epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _epoch || !_scroll.hasClients) return;
        final updated =
            entry.value.currentContext?.findRenderObject() as RenderBox?;
        if (updated == null || !updated.attached) return;
        // Reversed viewport: increasing pixels moves rows down the screen.
        final delta = y - updated.localToGlobal(Offset.zero).dy;
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
        );
      });
      return;
    }
  }

  void _reportVisible() {
    if (widget.onVisible == null) return;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch) return;
      final viewport =
          _viewport.currentContext?.findRenderObject() as RenderBox?;
      if (viewport == null || !viewport.hasSize) return;
      final top = viewport.localToGlobal(Offset.zero).dy;
      final ids = <String>[];
      for (final message in widget.view.messages.where((m) => !m.outgoing)) {
        final box =
            _anchors[message.id]?.currentContext?.findRenderObject()
                as RenderBox?;
        if (box == null || !box.attached || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y < top + viewport.size.height && y + box.size.height > top) {
          ids.addAll(
            message.visibleMessageIds.isEmpty
                ? [message.id]
                : message.visibleMessageIds,
          );
        }
      }
      if (ids.isNotEmpty) widget.onVisible?.call(ids);
    });
  }

  void _latest({bool animate = true}) {
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch || !_scroll.hasClients) return;
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(0);
      }
    });
  }

  void _onScroll() {
    _reportVisible();
    final away = _scroll.offset > 80;
    if (away != _away || (!away && _newMessages > 0)) {
      setState(() {
        _away = away;
        if (!away) _newMessages = 0;
      });
    }
    if (_scroll.position.extentAfter < 160 &&
        widget.view.historyState == DmHistoryState.available &&
        !_failed) {
      _loadOlder();
    }
  }

  Future<void> _loadOlder({bool retry = false}) async {
    final load = widget.onLoadOlder;
    final view = widget.view;
    if (load == null ||
        _loading ||
        view.historyState == DmHistoryState.loading ||
        view.historyState == DmHistoryState.complete ||
        (!retry && _attempted && _attemptedCursor == view.historyCursor)) {
      return;
    }
    final epoch = _epoch;
    setState(() {
      _loading = _attempted = true;
      _failed = false;
      _attemptedCursor = view.historyCursor;
    });
    try {
      await load(
        DmHistoryRequest(scopeKey: view.scopeKey, before: view.historyCursor),
      );
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _reportVisible();
    final view = widget.view, p = HhTelegramPalette.of(context);
    if (view.messages.isEmpty && view.historyState == DmHistoryState.complete) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '还没有消息',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    view.firstContact ? '打个招呼吧\n对方回复前只能发送一条文字消息' : '从这里继续你们的对话',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: p.secondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Icon(Icons.waving_hand_outlined, size: 72, color: p.accent),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final indices = <Key, int>{
      for (var i = 0; i < view.messages.length; i++)
        ValueKey('message:${view.messages[i].id}'):
            view.messages.length - 1 - i,
    };
    return Stack(
      children: [
        ListView.builder(
          key: _viewport,
          controller: _scroll,
          reverse: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          itemCount: view.messages.length + 1,
          findChildIndexCallback: (key) => indices[key],
          itemBuilder: (context, index) {
            if (index == view.messages.length) {
              if (_loading || view.historyState == DmHistoryState.loading) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (view.historyState == DmHistoryState.complete ||
                  widget.onLoadOlder == null) {
                return const SizedBox.shrink();
              }
              final failed =
                  _failed || view.historyState == DmHistoryState.failed;
              return Center(
                child: TextButton.icon(
                  key: const ValueKey('dm-load-older'),
                  onPressed: () => _loadOlder(retry: true),
                  icon: Icon(
                    failed ? Icons.refresh : Icons.expand_less,
                    size: 20,
                  ),
                  label: Text(failed ? '历史消息加载失败，重试' : '加载更早的消息'),
                ),
              );
            }
            final i = view.messages.length - 1 - index;
            final message = view.messages[i];
            String day(int n) => view.messages[n].dayLabel ?? view.dayLabel;
            bool joins(int n) =>
                n >= 0 &&
                n < view.messages.length &&
                day(n) == day(i) &&
                !message.recalled &&
                !view.messages[n].recalled &&
                message.outgoing == view.messages[n].outgoing &&
                view.firstUnreadMessageId != view.messages[n > i ? n : i].id;
            return Column(
              key: ValueKey('message:${message.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (day(i).isNotEmpty && (i == 0 || day(i - 1) != day(i)))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.surface.withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Text(
                          day(i),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: p.secondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (message.id == view.firstUnreadMessageId)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '以下是未读消息',
                      style: TextStyle(fontSize: 12, color: p.accent),
                    ),
                  ),
                Container(
                  key: _anchors.putIfAbsent(message.id, () => GlobalKey()),
                  child: HhDirectMessageBubble(
                    message: message,
                    imageBuilder: widget.imageBuilder,
                    joinsPrevious: joins(i - 1),
                    joinsNext: joins(i + 1),
                    selected:
                        widget.selectedMessage == message.id &&
                        widget.selectedImage == null,
                    selectedImageId: widget.selectedMessage == message.id
                        ? widget.selectedImage
                        : null,
                    onMenu: (image, anchor) =>
                        widget.onMenu(message, image, anchor),
                    onImage: widget.onImage,
                    onRetry: () => widget.onRetry(message),
                    onReedit: () => widget.onReedit(message),
                  ),
                ),
              ],
            );
          },
        ),
        if (_away)
          Positioned(
            right: 8,
            bottom: 8,
            child: Semantics(
              label: _newMessages > 0 ? '$_newMessages条新消息，回到最新消息' : '回到最新消息',
              button: true,
              child: Badge(
                isLabelVisible: _newMessages > 0,
                label: Text('$_newMessages'),
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: '回到最新消息',
                  onPressed: _latest,
                  backgroundColor: p.surface,
                  foregroundColor: p.accent,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
