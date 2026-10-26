part of 'dm_runtime.dart';

Future<void> showDmManagement(
  BuildContext context,
  DmController c,
  Map<String, dynamic> directory,
) async {
  final scope = c.scope;
  final action = await showModalBottomSheet<String>(
    context: context,
    barrierColor: Colors.transparent,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              directory['note']?.toString().isNotEmpty == true
                  ? directory['note']
                  : directory['peerName'],
            ),
            subtitle: const Text('仅管理本人这段会话'),
          ),
          for (final option in [
            (
              'pin',
              directory['pinned'] == true ? '取消置顶' : '置顶',
              Icons.push_pin_outlined,
            ),
            (
              'mute',
              directory['muted'] == true ? '取消免打扰' : '免打扰',
              Icons.notifications_off_outlined,
            ),
            ('note', '私人备注', Icons.edit_note),
            ('hide', '不显示', Icons.visibility_off_outlined),
            ('delete', '删除聊天', Icons.delete_outline),
            (
              'block',
              (directory['ownBlockId'] as String?)?.isNotEmpty == true
                  ? '解除拉黑'
                  : '拉黑',
              Icons.block_outlined,
            ),
            ('report', '举报', Icons.flag_outlined),
          ])
            ListTile(
              key: ValueKey('dm-manage-${option.$1}'),
              leading: Icon(option.$3),
              title: Text(option.$2),
              onTap: () => Navigator.pop(context, option.$1),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || !c.available || scope != c.scope || action == null) {
    return;
  }
  if (action == 'note') {
    final text = TextEditingController(
      text: directory['note'] as String? ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('私人备注'),
        content: TextField(
          key: const ValueKey('dm-note-input'),
          controller: text,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '仅本人可见，留空清除'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog transition may still reference its controller for a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    if (value != null && context.mounted && c.scope == scope && c.available) {
      await c.manage(directory, 'SETTINGS', note: value);
    }
    return;
  }
  if (action == 'block') {
    await showDmBlock(context, c, directory);
    return;
  }
  if (action == 'report') {
    await openDmReport(context, c, directory);
    return;
  }
  if (action == 'hide' || action == 'delete') {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      barrierColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              action == 'hide' ? '不显示这段会话？' : '删除本人聊天记录？',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              action == 'hide'
                  ? '记录和备注保留，新消息或搜索打开后恢复显示。'
                  : '清除本人当前已看到的历史和草稿，保留备注；对方记录不受影响。',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action == 'hide' ? '不显示' : '删除聊天'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        scope != c.scope ||
        !c.available) {
      return;
    }
    await c.manage(directory, action == 'hide' ? 'HIDE' : 'DELETE');
    return;
  }
  await c.manage(
    directory,
    'SETTINGS',
    pinned: action == 'pin' ? directory['pinned'] != true : null,
    muted: action == 'mute' ? directory['muted'] != true : null,
  );
}

extension _ChatPhotoUi on _DmChatRouteState {
  Future<List<DmImage>> _pickChatImages() async {
    final expected = scope;
    final limit = 9 - _draftImages.length;
    if (limit < 1) return [];
    final files = await _picker.pick(limit);
    if (!mounted || c.scope != expected || !c.available) return [];
    final selected = <DmImage>[];
    for (final file in files.take(9)) {
      final id = dmId();
      try {
        final inspected = await inspectPostPhoto(file, id);
        if (!mounted || c.scope != expected || !c.available) break;
        await c.savePhoto(
          widget.own.id,
          widget.peer.id,
          inspected.selection.toJson(),
          inspected.bytes,
        );
        if (!mounted || c.scope != expected) break;
        final image = DmImage(id: id, description: '待发送图片');
        _draftImages.add(image);
        selected.add(image);
      } catch (_) {
        if (mounted && c.scope == expected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('部分图片无法保存或超过格式/大小限制，请重选或移除')),
          );
        }
      }
    }
    return selected;
  }

  Map<String, dynamic>? _imageData(String id) {
    final row = rows.where((r) => r['_id'] == id).firstOrNull;
    if (row == null) return null;
    return row['outgoing'] == true
        ? Map<String, dynamic>.from(row['intent'])
        : {
            ...Map<String, dynamic>.from(row['media'] ?? {}),
            'groupId': row['groupId'],
            'position': row['position'],
            'groupSize': row['groupSize'],
          };
  }

  Future<Uint8List> _photoBytes(String id) =>
      _photoRequests.putIfAbsent(id, () async {
        final mediaId = _imageData(id)?['mediaId'] as String? ?? id;
        final row = rows.where((r) => r['_id'] == id).firstOrNull;
        final sender = row?['outgoing'] == false
            ? row!['senderId'] as String
            : widget.own.id;
        final bytes = await c.photo(mediaId, senderId: sender);
        if (!mounted || scope != c.scope || !c.available) {
          throw StateError('Photo window expired');
        }
        return bytes;
      });

  Widget _photoWidget(
    BuildContext context,
    DmImage image,
  ) => FutureBuilder<Uint8List>(
    future: _photoBytes(image.id),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Icon(Icons.broken_image_outlined, semanticLabel: '本地图片暂时不可用'),
        );
      }
      final data = snapshot.data;
      if (data == null) return const Center(child: CircularProgressIndicator());
      final provider = _photoProviders.putIfAbsent(
        image.id,
        () => MemoryImage(data),
      );
      return Image(
        image: provider,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      );
    },
  );

  void _releasePhotos() {
    _viewer?.invalidateAccess();
    for (final provider in _photoProviders.values) {
      unawaited(provider.evict());
    }
    _photoProviders.clear();
    _photoRequests.clear();
  }

  Future<void> _openPhoto(DmImage image) async {
    if (_viewer != null || scope != c.scope || !c.available) return;
    final row = rows.where((r) => r['_id'] == image.id).firstOrNull;
    final data = _imageData(image.id);
    if (data == null || row == null || row['recalled'] == true) return;
    final group = rows
        .where(
          (r) =>
              r['recalled'] != true &&
              r['messageType'] == 'IMAGE' &&
              (r['outgoing'] == true
                      ? (r['intent'] as Map)['groupId']
                      : r['groupId']) ==
                  data['groupId'] &&
              r['outgoing'] == row['outgoing'],
        )
        .toList();
    group.sort(
      (a, b) =>
          ((a['outgoing'] == true
                      ? (a['intent'] as Map)['position']
                      : a['position'])
                  as int)
              .compareTo(
                (b['outgoing'] == true
                        ? (b['intent'] as Map)['position']
                        : b['position'])
                    as int,
              ),
    );
    final viewer = ViewerController(
      items: [
        for (final r in group)
          ViewerItem(
            id: r['_id'],
            saveAllowed: false,
            loadSource: () async {
              final bytes = await _photoBytes(r['_id']);
              if (scope != c.scope ||
                  !c.available ||
                  !rows.any(
                    (v) => v['_id'] == r['_id'] && v['recalled'] != true,
                  )) {
                throw StateError('Photo unavailable');
              }
              final codec = await ui.instantiateImageCodec(bytes);
              try {
                final frame = await codec.getNextFrame();
                try {
                  return ViewerSource(
                    provider: _photoProviders.putIfAbsent(
                      r['_id'],
                      () => MemoryImage(bytes),
                    ),
                    pixelSize: Size(
                      frame.image.width.toDouble(),
                      frame.image.height.toDouble(),
                    ),
                  );
                } finally {
                  frame.image.dispose();
                }
              } finally {
                codec.dispose();
              }
            },
          ),
      ],
      initialIndex: group.indexWhere((r) => r['_id'] == image.id),
    );
    _viewer = viewer;
    final nav = Navigator.of(context);
    late HnuImageViewerRoute route;
    route = HnuImageViewerRoute(
      builder: (_) => HnuImageViewer(
        controller: viewer,
        onClosed: (_) {
          if (route.isCurrent) {
            nav.pop();
          } else if (route.isActive) {
            nav.removeRoute(route);
          }
        },
      ),
    );
    try {
      await nav.push(route);
    } finally {
      if (identical(_viewer, viewer)) _viewer = null;
      viewer.dispose();
    }
  }

  List<DmMessage> _chatMessages() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final data = row['outgoing'] == true ? row['intent'] as Map : row;
      final group = row['messageType'] == 'IMAGE' && row['recalled'] != true
          ? '${row['outgoing']}:${data['groupId']}'
          : row['_id'] as String;
      (groups[group] ??= []).add(row);
    }
    final result = <DmMessage>[];
    for (final group in groups.values) {
      group.sort(
        (a, b) =>
            ((a['outgoing'] == true
                            ? (a['intent'] as Map)['position']
                            : a['position'])
                        as int? ??
                    0)
                .compareTo(
                  (b['outgoing'] == true
                              ? (b['intent'] as Map)['position']
                              : b['position'])
                          as int? ??
                      0,
                ),
      );
      final r = group.first, outgoing = r['outgoing'] == true;
      final data = outgoing ? Map<String, dynamic>.from(r['intent'] as Map) : r;
      final receipt = r['receipt'] as Map?;
      final date = DateTime.tryParse(
        (outgoing ? (receipt?['acceptedAt']) : r['acceptedAt']) as String? ??
            '',
      )?.toLocal();
      bool recall(Map<String, dynamic> v) {
        final accepted = DateTime.tryParse(
          ((v['receipt'] as Map?)?['acceptedAt']) as String? ?? '',
        );
        return v['outgoing'] == true &&
            v['_state'] == 'sent' &&
            accepted != null &&
            DateTime.now().toUtc().isBefore(
              accepted.add(const Duration(minutes: 2)),
            );
      }

      final images = r['messageType'] == 'IMAGE' && r['recalled'] != true
          ? [
              for (final image in group)
                DmImage(
                  id: image['_id'],
                  description:
                      '第${((image['outgoing'] == true ? (image['intent'] as Map)['position'] : image['position']) as int) + 1}张图片',
                  state: _sendState(image['_state']),
                  canRecall: recall(image),
                ),
            ]
          : <DmImage>[];
      final until = DateTime.tryParse(r['reeditUntil'] as String? ?? '');
      result.add(
        DmMessage(
          id: images.isNotEmpty ? 'group:${data['groupId']}' : r['_id'],
          outgoing: outgoing,
          text: data['text'] as String? ?? '',
          images: images,
          state: images.isNotEmpty ? DmSendState.sent : _sendState(r['_state']),
          recalled: r['recalled'] == true,
          canRecall: group.any(recall),
          reeditableText:
              outgoing &&
                  until != null &&
                  DateTime.now().toUtc().isBefore(until)
              ? r['reeditText'] as String?
              : null,
          time: date == null
              ? ''
              : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
          dayLabel: date == null ? '' : '${date.month}月${date.day}日',
          visibleMessageIds: group.map((v) => v['_id'] as String).toList(),
        ),
      );
    }
    return result;
  }

  DmSendState _sendState(Object? state) => switch (state) {
    'queued' => DmSendState.sending,
    'unknown' => DmSendState.unknown,
    'failed' => DmSendState.failed,
    _ => DmSendState.sent,
  };

  Future<void> _chatMessageAction(
    DmMessageTarget target,
    DmMessageAction action,
    Map<String, dynamic>? directory,
  ) async {
    final id = target.imageId ?? target.messageId;
    if (scope != c.scope || !c.available) return;
    if (action == DmMessageAction.report && directory != null) {
      await openDmReport(context, c, directory);
      return;
    }
    if (action == DmMessageAction.delete) {
      await c.deleteLocal(id);
      _releasePhotos();
      return;
    }
    if (action == DmMessageAction.retry) {
      await c.retry(id);
      return;
    }
    if (action == DmMessageAction.recall && directory != null) {
      final row = await c.message(id);
      if (row == null ||
          scope != c.scope ||
          row['outgoing'] != true ||
          row['_state'] != 'sent') {
        return;
      }
      final serverId = (row['receipt'] as Map)['messageId'] as String;
      await c.manage(directory, 'RETRACT', messageId: serverId);
      _releasePhotos();
    }
  }
}
