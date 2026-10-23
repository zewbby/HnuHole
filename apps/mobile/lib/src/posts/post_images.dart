import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

/// The host authorizes both providers and the complete original resolver.
/// A thumbnail is only a preview; [item] must load the full viewing resource.
class PostImage {
  const PostImage({
    required ImageProvider this.thumbnail,
    required this.item,
    this.pixelSize,
    this.animated = false,
    this.registerDecodeProvider,
  }) : loadThumbnail = null,
       retryThumbnail = null;
  const PostImage.deferred({
    required Future<ImageProvider> Function() this.loadThumbnail,
    required this.item,
    this.pixelSize,
    this.animated = false,
    this.registerDecodeProvider,
    this.retryThumbnail,
  }) : thumbnail = null;
  final ImageProvider? thumbnail;
  final Future<ImageProvider> Function()? loadThumbnail;

  /// Explicit retry also discards failed decode bytes in the host media cache.
  final Future<ImageProvider> Function()? retryThumbnail;
  final ViewerItem item;
  final Size? pixelSize;
  final bool animated;
  final ValueChanged<ImageProvider>? registerDecodeProvider;
}

/// One immutable, ordered post image group, owned by the calling media layer.
/// Content changes require new item IDs and a new group. Revocation is terminal
/// for the open viewer. The media layer owns/disposes [accessGranted].
class PostImages {
  PostImages({
    required this.postId,
    required List<PostImage> images,
    required this.accessGranted,
    this.onRelease,
    this.isExpired,
  }) : images = List.unmodifiable(images) {
    if (postId.isEmpty ||
        postId.trim() != postId ||
        images.length > 9 ||
        images.map((image) => image.item.id).toSet().length != images.length) {
      throw ArgumentError('Expected one post and at most nine unique images.');
    }
  }
  final String postId;
  final List<PostImage> images;
  final ValueListenable<bool> accessGranted;

  /// Releases this host-owned lease when the detail no longer uses it.
  final VoidCallback? onRelease;

  /// Only a natural authorization deadline permits an automatic fresh read.
  /// A denial, release or account change must keep the old group terminal.
  final bool Function()? isExpired;
}

/// Host media integration seam; production uses the fixed protected C contract.
/// Do not return a different post, credentials, or a publicly cached private URL.
typedef PostImagesLoader = Future<PostImages> Function(String postId);

/// Existing post details use this only when the host supplies a media loader.
/// The post authority is a lease, never an account/token passed to the viewer.
class PostImagesSection extends StatefulWidget {
  const PostImagesSection({
    required this.postId,
    required this.loadImages,
    required this.authority,
    required this.isCurrent,
    this.expectedCount,
    this.feedPreview = false,
    this.initialSizes,
    super.key,
  });
  final String postId;
  final PostImagesLoader loadImages;
  final Listenable authority;
  final bool Function() isCurrent;
  final int? expectedCount;
  final bool feedPreview;
  final List<Size>? initialSizes;
  @override
  State<PostImagesSection> createState() => _PostImagesSectionState();
}

class _PostImagesSectionState extends State<PostImagesSection> {
  PostImages? _group;
  ViewerController? _viewer;
  int _revision = 0;
  int? _scheduledGroupRevision;
  bool _loading = true, _failed = false, _revoked = false;
  List<Size?>? _feedSizes;

  @override
  void initState() {
    super.initState();
    widget.authority.addListener(_authorityChanged);
    _feedSizes = widget.initialSizes;
    unawaited(_load());
  }

  bool get _current => mounted && widget.isCurrent();

  void _authorityChanged() {
    if (!_current) {
      _feedSizes = null;
      _revision++;
      _viewer?.invalidateAccess();
      _detachGroup();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _groupChanged() {
    final group = _group;
    if (group != null && !group.accessGranted.value) {
      _revoked = true;
      _viewer?.invalidateAccess();
      final revision = _revision;
      if (_scheduledGroupRevision == revision) return;
      _scheduledGroupRevision = revision;
      // A decoder can discover expiry during LayoutBuilder. Revoke immediately,
      // but defer widget changes and new reads until this frame has finished.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scheduledGroupRevision != revision) return;
        _scheduledGroupRevision = null;
        if (!mounted || revision != _revision || !identical(_group, group)) {
          return;
        }
        if (_current && group.isExpired?.call() == true) {
          unawaited(_load());
        } else {
          setState(() {});
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _detachGroup() {
    _group?.accessGranted.removeListener(_groupChanged);
    _group?.onRelease?.call();
    _group = null;
  }

  Future<void> _load() async {
    if (!_current) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final group = await widget.loadImages(widget.postId);
      if (!_current || revision != _revision) {
        group.onRelease?.call();
        return;
      }
      if (group.postId != widget.postId ||
          widget.expectedCount != null &&
              group.images.length != widget.expectedCount) {
        group.onRelease?.call();
        throw StateError('Media belongs to another post.');
      }
      _detachGroup();
      _group = group;
      _feedSizes =
          widget.initialSizes ??
          [for (final image in group.images) image.pixelSize];
      _revoked = !group.accessGranted.value;
      group.accessGranted.addListener(_groupChanged);
    } catch (_) {
      if (!_current || revision != _revision) return;
      _failed = true;
    }
    if (_current && revision == _revision) setState(() => _loading = false);
  }

  @override
  void didUpdateWidget(PostImagesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.expectedCount != widget.expectedCount ||
        oldWidget.authority != widget.authority) {
      _feedSizes = widget.initialSizes;
    }
    if (oldWidget.postId != widget.postId ||
        oldWidget.expectedCount != widget.expectedCount ||
        oldWidget.loadImages != widget.loadImages ||
        oldWidget.authority != widget.authority) {
      oldWidget.authority.removeListener(_authorityChanged);
      widget.authority.addListener(_authorityChanged);
      _viewer?.invalidateAccess();
      _detachGroup();
      unawaited(_load());
    }
    _authorityChanged();
  }

  Future<void> _open(int index) async {
    final group = _group;
    if (!_current ||
        group == null ||
        _revoked ||
        !group.accessGranted.value ||
        _viewer != null) {
      return;
    }
    final viewer = ViewerController(
      items: [for (final image in group.images) image.item],
      initialIndex: index,
    );
    _viewer = viewer;
    final navigator = Navigator.of(context);
    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: HnuImageViewer(
          controller: viewer,
          onClosed: (_) {
            if (!route.isActive) return;
            // Never pop a different route/dialog which happens to be above it.
            if (route.isCurrent) {
              navigator.pop();
            } else {
              navigator.removeRoute(route);
            }
          },
        ),
      ),
    );
    try {
      await navigator.push<void>(route);
    } finally {
      if (identical(_viewer, viewer)) _viewer = null;
      viewer.dispose();
    }
  }

  @override
  void dispose() {
    _revision++;
    widget.authority.removeListener(_authorityChanged);
    _detachGroup();
    final viewer = _viewer;
    // Disposal may happen while the parent Navigator is building. The viewer
    // route is still owned here; end its lease safely after that frame.
    if (viewer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (viewer.active) viewer.invalidateAccess();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    if (_loading) {
      if (widget.feedPreview && _feedSizes?.isNotEmpty == true) {
        return _feedMedia(
          context,
          _group,
          placeholder: const Center(
            child: CircularProgressIndicator(semanticsLabel: '正在读取图片'),
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: '正在读取图片'),
        ),
      );
    }
    if (_failed) {
      if (widget.feedPreview && _feedSizes?.isNotEmpty == true) {
        return _feedMedia(
          context,
          _group,
          placeholder: _feedStatus('图片暂时无法读取', '重新加载图片'),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Text('图片暂时无法读取'),
            TextButton(onPressed: _load, child: const Text('重新加载图片')),
          ],
        ),
      );
    }
    final group = _group;
    if (group == null || group.images.isEmpty) return const SizedBox.shrink();
    if (_revoked || !group.accessGranted.value) {
      if (widget.feedPreview) {
        return _feedMedia(
          context,
          group,
          placeholder: _feedStatus('图片已不可访问', '重新读取图片'),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Text('图片已不可访问'),
            TextButton(onPressed: _load, child: const Text('重新读取图片')),
          ],
        ),
      );
    }
    if (widget.feedPreview) return _feedMedia(context, group);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: GridView.builder(
        key: const ValueKey('post-image-grid'),
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: group.images.length,
        itemBuilder: (context, index) => Semantics(
          button: true,
          label: '查看第${index + 1}张图片，共${group.images.length}张',
          child: Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(4),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              key: ValueKey(('post-image', group.images[index].item.id)),
              onTap: () => _open(index),
              child: ExcludeSemantics(
                child: _PostThumbnail(
                  key: ValueKey(group.images[index]),
                  image: group.images[index],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedStatus(String status, String retry) => Center(
    child: SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status),
          TextButton(onPressed: _load, child: Text(retry)),
        ],
      ),
    ),
  );

  Widget _feedMedia(
    BuildContext context,
    PostImages? group, {
    Widget? placeholder,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final sizes = _feedSizes!;
      double ratio(Size? size) {
        return size == null ? 1 : size.width / size.height;
      }

      Widget card(int index, double w, double h) => SizedBox(
        width: w,
        height: h,
        child: Semantics(
          button: placeholder == null,
          label: placeholder == null
              ? '查看第${index + 1}张图片，共${sizes.length}张'
              : null,
          child: Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            // Participate from pointer-down even if the lease or reload state
            // changes before pointer-up. The outer post must never inherit it.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () {},
              child:
                  placeholder ??
                  InkWell(
                    key: ValueKey(('feed-image', group!.images[index].item.id)),
                    onTap: () => _open(index),
                    child: _PostThumbnail(
                      key: ValueKey(group.images[index]),
                      image: group.images[index],
                      fit: sizes.length == 1 ? BoxFit.cover : BoxFit.contain,
                    ),
                  ),
            ),
          ),
        ),
      );
      if (sizes.length == 1) {
        final r = ratio(sizes.first);
        final previewRatio = r.clamp(.75, 2.0);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              card(0, width, width / previewRatio),
              if (r != previewRatio)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('点击查看完整图片', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      }
      final height = (width * .8).clamp(160.0, 260.0);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          height: height,
          child: ListView.separated(
            key: ValueKey('feed-media:${widget.postId}'),
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: sizes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 5),
            itemBuilder: (_, i) => card(
              i,
              (height * ratio(sizes[i])).clamp(width * .45, width * .78),
              height,
            ),
          ),
        ),
      );
    },
  );
}

class _PostThumbnail extends StatefulWidget {
  const _PostThumbnail({
    required this.image,
    this.fit = BoxFit.cover,
    super.key,
  });
  final BoxFit fit;
  final PostImage image;
  @override
  State<_PostThumbnail> createState() => _PostThumbnailState();
}

class _PostThumbnailState extends State<_PostThumbnail> {
  Future<ImageProvider>? _pending;
  ImageProvider? _decoded;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    final load = widget.image.loadThumbnail;
    if (load != null) _pending = Future<ImageProvider>.sync(load);
  }

  void _retry() {
    final load = widget.image.retryThumbnail ?? widget.image.loadThumbnail;
    if (load == null) return;
    final decoded = _decoded;
    if (decoded != null) unawaited(decoded.evict());
    setState(() {
      _attempt++;
      _pending = Future<ImageProvider>.sync(load);
    });
  }

  Widget _loading() => const Center(child: Text('图片加载中'));

  Widget _failure() => Center(
    child: SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('图片加载失败'),
          if (widget.image.loadThumbnail != null)
            TextButton(onPressed: _retry, child: const Text('点击重试')),
        ],
      ),
    ),
  );

  Widget _image(ImageProvider provider) => LayoutBuilder(
    builder: (context, constraints) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final width =
          ((constraints.maxWidth.isFinite ? constraints.maxWidth : 640) * dpr)
              .ceil()
              .clamp(1, 1280);
      final height =
          ((constraints.maxHeight.isFinite ? constraints.maxHeight : 640) * dpr)
              .ceil()
              .clamp(1, 1280);
      final decoded = ResizeImage(
        provider,
        width: width,
        height: height,
        policy: ResizeImagePolicy.fit,
      );
      _decoded = decoded;
      try {
        widget.image.registerDecodeProvider?.call(decoded);
      } catch (_) {
        // A synchronous authorization check can revoke this group during layout.
        // Never paint the stale provider or leak that rejection into the frame.
        return _failure();
      }
      final image = Image(
        key: ValueKey(_attempt),
        image: decoded,
        fit: widget.fit,
        frameBuilder: (_, child, frame, sync) =>
            sync || frame != null ? child : _loading(),
        errorBuilder: (_, _, _) => _failure(),
      );
      if (!widget.image.animated) return image;
      return Stack(
        fit: StackFit.expand,
        children: [
          image,
          const Positioned(
            right: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '动图',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    if (widget.image.thumbnail case final provider?) return _image(provider);
    return FutureBuilder<ImageProvider>(
      future: _pending,
      builder: (_, snapshot) => snapshot.connectionState != ConnectionState.done
          ? _loading()
          : snapshot.hasData
          ? _image(snapshot.data!)
          : _failure(),
    );
  }
}
