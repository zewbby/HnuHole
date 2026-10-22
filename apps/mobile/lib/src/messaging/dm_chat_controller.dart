part of 'dm_controller.dart';

extension DmChatController on DmController {
  Future<void> _chatBeforeSync(int epoch, DmStore store, String token) async {
    await store.expireReedit();
    for (final row in await store.operations()) {
      final path = 'chat/operations/${row['_id']}';
      Map<String, dynamic> receipt;
      try {
        receipt = await _request(epoch, token, 'GET', path);
        if (receipt['state'] == 'ABSENT') {
          receipt = await _request(
            epoch,
            token,
            'PUT',
            path,
            body: Map<String, Object>.from(row['intent'] as Map),
          );
        }
      } on PostFailure catch (e) {
        if (e.kind != PostFailureKind.rejected ||
            !{400, 403, 409}.contains(e.statusCode)) {
          rethrow;
        }
        receipt = {
          'state': 'REJECTED',
          'errorCode': e.code ?? 'COMMAND_CONFLICT',
        };
      }
      if (!_current(epoch)) return;
      if (!{'APPLIED', 'REJECTED'}.contains(receipt['state'])) {
        throw const FormatException('Incomplete DM operation');
      }
      await store.finishOperation(row['_id'], receipt);
      if (receipt['state'] == 'REJECTED') {
        _operationError =
            '操作未完成：${receipt['errorCode'] == 'VERSION_CONFLICT' ? '会话已更新，请重新操作' : '请刷新后重试'}';
      }
    }
    await _chatControls(epoch, store, token);
    for (final identity in _identities) {
      var after = '';
      while (_current(epoch)) {
        final page = await _request(
          epoch,
          token,
          'GET',
          'chat/conversations',
          query: {'identityId': identity, if (after.isNotEmpty) 'after': after},
        );
        final rows = (page['items'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        if (rows.any((r) => r['identityId'] != identity)) {
          throw const FormatException('Wrong DM identity');
        }
        if (!_current(epoch)) return;
        await store.saveChatConversations(rows);
        if (rows.length < 100) break;
        final next = rows.last['id'] as String;
        if (next.compareTo(after) <= 0) {
          throw const FormatException('DM directory stalled');
        }
        after = next;
      }
    }
  }

  Future<void> _chatControls(int epoch, DmStore store, String token) async {
    while (_current(epoch)) {
      final cursor = await store.controlCursor();
      final page = await _request(
        epoch,
        token,
        'GET',
        'chat/controls',
        query: {'after': '$cursor'},
      );
      final items = (page['items'] as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      if (items.any((v) => !_identities.contains(v['identityId']))) {
        throw const FormatException('Wrong control identity');
      }
      if (!_current(epoch)) return;
      await store.applyControls(items, page['next']);
      if (items.length < 100) break;
      if (page['next'] <= cursor) {
        throw const FormatException('DM controls stalled');
      }
    }
  }

  Future<void> manage(
    Map<String, dynamic> directory,
    String operation, {
    bool? pinned,
    bool? muted,
    String? note,
    String? messageId,
  }) async {
    if (!available ||
        !chatEnabled ||
        !_identities.contains(directory['identityId']) ||
        directory['localOnly'] == true) {
      return;
    }
    final epoch = _epoch;
    try {
      await _store!.enqueueOperation({
        'identityId': directory['identityId'],
        'conversationId': directory['id'],
        'operation': operation,
        'expectedVersion': directory['settingsVersion'] ?? 0,
        if (operation == 'SETTINGS') ...{
          'pinned': pinned ?? directory['pinned'] ?? false,
          'muted': muted ?? directory['muted'] ?? false,
          'note': note ?? directory['note'] ?? '',
        },
        if (operation == 'DELETE') 'throughSequence': directory['sequence'],
        if (messageId != null) 'messageId': messageId,
      });
      if (!_current(epoch)) return;
      _notify();
      await sync();
    } catch (_) {
      if (_current(epoch)) {
        error = '操作尚未保存，请重试';
        _notify();
      }
    }
  }

  Future<bool> sendPhotos(
    Map<String, Object> intent,
    List<String> mediaIds,
  ) async {
    if (!available ||
        !chatEnabled ||
        !_identities.contains(intent['identityId'])) {
      return false;
    }
    final epoch = _epoch;
    try {
      await _store!.enqueueChat(intent, mediaIds);
      if (!_current(epoch)) return false;
      try {
        await _refreshDirectory(epoch, _store!);
      } catch (_) {}
      _notify();
      unawaited(sync());
      return true;
    } catch (_) {
      if (_current(epoch)) {
        error = '图片尚未可靠保存，请保留选择后重试';
        _notify();
      }
      return false;
    }
  }

  Future<void> savePhoto(
    String own,
    String peer,
    Map<String, dynamic> descriptor,
    Uint8List bytes,
  ) async {
    if (!available || !chatEnabled || !_identities.contains(own)) {
      throw StateError('DM unavailable');
    }
    final epoch = _epoch;
    await _store!.savePhotoDraft(own, peer, descriptor, bytes);
    if (!_current(epoch)) throw StateError('DM window expired');
  }

  Future<List<Map<String, dynamic>>> photoDraft(String own, String peer) async {
    if (!available || !chatEnabled || !_identities.contains(own)) return [];
    final epoch = _epoch, store = _store!;
    final rows = await store.photoDraft(own, peer);
    return _current(epoch) ? rows : [];
  }

  Future<Uint8List> photo(String id) async {
    if (!available || !chatEnabled) throw StateError('DM unavailable');
    final epoch = _epoch;
    final bytes = await _store!.photo(id);
    if (!_current(epoch)) throw StateError('DM window expired');
    return bytes;
  }

  Future<void> removePhoto(String own, String peer, String id) async {
    if (!available || !chatEnabled || !_identities.contains(own)) return;
    await _store!.removePhotoDraft(own, peer, id);
  }

  Future<void> deleteLocal(String id) async {
    if (!available || !chatEnabled) return;
    final epoch = _epoch;
    await _store!.hideMessage(id);
    if (_current(epoch)) {
      await _refreshDirectory(epoch, _store!);
      _notify();
    }
  }
}
