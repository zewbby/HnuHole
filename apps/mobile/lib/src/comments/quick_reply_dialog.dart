import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';

/// Presentation shared by the real comment composer and its visual preview.
class QuickReplyDialog extends StatelessWidget {
  const QuickReplyDialog({
    super.key,
    required this.targetName,
    required this.controller,
    required this.onReply,
    required this.onClose,
    this.busy = false,
    this.error,
    this.identityCaption,
    this.onRetry,
    this.retryLabel = '重试',
  });
  final String targetName;
  final TextEditingController controller;
  final VoidCallback? onReply, onClose, onRetry;
  final bool busy;
  final String? error, identityCaption;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    TextStyle type(
      double size, {
      Color? color,
      FontWeight weight = FontWeight.w400,
    }) => Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: size,
      height: 1.5,
      fontWeight: weight,
      color: color ?? p.ink,
    );
    return Dialog(
      key: const ValueKey('quick-reply-dialog'),
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: .12),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '回复给 ',
                              style: type(17, color: p.secondary),
                            ),
                            TextSpan(
                              text: targetName,
                              style: type(18, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '收起回复',
                      onPressed: onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: p.secondary,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                TextField(
                  key: const ValueKey('reply-input'),
                  controller: controller,
                  readOnly: busy,
                  minLines: 4,
                  maxLines: 7,
                  style: type(17),
                  cursorColor: p.action,
                  decoration: InputDecoration(
                    hintText: '写下你的回复…',
                    hintStyle: type(17, color: p.secondary),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.only(
                      top: 3,
                      right: 6,
                      bottom: 5,
                    ),
                  ),
                ),
                if (error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(error!, style: type(14, color: p.error)),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: busy ? null : onRetry,
                      child: Text(retryLabel),
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: identityCaption == null
                          ? const SizedBox.shrink()
                          : Text(
                              identityCaption!,
                              style: type(13, color: p.secondary),
                            ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => FilledButton(
                        key: const ValueKey('reply-send'),
                        onPressed: busy || value.text.trim().isEmpty
                            ? null
                            : onReply,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.action,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: p.action.withValues(
                            alpha: .14,
                          ),
                          disabledForegroundColor: p.secondary,
                          minimumSize: const Size(92, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 26),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          textStyle: type(16, weight: FontWeight.w500),
                          elevation: 0,
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('回复'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
