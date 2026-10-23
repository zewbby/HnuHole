import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/telegram_theme.dart';
import 'direct_message_composer.dart';
import 'direct_message_models.dart';

/// Floating controls measured from the supplied 1080px Telegram references.
/// Uses HnuHole's existing semantic palette; never displays presence or calls.
class HhDmHeader extends StatelessWidget {
  const HhDmHeader({
    super.key,
    required this.view,
    required this.onBack,
    required this.onSource,
    this.onManage,
  });
  final DmConversationView view;
  final VoidCallback onBack, onSource;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final radius = BorderRadius.circular(32);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: p.surface.withValues(alpha: .94),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: '返回',
              onPressed: onBack,
              style: IconButton.styleFrom(
                fixedSize: const Size(52, 52),
                foregroundColor: p.ink,
              ),
              icon: const Icon(Icons.arrow_back, size: 26),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: p.surface.withValues(alpha: .94),
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(
                  children: [
                    HhDmAvatar(identity: view.recipient, size: 44),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: scale > 1.4 ? 4 : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              view.privateNote ?? view.recipient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: p.ink,
                              ),
                            ),
                            Text(
                              view.privateNote == null
                                  ? '私密会话'
                                  : view.recipient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: p.surface.withValues(alpha: .94),
            shape: const CircleBorder(),
            child: PopupMenuButton<int>(
              key: const ValueKey('dm-conversation-menu'),
              tooltip: '会话选项',
              requestFocus: false,
              constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              icon: Icon(Icons.more_vert, color: p.ink, size: 26),
              style: IconButton.styleFrom(fixedSize: const Size(52, 52)),
              onSelected: (value) {
                if (value == 0) onSource();
                if (value == 2) onManage?.call();
                if (value == 1) {
                  Clipboard.setData(ClipboardData(text: view.recipient.name));
                }
              },
              itemBuilder: (_) => [
                if (onManage != null)
                  const PopupMenuItem(
                    value: 2,
                    child: Row(
                      children: [
                        Icon(Icons.tune, size: 22),
                        SizedBox(width: 18),
                        Text('会话管理'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 0,
                  enabled: !view.sourceDeleted,
                  child: const Row(
                    children: [
                      Icon(Icons.article_outlined, size: 22),
                      SizedBox(width: 18),
                      Flexible(child: Text('查看来源帖')),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 1,
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, size: 22),
                      SizedBox(width: 18),
                      Flexible(child: Text('复制昵称')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HhDmWallpaper extends StatelessWidget {
  const HhDmWallpaper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(p.background, p.outgoing, .5)!,
            p.background,
            Color.lerp(p.background, p.selection, .65)!,
          ],
        ),
      ),
      child: child,
    );
  }
}
