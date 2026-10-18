part of 'post_screens.dart';

class _ComposerPhotos extends StatelessWidget {
  const _ComposerPhotos({
    required this.controller,
    required this.editor,
    required this.onChanged,
  });
  final PostController controller;
  final PostDraftEditor editor;
  final VoidCallback onChanged;
  void move(int from, int to) {
    if (editor.mediaBusy || !controller.editorCurrent(editor) || from == to) {
      return;
    }
    final image = editor.images.removeAt(from);
    editor.images.insert(to, image);
    editor.mediaTouched = true;
    onChanged();
  }

  Future<void> preview(BuildContext context, DraftPostImage selected) async {
    final images = editor.images.where((e) => e.ready).toList();
    final providers = <MemoryImage>{};
    var open = true;
    final viewer = ViewerController(
      initialIndex: images.indexOf(selected),
      items: [
        for (final image in images)
          ViewerItem(
            id: image.mediaId,
            saveAllowed: false,
            loadSource: () async {
              final bytes = await controller.draftPhotoBytes(editor, image);
              final codec = await ui.instantiateImageCodec(bytes);
              Size size;
              try {
                final frame = await codec.getNextFrame();
                size = Size(
                  frame.image.width.toDouble(),
                  frame.image.height.toDouble(),
                );
                frame.image.dispose();
              } finally {
                codec.dispose();
              }
              if (!open || !controller.editorCurrent(editor)) {
                throw const PostStorageFailure();
              }
              final provider = MemoryImage(bytes);
              providers.add(provider);
              return ViewerSource(provider: provider, pixelSize: size);
            },
          ),
      ],
    );
    final navigator = Navigator.of(context);
    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: HnuImageViewer(
          controller: viewer,
          onClosed: (_) {
            if (!route.isActive) return;
            if (route.isCurrent) {
              navigator.pop();
            } else {
              navigator.removeRoute(route);
            }
          },
        ),
      ),
    );
    void changed() {
      if (!controller.editorCurrent(editor)) viewer.invalidateAccess();
    }

    controller.addListener(changed);
    try {
      await navigator.push(route);
    } finally {
      open = false;
      controller.removeListener(changed);
      viewer.dispose();
      for (final provider in providers) {
        unawaited(provider.evict());
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('图片', style: TextStyle(color: PostTheme.muted)),
            const Spacer(),
            Text(
              '${editor.images.length}/9',
              style: const TextStyle(color: PostTheme.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < editor.images.length; index++)
                  DragTarget<String>(
                    onWillAcceptWithDetails: (d) =>
                        !editor.mediaBusy &&
                        d.data != editor.images[index].mediaId,
                    onAcceptWithDetails: (d) {
                      final from = editor.images.indexWhere(
                        (e) => e.mediaId == d.data,
                      );
                      if (from >= 0) move(from, index);
                    },
                    builder: (context, candidates, rejected) {
                      final image = editor.images[index];
                      final tile = Semantics(
                        label: '第${index + 1}张图片${image.ready ? '' : '，无法读取'}',
                        customSemanticsActions: {
                          if (index > 0)
                            const CustomSemanticsAction(label: '向前移动'): () =>
                                move(index, index - 1),
                          if (index + 1 < editor.images.length)
                            const CustomSemanticsAction(label: '向后移动'): () =>
                                move(index, index + 1),
                        },
                        child: SizedBox(
                          width: width,
                          height: width,
                          child: Material(
                            color: candidates.isNotEmpty
                                ? PostTheme.muted
                                : PostTheme.cardTint,
                            borderRadius: BorderRadius.circular(6),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (image.ready)
                                  InkWell(
                                    onTap: editor.mediaBusy
                                        ? null
                                        : () => preview(context, image),
                                    child: _DraftPhotoPreview(
                                      key: ValueKey(image.blobId),
                                      load: () => controller.draftPhotoBytes(
                                        editor,
                                        image,
                                      ),
                                    ),
                                  )
                                else
                                  Center(
                                    child: IconButton(
                                      tooltip: '重新选择第${index + 1}张图片',
                                      onPressed: editor.mediaBusy
                                          ? null
                                          : () => controller.pickDraftPhotos(
                                              editor,
                                              replaceIndex: index,
                                            ),
                                      icon: const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                      foregroundColor: Colors.white,
                                    ),
                                    tooltip: '移除第${index + 1}张图片',
                                    onPressed: editor.mediaBusy
                                        ? null
                                        : () {
                                            editor.images.removeAt(index);
                                            editor.mediaTouched = true;
                                            onChanged();
                                          },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      return LongPressDraggable<String>(
                        data: image.mediaId,
                        maxSimultaneousDrags: editor.mediaBusy ? 0 : 1,
                        feedback: Material(
                          elevation: 4,
                          child: SizedBox(
                            width: width,
                            height: width,
                            child: IgnorePointer(child: tile),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: .35, child: tile),
                        child: tile,
                      );
                    },
                  ),
                if (editor.images.length < 9)
                  SizedBox(
                    width: width,
                    height: width,
                    child: Material(
                      color: PostTheme.cardTint,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        key: const ValueKey('post-add-images'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: editor.mediaBusy
                            ? null
                            : () => controller.pickDraftPhotos(editor),
                        child: const Center(
                          child: Tooltip(
                            message: '添加图片',
                            child: Icon(Icons.add, size: 32),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (editor.mediaBusy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('正在读取并保存所选图片…'),
          ),
        if (editor.mediaError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              editor.mediaError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

class _DraftPhotoPreview extends StatefulWidget {
  const _DraftPhotoPreview({required this.load, super.key});
  final Future<Uint8List> Function() load;
  @override
  State<_DraftPhotoPreview> createState() => _DraftPhotoPreviewState();
}

class _DraftPhotoPreviewState extends State<_DraftPhotoPreview> {
  MemoryImage? _provider;
  late final Future<MemoryImage> _future = () async {
    final bytes = await widget.load();
    if (!mounted) throw const PostStorageFailure();
    return _provider = MemoryImage(bytes);
  }();
  @override
  void dispose() {
    final provider = _provider;
    if (provider != null) unawaited(provider.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MemoryImage>(
    future: _future,
    builder: (context, state) {
      if (state.hasData) {
        return Image(
          image: state.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        );
      }
      return Center(
        child: Icon(
          state.hasError ? Icons.broken_image_outlined : Icons.image_outlined,
        ),
      );
    },
  );
}

class _PostImageUploadStatus extends StatelessWidget {
  const _PostImageUploadStatus({required this.controller, required this.item});
  final PostController controller;
  final PersonalPostItem item;
  @override
  Widget build(BuildContext context) {
    final progress = controller.imageUploadProgress(item.id);
    final total = (item.local!.data['images'] as List).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          progress?.message ??
              (progress?.busy == true
                  ? '图片上传：${progress!.completed}/${progress.total}'
                  : '图片上传状态会先与服务端核对。'),
        ),
        if (progress?.failed.isNotEmpty == true)
          Text('待补传：${progress!.failed.map((i) => i + 1).join('、')}'),
        if (progress?.busy != true)
          OutlinedButton(
            onPressed: () => controller.resumeImageUpload(item.id),
            child: Text('继续上传（${progress?.completed ?? 0}/$total）'),
          ),
      ],
    );
  }
}
