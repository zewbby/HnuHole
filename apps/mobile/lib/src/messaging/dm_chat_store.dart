part of 'dm_store.dart';

/// Photos use encrypted chunks in the same FULL SQLite transaction as their
/// references. No original or search index is written to a public cache/file.
extension DmChatStorage on DmStore {
  static const _chunkSize = 256 * 1024;

  Future<String> _mediaKey(String sender, String id) =>
      pairTag('private-media:$sender', id);

  Future<void> _deletePhoto(String sender, String id) async {
    _db.execute(
      "DELETE FROM dm_records WHERE kind IN ('media','media_meta') AND pair=?",
      [await _mediaKey(sender, id)],
    );
  }

  // P1 has no media. Old isolated P2 builds used account-wide media IDs;
  // migrate only bytes proven to match a reference, never a colliding image.
  Future<void> _migrateChatMedia() async {
    if (await _get('chat-media-layout') != null) return;
    final legacy = _db
        .select("SELECT pair FROM dm_records WHERE kind='media_meta'")
        .map((r) => r['pair'] as String)
        .toSet();
    if (legacy.isNotEmpty) {
      Future<void> copy(String sender, Map descriptor) async {
        final id = descriptor['mediaId'];
        if (id is! String || !legacy.contains(id)) return;
        try {
          final bytes = await _readPhoto(id);
          if (bytes.length == descriptor['byteLength'] &&
              hashes.sha256.convert(bytes).toString() == descriptor['sha256']) {
            await _writePhoto(await _mediaKey(sender, id), bytes);
          }
        } on PostStorageFailure {
          // A damaged or overwritten old image remains unavailable.
        }
      }

      for (final raw
          in _db
              .select(
                "SELECT * FROM dm_records WHERE kind IN ('message','hidden_message','photo_draft')",
              )
              .toList()) {
        final row = await _decode(raw);
        if (row['_kind'] == 'photo_draft') {
          final dir = await _get('conversation:${row['_pair']}');
          final sender = row['senderId'] ?? dir?['identityId'];
          if (sender is String) {
            for (final descriptor in row['photos'] as List? ?? []) {
              await copy(sender, descriptor as Map);
            }
          }
        } else {
          final intent = row['intent'] as Map?;
          final descriptor = row['outgoing'] == true
              ? intent
              : row['media'] as Map?;
          final sender = row['outgoing'] == true
              ? (intent?['identityId'])
              : row['senderId'];
          if (sender is String && descriptor != null) {
            await copy(sender, descriptor);
          }
        }
      }
      for (final key in legacy) {
        _db.execute(
          "DELETE FROM dm_records WHERE kind IN ('media','media_meta') AND pair=?",
          [key],
        );
      }
    }
    await _put('chat-media-layout', 'metadata', '', 0, 'saved', {'version': 2});
  }

  Future<void> _eraseMedia(Map<String, dynamic> row) async {
    final mediaId =
        ((row['intent'] as Map?)?['mediaId'] ??
                (row['media'] as Map?)?['mediaId'])
            as String?;
    if (mediaId != null) {
      final sender = row['outgoing'] == true
          ? ((row['intent'] as Map?)?['identityId'])
          : row['senderId'];
      if (sender is String) await _deletePhoto(sender, mediaId);
    }
  }

  Future<void> _eraseResolved(Map<String, dynamic> row) async {
    await _eraseMedia(row);
    await _put(
      row['_id'],
      'hidden_message',
      row['_pair'],
      row['_ordinal'],
      'deleted',
      {
        'outgoing': row['outgoing'],
        'sequence': row['sequence'] ?? (row['receipt'] as Map?)?['sequence'],
        'messageId': row['messageId'] ?? (row['receipt'] as Map?)?['messageId'],
        'conversationId':
            row['conversationId'] ??
            (row['receipt'] as Map?)?['conversationId'],
      },
    );
  }

  Future<void> eraseHiddenResolved(String id) => _run(
    () => _transaction(() async {
      final row = await _get(id);
      if (row?['_kind'] == 'hidden_message' &&
          !{'unknown', 'received', 'read_pending'}.contains(row?['_state'])) {
        await _eraseResolved(row!);
      }
    }),
  );
  Future<void> expireReedit() => _run(
    () => _transaction(() async {
      for (final raw
          in _db
              .select("SELECT * FROM dm_records WHERE state='retracted'")
              .toList()) {
        final row = await _decode(raw);
        final until = DateTime.tryParse(row['reeditUntil'] as String? ?? '');
        if (until != null && !DateTime.now().toUtc().isBefore(until)) {
          row.remove('reeditText');
          row.remove('reeditUntil');
          row['reeditExpired'] = true;
          await _put(
            raw['id'],
            raw['kind'],
            raw['pair'],
            raw['ordinal'],
            raw['state'],
            row,
          );
        }
      }
    }),
  );

  Future<void> enqueueOperation(Map<String, Object> operation) => _run(
    () => _transaction(() async {
      final id = dmId();
      Map<String, dynamic> snapshot = {};
      if (operation['operation'] == 'DELETE') {
        for (final raw in _db.select(
          "SELECT * FROM dm_records WHERE kind='conversation'",
        )) {
          final dir = await _decode(raw);
          if (dir['id'] != operation['conversationId'] ||
              dir['identityId'] != operation['identityId']) {
            continue;
          }
          final draft = await _get('draft:${raw['pair']}');
          final photos = await _get('photo-draft:${raw['pair']}');
          snapshot = {
            'draftRevision': draft?['revision'] ?? 0,
            'draftPresent': draft != null,
            'draftPhotoIds': [
              for (final p in photos?['photos'] as List? ?? []) p['mediaId'],
            ],
          };
          break;
        }
      }
      await _put(id, 'operation', '', _nextOrdinal(), 'unknown', {
        'intent': operation,
        ...snapshot,
      });
    }),
  );
  Future<List<Map<String, dynamic>>> operations() => _run(
    () async => Future.wait(
      _db
          .select(
            "SELECT * FROM dm_records WHERE kind='operation' AND state='unknown' ORDER BY ordinal LIMIT 100",
          )
          .map(_decode),
    ),
  );
  Future<void> finishOperation(String id, Map<String, dynamic> receipt) => _run(
    () => _transaction(() async {
      final row = await _get(id);
      if (row == null || row['_state'] != 'unknown') return;
      await _put(
        id,
        'operation',
        '',
        row['_ordinal'],
        receipt['state'] == 'APPLIED' ? 'applied' : 'rejected',
        {...row, 'receipt': receipt},
      );
      if (receipt['state'] == 'APPLIED' &&
          (row['intent'] as Map)['operation'] == 'DELETE') {
        final intent = Map<String, dynamic>.from(row['intent']);
        for (final r
            in _db
                .select("SELECT * FROM dm_records WHERE kind='conversation'")
                .toList()) {
          final dir = await _decode(r);
          if (dir['id'] == intent['conversationId'] &&
              dir['identityId'] == intent['identityId']) {
            dir['deletedThrough'] = max(
              (dir['deletedThrough'] as int?) ?? 0,
              receipt['deletedThrough'] as int,
            );
            dir['deleted'] =
                (dir['sequence'] as int) <= (dir['deletedThrough'] as int);
            dir['version'] = max(
              (dir['version'] as int?) ?? 0,
              receipt['version'] as int,
            );
            await _put(r['id'], 'conversation', r['pair'], 0, 'directory', dir);
            await _pruneDeleted(r['pair'], dir['deletedThrough']);
            for (final queued in _db.select(
              "SELECT * FROM dm_records WHERE pair=? AND kind='message' AND state IN ('queued','unknown') AND ordinal<?",
              [r['pair'], row['_ordinal']],
            ).toList()) {
              final data = await _decode(queued);
              if (queued['state'] == 'unknown') {
                await _hidePending(data);
              } else {
                await _eraseResolved(data);
              }
            }
            final draftPhotos = await _get('photo-draft:${r['pair']}');
            final removed = (row['draftPhotoIds'] as List? ?? []).toSet();
            final retained = <dynamic>[];
            for (final photo in draftPhotos?['photos'] as List? ?? []) {
              if (removed.contains(photo['mediaId'])) {
                await _deletePhoto(intent['identityId'], photo['mediaId']);
              } else {
                retained.add(photo);
              }
            }
            if (draftPhotos != null) {
              await _put(
                'photo-draft:${r['pair']}',
                'photo_draft',
                r['pair'],
                0,
                'draft',
                {...draftPhotos, 'photos': retained},
              );
            }
            final draft = await _get('draft:${r['pair']}');
            if (row['draftPresent'] == true &&
                draft != null &&
                (draft['revision'] ?? 0) == row['draftRevision']) {
              await _put('draft:${r['pair']}', 'draft', r['pair'], 0, 'draft', {
                'identityId': intent['identityId'],
                'text': '',
                'revision': (draft['revision'] as int? ?? 0) + 1,
              });
            }
          }
        }
      }
    }),
  );

  Future<void> _pruneDeleted(String pair, int through) async {
    if (through < 1) return;
    for (final r in _db.select(
      "SELECT * FROM dm_records WHERE pair=? AND kind IN ('message','hidden_message')",
      [pair],
    ).toList()) {
      final data = await _decode(r);
      final seq = data['outgoing'] == true
          ? ((data['receipt'] as Map?)?['sequence'])
          : data['sequence'];
      if (seq is int && seq <= through) {
        await _eraseMedia(data);
        // Persist a minimum dedup tombstone so a late delivery is never revived.
        await _put(r['id'], 'hidden_message', pair, r['ordinal'], 'deleted', {
          'sequence': seq,
          'outgoing': data['outgoing'],
          'conversationId':
              data['conversationId'] ??
              (data['receipt'] as Map?)?['conversationId'],
        });
      }
    }
  }

  Future<void> saveChatConversations(List<Map<String, dynamic>> items) => _run(
    () => _transaction(() async {
      for (final item in items) {
        final pair = await pairTag(item['identityId'], item['peerId']);
        final old = await _get('conversation:$pair');
        if (((old?['version'] as int?) ?? -1) > (item['version'] as int)) {
          continue;
        }
        final merged = {
          ...item,
          'deletedThrough': max(
            (old?['deletedThrough'] as int?) ?? 0,
            item['deletedThrough'] as int,
          ),
        };
        merged['deleted'] =
            (item['sequence'] as int) <= (merged['deletedThrough'] as int);
        await _put(
          'conversation:$pair',
          'conversation',
          pair,
          0,
          'directory',
          merged,
        );
        await _pruneDeleted(pair, merged['deletedThrough']);
      }
    }),
  );

  Future<void> enforceDeleteFor(String id) => _run(
    () => _transaction(() async {
      final row = await _get(id);
      if (row == null) return;
      final dir = await _get('conversation:${row['_pair']}');
      if (dir != null) {
        await _pruneDeleted(row['_pair'], (dir['deletedThrough'] as int?) ?? 0);
      }
    }),
  );

  Future<bool> deliverySuppressed(Map<String, dynamic> item) => _run(() async {
    if (await _get('retracted:${item['messageId']}') != null) return true;
    final pair = await pairTag(item['identityId'], item['senderId']);
    final dir = await _get('conversation:$pair');
    return (item['sequence'] as int) <= ((dir?['deletedThrough'] as int?) ?? 0);
  });

  Future<int> controlCursor() =>
      _run(() async => ((await _get('control-cursor'))?['next'] as int?) ?? 0);
  Future<bool> isRetracted(String id) =>
      _run(() async => await _get('retracted:$id') != null);
  Future<void> applyControls(List<Map<String, dynamic>> items, int next) =>
      _run(
        () => _transaction(() async {
          final previous =
              ((await _get('control-cursor'))?['next'] as int?) ?? 0;
          if (next < previous) throw const PostStorageFailure();
          for (final event in items) {
            await _put(
              'retracted:${event['messageId']}',
              'control',
              '',
              0,
              'retracted',
              event,
            );
            // Outgoing rows use the command ID locally, incoming rows use message ID.
            for (final r
                in _db
                    .select(
                      "SELECT * FROM dm_records WHERE kind IN ('message','hidden_message')",
                    )
                    .toList()) {
              final row = await _decode(r);
              final serverId = row['outgoing'] == true
                  ? ((row['receipt'] as Map?)?['messageId'])
                  : row['messageId'];
              if (serverId != event['messageId']) continue;
              final intent = row['intent'] as Map?;
              final text =
                  (row['outgoing'] == true ? (intent?['text']) : row['text'])
                      as String?;
              await _eraseMedia(row);
              if (row['outgoing'] == true &&
                  text != null &&
                  row['reeditExpired'] != true &&
                  row['reeditUntil'] == null) {
                row['reeditText'] = text;
                row['reeditUntil'] = DateTime.parse(event['createdAt'])
                    .add(const Duration(hours: 24))
                    .toUtc()
                    .toIso8601String();
              }
              row['recalled'] = true;
              row['text'] = '';
              row.remove('media');
              if (intent != null) {
                row['intent'] = {...intent, 'text': ''}..remove('mediaId');
              }
              await _put(
                r['id'],
                r['kind'],
                r['pair'],
                r['ordinal'],
                'retracted',
                row,
              );
            }
          }
          await _put('control-cursor', 'control_cursor', '', 0, 'saved', {
            'next': next,
          });
        }),
      );

  Future<void> _writePhoto(String id, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const PostStorageFailure();
    }
    for (
      var offset = 0, chunk = 0;
      offset < bytes.length;
      offset += _chunkSize, chunk++
    ) {
      await _put('media:$id:$chunk', 'media', id, 0, 'saved', {
        'bytes': base64Encode(
          bytes.sublist(offset, min(offset + _chunkSize, bytes.length)),
        ),
      });
    }
    await _put('media:$id', 'media_meta', id, 0, 'saved', {
      'length': bytes.length,
      'sha256': hashes.sha256.convert(bytes).toString(),
      'chunks': (bytes.length / _chunkSize).ceil(),
    });
  }

  Future<Uint8List> _readPhoto(String id) async {
    final meta = await _get('media:$id');
    if (meta == null) throw const PostStorageFailure();
    final bytes = BytesBuilder(copy: false);
    for (var i = 0; i < (meta['chunks'] as int); i++) {
      final chunk = await _get('media:$id:$i');
      if (chunk == null) throw const PostStorageFailure();
      bytes.add(base64Decode(chunk['bytes'] as String));
    }
    final value = bytes.takeBytes();
    if (value.length != meta['length'] ||
        hashes.sha256.convert(value).toString() != meta['sha256']) {
      throw const PostStorageFailure();
    }
    return value;
  }

  Future<Uint8List> photo(String id, {required String senderId}) =>
      _run(() async => _readPhoto(await _mediaKey(senderId, id)));

  Future<void> savePhotoDraft(
    String own,
    String peer,
    Map<String, dynamic> descriptor,
    Uint8List bytes,
  ) => _run(
    () => _transaction(() async {
      final pair = await pairTag(own, peer);
      await _requireIdentity(own);
      final id = descriptor['mediaId'] as String;
      final record = await _get('photo-draft:$pair');
      final photos = (record?['photos'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (photos.length >= 9 ||
          photos.any((p) => p['mediaId'] == id) ||
          descriptor['sha256'] != hashes.sha256.convert(bytes).toString() ||
          descriptor['byteLength'] != bytes.length) {
        throw const PostStorageFailure();
      }
      await _writePhoto(await _mediaKey(own, id), bytes);
      photos.add(descriptor);
      await _put('photo-draft:$pair', 'photo_draft', pair, 0, 'draft', {
        'photos': photos,
        'senderId': own,
      });
    }),
  );

  Future<List<Map<String, dynamic>>> photoDraft(String own, String peer) =>
      _run(() async {
        final row = await _get('photo-draft:${await pairTag(own, peer)}');
        return (row?['photos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });

  Future<Map<String, dynamic>> draftState(String own, String peer) =>
      _run(() async {
        final pair = await pairTag(own, peer);
        final text = await _get('draft:$pair');
        final photos = await _get('photo-draft:$pair');
        return {
          'text': text?['text'] ?? '',
          'revision': text?['revision'] ?? 0,
          'photos': photos?['photos'] ?? <dynamic>[],
        };
      });

  Future<void> removePhotoDraft(String own, String peer, String id) => _run(
    () => _transaction(() async {
      final pair = await pairTag(own, peer), key = 'photo-draft:$pair';
      final row = await _get(key);
      if (row == null) return;
      final photos = (row['photos'] as List)
          .where((p) => p['mediaId'] != id)
          .toList();
      await _put(key, 'photo_draft', pair, 0, 'draft', {
        'photos': photos,
        'senderId': own,
      });
      await _deletePhoto(own, id);
    }),
  );

  Future<void> hideMessage(String id) => _run(
    () => _transaction(() async {
      final row = await _get(id);
      if (row == null) return;
      if (!{'unknown', 'received', 'read_pending'}.contains(row['_state'])) {
        await _eraseResolved(row);
        return;
      }
      await _hidePending(row);
    }),
  );

  Future<void> _hidePending(Map<String, dynamic> row) async {
    await _eraseMedia(row);
    final intent = row['intent'] as Map?;
    await _put(
      row['_id'],
      'hidden_message',
      row['_pair'],
      row['_ordinal'],
      row['_state'],
      {
        'outgoing': row['outgoing'],
        if (intent != null)
          'intent': {
            for (final key in [
              'identityId',
              'peerId',
              'conversationId',
              'attempt',
            ])
              if (intent.containsKey(key)) key: intent[key],
          },
        for (final key in [
          'messageId',
          'sequence',
          'conversationId',
          'identityId',
          'senderId',
          'receipt',
        ])
          if (row.containsKey(key)) key: row[key],
      },
    );
  }

  Future<void> enqueueChat(
    Map<String, Object> textIntent,
    List<String> mediaIds,
  ) => _run(
    () => _transaction(() async {
      if (mediaIds.isEmpty ||
          mediaIds.length > 9 ||
          mediaIds.toSet().length != mediaIds.length ||
          textIntent['conversationId'] == '') {
        throw const PostStorageFailure();
      }
      final own = textIntent['identityId'] as String,
          peer = textIntent['peerId'] as String;
      final pair = await pairTag(own, peer);
      final draft = await _get('photo-draft:$pair');
      final photos = (draft?['photos'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      final selected = <Map<String, dynamic>>[];
      for (final id in mediaIds) {
        final p = photos.where((p) => p['mediaId'] == id).firstOrNull;
        if (p == null) throw const PostStorageFailure();
        await _readPhoto(
          await _mediaKey(own, id),
        ); // Validate durable originals before clearing UI.
        selected.add(p);
      }
      final text = textIntent['text'] as String;
      _checkQueueCapacity(selected.length + (text.trim().isEmpty ? 0 : 1));
      if (text.trim().isNotEmpty) {
        if (!dmValidText(text)) throw const PostStorageFailure();
        await _put(dmId(), 'message', pair, _nextOrdinal(), 'queued', {
          'intent': textIntent,
          'outgoing': true,
        });
      }
      final group = dmId();
      for (var i = 0; i < selected.length; i++) {
        await _put(dmId(), 'message', pair, _nextOrdinal(), 'queued', {
          'outgoing': true,
          'messageType': 'IMAGE',
          'intent': {
            'identityId': own,
            'peerId': peer,
            'conversationId': textIntent['conversationId'],
            'groupId': group,
            'position': i,
            'groupSize': selected.length,
            ...selected[i],
            'attempt': 1,
          },
        });
      }
      await _put('photo-draft:$pair', 'photo_draft', pair, 0, 'draft', {
        'photos': photos
            .where((p) => !mediaIds.contains(p['mediaId']))
            .toList(),
        'senderId': own,
      });
      final textDraft = await _get('draft:$pair');
      if (textDraft?['text'] == text) {
        await _put('draft:$pair', 'draft', pair, 0, 'draft', {
          'identityId': own,
          'text': '',
          'revision': (textDraft?['revision'] as int? ?? 0) + 1,
        });
      }
    }),
  );

  Future<void> receivePhoto(Map<String, dynamic> item, Uint8List bytes) => _run(
    () => _transaction(() async {
      await _requireIdentity(item['identityId']);
      final descriptor = Map<String, dynamic>.from(item['media']);
      if (bytes.length != descriptor['byteLength'] ||
          hashes.sha256.convert(bytes).toString() != descriptor['sha256']) {
        throw const PostStorageFailure();
      }
      final id = item['messageId'] as String;
      final old = await _get(id);
      if (old != null) {
        for (final k in [
          'conversationId',
          'identityId',
          'senderId',
          'sequence',
          'groupId',
          'position',
          'groupSize',
        ]) {
          if (old[k] != item[k]) throw const PostStorageFailure();
        }
        return;
      }
      final pair = await pairTag(item['identityId'], item['senderId']);
      // Suppression and durable bytes/reference commit share this transaction.
      if (await _get('retracted:$id') != null) return;
      final directory = await _get('conversation:$pair');
      if ((item['sequence'] as int) <=
          ((directory?['deletedThrough'] as int?) ?? 0)) {
        return;
      }
      await _writePhoto(
        await _mediaKey(item['senderId'], descriptor['mediaId']),
        bytes,
      );
      await _put(id, 'message', pair, _nextOrdinal(), 'received', {
        ...item,
        'outgoing': false,
        'messageType': 'IMAGE',
      });
      final key = 'conversation:$pair';
      final dir =
          await _get(key) ??
          <String, dynamic>{
            'peerName': '匿名身份',
            'sourcePostId': '',
            'unread': 0,
            'canSend': true,
          };
      final seq = (dir['sequence'] as int?) ?? 0;
      dir.addAll({
        'id': item['conversationId'],
        'identityId': item['identityId'],
        'peerId': item['senderId'],
        'localOnly': false,
        'sequence': max(seq, item['sequence'] as int),
        'waiting': false,
        'unread':
            (dir['unread'] as int) + ((item['sequence'] as int) > seq ? 1 : 0),
      });
      await _put(key, 'conversation', pair, 0, 'directory', dir);
    }),
  );

  Future<String> searchText(String own, String peer) => _run(() async {
    final pair = await pairTag(own, peer);
    final texts = <String>[];
    for (final row in _db.select(
      "SELECT * FROM dm_records WHERE kind='message' AND pair=? ORDER BY sort_key",
      [pair],
    )) {
      final data = await _decode(row);
      if (data['recalled'] == true) continue;
      final text = data['outgoing'] == true
          ? (data['intent'] as Map)['text']
          : data['text'];
      if (text is String && text.isNotEmpty) texts.add(text);
    }
    return texts.join('\n');
  });
}
