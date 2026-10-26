import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import '../posts/post_images.dart';

/// A small source-post cover using the same protected media lease as the feed.
class NotificationThumbnail extends StatefulWidget {
  const NotificationThumbnail({
    super.key,
    required this.postId,
    required this.load,
  });
  final String postId;
  final PostImagesLoader load;
  @override
  State<NotificationThumbnail> createState() => _NotificationThumbnailState();
}

class _NotificationThumbnailState extends State<NotificationThumbnail> {
  PostImages? group;
  ImageProvider? provider;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final images = await widget.load(widget.postId);
      if (!mounted ||
          images.postId != widget.postId ||
          !images.accessGranted.value ||
          images.images.isEmpty) {
        images.onRelease?.call();
        return;
      }
      group = images;
      images.accessGranted.addListener(changed);
      images.maintainAccessWhile?.call(() {
        if (!mounted ||
            !TickerMode.valuesOf(context).enabled ||
            ModalRoute.of(context)?.isCurrent == false) {
          return false;
        }
        final box = context.findRenderObject();
        return box is RenderBox &&
            box.attached &&
            box.hasSize &&
            (box.localToGlobal(Offset.zero) & box.size).overlaps(
              Offset.zero & MediaQuery.sizeOf(context),
            );
      });
      final first = images.images.first;
      final image = first.thumbnail ?? await first.loadThumbnail!();
      if (!mounted || group != images || !images.accessGranted.value) return;
      final decoded = ResizeImage(
        image,
        width: 168,
        height: 198,
        policy: ResizeImagePolicy.fit,
      );
      first.registerDecodeProvider?.call(decoded);
      setState(() => provider = decoded);
    } on Object {
      if (mounted) setState(() => provider = null);
    }
  }

  void changed() {
    if (mounted && !group!.accessGranted.value) setState(() => provider = null);
  }

  @override
  void dispose() {
    group?.accessGranted.removeListener(changed);
    group?.onRelease?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 66,
        child: ColoredBox(
          color: p.background,
          child: provider == null
              ? Icon(Icons.image_outlined, color: p.secondary, size: 20)
              : Image(
                  image: provider!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.image_outlined, color: p.secondary, size: 20),
                ),
        ),
      ),
    );
  }
}
