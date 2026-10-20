library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'viewer_save.dart';

part 'viewer_controller.dart';
part 'viewer_surface.dart';
part 'viewer_resources.dart';

/// A complete viewing surface. The caller owns navigation and controllers.
///
/// Removing this widget ends its controller's session. Create a fresh controller
/// to reopen. [onChanged] emits the latest sanitized snapshot per frame;
/// [onClosed] emits once while attached, and never navigates on its own.
class HnuImageViewer extends StatefulWidget {
  const HnuImageViewer({
    required this.controller,
    this.saveCoordinator,
    this.enableAndroidSaving = true,
    this.onChanged,
    this.onClosed,
    this.backgroundColor = Colors.black,
    super.key,
  });

  final ViewerController controller;
  final ViewerSaveCoordinator? saveCoordinator;

  /// Uses an internally owned gal coordinator on Android when none is supplied.
  /// Other platforms require an explicit coordinator. Item permissions and the
  /// complete original resolver remain mandatory; viewing never requests access.
  final bool enableAndroidSaving;
  final ValueChanged<ViewerSnapshot>? onChanged;
  final ValueChanged<ViewerCloseReason>? onClosed;
  final Color backgroundColor;

  @override
  State<HnuImageViewer> createState() => _HnuImageViewerState();
}

class _HnuImageViewerState extends State<HnuImageViewer>
    with WidgetsBindingObserver {
  bool _closedNotified = false;
  String? _saveMessage;
  int _callbackRevision = 0;
  bool _applicationForeground = true;
  bool _ancestorVisible = true;
  ViewerSaveCoordinator? _ownedSaver;
  ViewerSaveCoordinator? get _saver => widget.saveCoordinator ?? _ownedSaver;

  void _configureSaving() {
    final useDefault =
        widget.saveCoordinator == null &&
        widget.enableAndroidSaving &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;
    if (useDefault) {
      _ownedSaver ??= ViewerSaveCoordinator(
        gallery: const GalViewerGalleryWriter(),
      );
    } else {
      _ownedSaver?.dispose();
      _ownedSaver = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _configureSaving();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _applicationForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _connect();
    WidgetsBinding.instance.addObserver(this);
  }

  void _connect() {
    widget.controller._attach(this);
    widget.controller.addListener(_changed);
    _saver?.busyListenable.addListener(_saveChanged);
    widget.controller._setForeground(
      _applicationForeground && _ancestorVisible,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller._owner == this) {
        widget.controller._loadCurrent();
        _queueCallbacks();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ancestorVisible = TickerMode.valuesOf(context).enabled;
    widget.controller._setForeground(
      _applicationForeground && _ancestorVisible,
    );
  }

  @override
  void didUpdateWidget(HnuImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSaver = oldWidget.saveCoordinator ?? _ownedSaver;
    oldSaver?.busyListenable.removeListener(_saveChanged);
    if (oldWidget.controller != widget.controller) {
      _ownedSaver?.dispose();
      _ownedSaver = null;
    }
    _configureSaving();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller._detach(this);
      _closedNotified = false;
      _saveMessage = null;
      _callbackRevision++;
      _connect();
    } else {
      _saver?.busyListenable.addListener(_saveChanged);
      if (oldSaver != _saver) _saveMessage = null;
    }
  }

  void _saveChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() => _saveMessage = null);
    _queueCallbacks();
  }

  void _queueCallbacks() {
    final controller = widget.controller;
    final snapshot = controller.snapshot;
    final revision = ++_callbackRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.controller != controller ||
          controller._owner != this ||
          revision != _callbackRevision) {
        return;
      }
      widget.onChanged?.call(snapshot);
      if (mounted &&
          controller._owner == this &&
          snapshot.closeReason != null &&
          snapshot.closeReason != ViewerCloseReason.detached &&
          !_closedNotified) {
        _closedNotified = true;
        widget.onClosed?.call(snapshot.closeReason!);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationForeground = state == AppLifecycleState.resumed;
    widget.controller._setForeground(
      _applicationForeground && _ancestorVisible,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    _saver?.busyListenable.removeListener(_saveChanged);
    _ownedSaver?.dispose();
    widget.controller._detach(this);
    super.dispose();
  }

  String get _saveAvailability {
    final c = widget.controller;
    if (!c.active) return '查看已结束';
    if (!c.foreground) return '返回查看后可保存';
    if (!c.currentItem.saveAllowed) return '此图片不允许保存';
    if (_saver == null) return '此查看入口未启用保存';
    if (!_saver!.active) return '此保存入口已失效';
    if (c.currentItem.resolveOriginal == null) return '没有可保存的原文件';
    if (_saver!.busy) return '正在保存图片';
    if (c.status != ViewerLoadStatus.ready) return '图片加载完成后可保存';
    return '保存图片';
  }

  Future<void> _save() async {
    final coordinator = _saver;
    final c = widget.controller;
    final item = c.currentItem;
    if (coordinator == null || item.resolveOriginal == null) return;
    final generation = c.generation;
    final selection = c.selectionRevision;
    bool isCurrent() =>
        mounted &&
        widget.controller == c &&
        identical(_saver, coordinator) &&
        coordinator.active &&
        c.active &&
        c.foreground &&
        c.generation == generation &&
        c.selectionRevision == selection &&
        c.currentItem.id == item.id;
    final result = await coordinator.save(
      itemId: item.id,
      resolveOriginal: item.resolveOriginal!,
      allowed: item.saveAllowed,
      isCurrent: isCurrent,
    );
    if (isCurrent() && result.isCurrent) {
      setState(() => _saveMessage = result.message);
    }
  }

  Widget _actionButton({
    required Key key,
    required String label,
    required Widget icon,
    VoidCallback? onPressed,
  }) => Semantics(
    container: true,
    label: label,
    button: true,
    enabled: onPressed != null,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: IconButton(
        key: key,
        tooltip: label,
        onPressed: onPressed,
        icon: icon,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final saveLabel = _saveAvailability;
    final saveEnabled = saveLabel == '保存图片';
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) c.close(ViewerCloseReason.systemBack);
      },
      child: Theme(
        data: ThemeData(
          brightness: ThemeData.estimateBrightnessForColor(
            widget.backgroundColor,
          ),
        ),
        // Material supplies DefaultTextStyle, so it must be below the viewer's
        // own theme rather than inheriting the page's foreground on a black UI.
        child: Material(
          color: widget.backgroundColor,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Row(
                    children: [
                      _actionButton(
                        key: const ValueKey('viewer-close'),
                        label: '关闭图片查看',
                        onPressed: c.active
                            ? () => c.close(ViewerCloseReason.button)
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          label: '第${c.index + 1}张，共${c.items.length}张',
                          child: ExcludeSemantics(
                            child: Text(
                              '${c.index + 1} / ${c.items.length}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      _actionButton(
                        key: const ValueKey('viewer-save'),
                        label: saveLabel,
                        onPressed: saveEnabled ? _save : null,
                        icon: _saver?.busy == true
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (c.active)
                          _ViewerSurface(
                            key: ValueKey((c, c.generation)),
                            controller: c,
                            backgroundColor: widget.backgroundColor,
                          ),
                        if (!c.active || c.status != ViewerLoadStatus.ready)
                          _feedback(c),
                      ],
                    ),
                  ),
                  if (_saveMessage != null)
                    ConstrainedBox(
                      // Short feedback uses its own height. Large text can scroll
                      // without consuming the image's share of the flex layout.
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight / 4,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_saveMessage!),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionButton(
                        key: const ValueKey('viewer-previous'),
                        label: '上一张图片',
                        onPressed: c.active && c.index > 0
                            ? () => c.select(c.index - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      _actionButton(
                        key: const ValueKey('viewer-next'),
                        label: '下一张图片',
                        onPressed: c.active && c.index + 1 < c.items.length
                            ? () => c.select(c.index + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedback(ViewerController c) {
    final message = !c.active
        ? c.accessValid
              ? '查看已结束'
              : '访问已失效'
        : c.status == ViewerLoadStatus.failed
        ? switch (c.failure) {
            ViewerFailure.invalidSource => '图片尺寸与来源不匹配',
            ViewerFailure.decodeFailed => '无法显示此图片',
            ViewerFailure.resourceLimit => '图片超出支持上限，请选择其他图片',
            _ => '图片加载失败',
          }
        : '正在加载图片';
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(liveRegion: true, child: Text(message)),
              if (c.active && c.status == ViewerLoadStatus.failed)
                TextButton(
                  key: const ValueKey('viewer-retry'),
                  onPressed: c.foreground ? c.retry : null,
                  child: const Text('重试加载'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
