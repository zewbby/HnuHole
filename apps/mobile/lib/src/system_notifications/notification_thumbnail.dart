import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;

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

class _NotificationThumbnailState extends State<NotificationThumbnail>
    with WidgetsBindingObserver {
  PostImages? group;
  ImageProvider? provider;
  int revision = 0;
  bool loading = false, failed = false, refreshScheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
  }

  bool get visible {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return false;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.overlaps(Offset.zero & MediaQuery.sizeOf(context))) return false;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    return viewport is! RenderBox ||
        !viewport.hasSize ||
        rect.overlaps(viewport.localToGlobal(Offset.zero) & viewport.size);
  }

  void detach() {
    group?.accessGranted.removeListener(changed);
    group?.onRelease?.call();
    group = null;
    provider = null;
  }

  void refreshExpired() {
    if (!mounted ||
        loading ||
        failed ||
        refreshScheduled ||
        group?.isExpired?.call() != true) {
      return;
    }
    refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshScheduled = false;
      // An expired lease may obtain fresh authority. A denied/released lease
      // remains terminal and must never be revived automatically.
      if (!mounted ||
          loading ||
          failed ||
          group?.isExpired?.call() != true ||
          !visible) {
        return;
      }
      unawaited(load());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    refreshExpired();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshExpired();
  }

  @override
  void didUpdateWidget(NotificationThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      revision++;
      detach();
      unawaited(load());
    }
  }

  Future<void> load() async {
    final generation = ++revision;
    loading = true;
    failed = false;
    detach();
    try {
      final images = await widget.load(widget.postId);
      if (!mounted ||
          generation != revision ||
          images.postId != widget.postId ||
          !images.accessGranted.value ||
          images.images.isEmpty) {
        images.onRelease?.call();
        if (mounted && generation == revision) failed = true;
        return;
      }
      group = images;
      images.accessGranted.addListener(changed);
      images.maintainAccessWhile?.call(() => visible);
      final first = images.images.first;
      final image = first.thumbnail ?? await first.loadThumbnail!();
      if (!mounted ||
          generation != revision ||
          group != images ||
          !images.accessGranted.value) {
        return;
      }
      final decoded = ResizeImage(
        image,
        width: 168,
        height: 198,
        policy: ResizeImagePolicy.fit,
      );
      first.registerDecodeProvider?.call(decoded);
      setState(() => provider = decoded);
    } on Object {
      if (mounted && generation == revision) {
        failed = true;
        setState(() => provider = null);
      }
    } finally {
      if (mounted && generation == revision) {
        loading = false;
        refreshExpired();
      }
    }
  }

  void changed() {
    if (!mounted || group?.accessGranted.value != false) return;
    void update() {
      if (!mounted || group?.accessGranted.value != false) return;
      setState(() => provider = null);
      refreshExpired();
    }

    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      update();
    }
  }

  @override
  void dispose() {
    revision++;
    WidgetsBinding.instance.removeObserver(this);
    detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    refreshExpired();
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
