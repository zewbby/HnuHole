import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';

@immutable
class FeedChannelView {
  const FeedChannelView(this.code, this.title, this.icon);
  final String code, title;
  final IconData icon;
}

/// Presentation-only; caller supplies the authorized channel directory.
Future<void> showFeedChannelPicker(
  BuildContext context, {
  required List<FeedChannelView> channels,
  required Listenable authority,
  required bool Function() isCurrent,
  required String? selected,
  required ValueChanged<String?> onSelected,
  bool includeRecommended = true,
}) => _sheet(
  context,
  AnimatedBuilder(
    animation: authority,
    builder: (context, _) => isCurrent()
        ? _ChannelPicker(
            channels: channels,
            selected: selected,
            includeRecommended: includeRecommended,
            onSelected: (code) {
              Navigator.of(context).pop();
              if (isCurrent()) onSelected(code);
            },
          )
        : const Center(child: Text('请重新登录')),
  ),
);

Future<void> showFeedBlockFilter(
  BuildContext context, {
  required List<FeedChannelView> channels,
  required Listenable authority,
  required Set<String> Function() blocked,
  required bool Function() saving,
  required bool Function() ready,
  required VoidCallback onRetry,
  required bool Function() isCurrent,
  required String? Function() error,
  required ValueChanged<Set<String>> onChanged,
}) => _sheet(
  context,
  AnimatedBuilder(
    animation: authority,
    builder: (context, _) => isCurrent()
        ? _BlockFilter(
            channels: channels,
            blocked: blocked(),
            saving: saving(),
            ready: ready(),
            onRetry: onRetry,
            error: error(),
            onChanged: onChanged,
          )
        : const Center(child: Text('请重新登录')),
  ),
);

Future<void> _sheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: .32),
      backgroundColor: HhTelegramPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: child,
      ),
    );

TextStyle _style(
  BuildContext context,
  double size, {
  bool bold = false,
  Color? color,
}) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  fontSize: size,
  height: 1.35,
  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
  color: color ?? HhTelegramPalette.of(context).ink,
);

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: p.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: _style(context, 22, bold: true),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: _style(context, 14, color: p.secondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker({
    required this.channels,
    required this.selected,
    required this.onSelected,
    required this.includeRecommended,
  });
  final List<FeedChannelView> channels;
  final String? selected;
  final bool includeRecommended;
  final ValueChanged<String?> onSelected;
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    final items = [
      if (includeRecommended) (null, '推荐'),
      for (final c in channels) (c.code, c.title),
    ];
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _Header(
            includeRecommended ? '切换通道' : '选择发布通道',
            includeRecommended ? '点击名称，直接进入对应通道' : '选择本次新帖所属的通道',
          ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('channel-options'),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final active = item.$1 == selected;
                return Semantics(
                  selected: active,
                  child: Material(
                    color: active ? p.selection : p.surface,
                    child: InkWell(
                      key: ValueKey(
                        'choose-channel:${item.$1 ?? 'recommended'}',
                      ),
                      onTap: () => onSelected(item.$1),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 17,
                          ),
                          child: Text(
                            item.$2,
                            style: _style(
                              context,
                              18,
                              bold: active,
                              color: active ? p.accent : p.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockFilter extends StatefulWidget {
  const _BlockFilter({
    required this.channels,
    required this.blocked,
    required this.onChanged,
    required this.saving,
    required this.ready,
    required this.onRetry,
    this.error,
  });
  final bool saving, ready;
  final VoidCallback onRetry;
  final String? error;
  final List<FeedChannelView> channels;
  final Set<String> blocked;
  final ValueChanged<Set<String>> onChanged;
  @override
  State<_BlockFilter> createState() => _BlockFilterState();
}

class _BlockFilterState extends State<_BlockFilter> {
  late Set<String> _blocked;
  @override
  void initState() {
    super.initState();
    _blocked = Set.of(widget.blocked);
  }

  @override
  void didUpdateWidget(_BlockFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _blocked = Set.of(widget.blocked);
  }

  void _set(String code, bool value) {
    if (widget.saving || !widget.ready) return;
    final next = Set<String>.of(widget.blocked);
    value ? next.add(code) : next.remove(code);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _Header(
            '屏蔽内容',
            _blocked.isEmpty ? '开启后隐藏对应通道的帖子' : '已屏蔽 ${_blocked.length} 个通道',
          ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('block-options'),
              padding: EdgeInsets.zero,
              itemCount: widget.channels.length,
              itemBuilder: (context, index) {
                final channel = widget.channels[index];
                final active = _blocked.contains(channel.code);
                return InkWell(
                  onTap: (widget.saving || !widget.ready)
                      ? null
                      : () => _set(channel.code, !active),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(channel.icon, color: p.ink, size: 25),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            channel.title,
                            style: _style(context, 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          label: '屏蔽${channel.title}',
                          child: Switch(
                            key: ValueKey('block-channel:${channel.code}'),
                            value: active,
                            onChanged: (widget.saving || !widget.ready)
                                ? null
                                : (value) => _set(channel.code, value),
                            activeTrackColor: p.action,
                            activeThumbColor: Colors.white,
                            inactiveTrackColor: p.background,
                            inactiveThumbColor: p.secondary.withValues(
                              alpha: .35,
                            ),
                            trackOutlineColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.selected)
                                  ? Colors.transparent
                                  : p.line,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.saving) const LinearProgressIndicator(),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.error!, style: TextStyle(color: p.error)),
            ),
          if (widget.error != null)
            TextButton(
              onPressed: widget.saving ? null : widget.onRetry,
              child: const Text('重新核对设置'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('reset-blocks'),
                onPressed: (widget.saving || !widget.ready)
                    ? null
                    : () => widget.onChanged({}),
                child: Text(
                  '重置',
                  style: _style(context, 18, bold: true, color: p.onAccent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
