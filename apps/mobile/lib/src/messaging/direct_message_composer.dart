import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../identity/identity_avatar.dart';
import 'direct_message_bubble.dart';
import 'direct_message_models.dart';

class HhDmAvatar extends StatelessWidget {
  const HhDmAvatar({super.key, required this.identity, this.size = 40});
  final DmIdentity identity;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return ExcludeSemantics(
      child: IdentityAvatar(
        avatar: identity.avatar,
        radius: size / 2,
        fallback: CircleAvatar(
          radius: size / 2,
          backgroundColor: p.action,
          foregroundColor: Colors.white,
          child: Text(
            identity.name.isEmpty ? '?' : identity.name.characters.first,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class HhDirectMessageComposer extends StatelessWidget {
  const HhDirectMessageComposer({
    super.key,
    required this.view,
    required this.text,
    required this.focus,
    required this.images,
    required this.imageBuilder,
    required this.onIdentity,
    required this.onPickImages,
    required this.onRemoveImage,
    required this.onSend,
    required this.onTextChanged,
    this.queueing = false,
    this.textOnly = false,
  });
  final DmConversationView view;
  final TextEditingController text;
  final FocusNode focus;
  final List<DmImage> images;
  final DmImageBuilder imageBuilder;
  final VoidCallback onIdentity, onPickImages, onSend;
  final ValueChanged<DmImage> onRemoveImage;
  final ValueChanged<String> onTextChanged;
  final bool queueing;
  final bool textOnly;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    final waiting = view.waitingForReply;
    final ready =
        (text.text.trim().isNotEmpty || images.isNotEmpty) &&
        !queueing &&
        !waiting &&
        view.canSend;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!view.canSend || waiting)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Text(
              waiting ? '对方回复前只能发一条消息' : '对方身份已失效，无法继续发送',
              style: TextStyle(color: p.secondary, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              if (view.selfIdentity != null) ...[
                HhDmAvatar(identity: view.selfIdentity!, size: 22),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    view.selfIdentity!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.secondary, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 5),
                if (view.identityLocked)
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 12,
                    color: p.secondary,
                  ),
              ],
              if (!view.identityLocked)
                TextButton(
                  key: const ValueKey('dm-select-identity'),
                  onPressed: onIdentity,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    view.selfIdentity == null ? '选择发送身份' : '更换',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (images.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              padding: const EdgeInsets.only(bottom: 8),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox(
                width: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageBuilder(context, images[index]),
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton.filled(
                          key: ValueKey('remove-image:${images[index].id}'),
                          tooltip: '移除第${index + 1}张图片',
                          onPressed: () => onRemoveImage(images[index]),
                          icon: const Icon(Icons.close_rounded, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Material(
          color: p.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6, right: 8),
                  child: view.selfIdentity == null
                      ? IconButton(
                          tooltip: '选择发送身份',
                          onPressed: view.identityLocked ? null : onIdentity,
                          icon: const Icon(Icons.person_outline),
                        )
                      : HhDmAvatar(identity: view.selfIdentity!, size: 34),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('dm-input'),
                    controller: text,
                    focusNode: focus,
                    readOnly: !view.canSend || waiting,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: onTextChanged,
                    style: TextStyle(color: p.ink, fontSize: 17, height: 1.35),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintText: waiting ? '等待对方回复' : '输入消息',
                      hintStyle: TextStyle(color: p.secondary),
                    ),
                  ),
                ),
                if (!textOnly)
                  IconButton(
                    key: const ValueKey('dm-attach'),
                    tooltip: '添加图片',
                    onPressed: view.canSend ? onPickImages : null,
                    icon: Transform.rotate(
                      angle: -.35,
                      child: const Icon(Icons.attach_file_rounded, size: 26),
                    ),
                  ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    key: const ValueKey('dm-send'),
                    tooltip: '发送消息',
                    onPressed: ready ? onSend : null,
                    style: IconButton.styleFrom(
                      backgroundColor: p.action,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: p.action.withValues(alpha: .12),
                      disabledForegroundColor: p.secondary,
                    ),
                    icon: queueing
                        ? const SizedBox.square(
                            dimension: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
