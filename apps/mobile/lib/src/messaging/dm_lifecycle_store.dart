part of 'dm_store.dart';

extension DmLifecycleStorage on DmStore {
  String? _recordOwner(String kind, Map<String, dynamic> row) {
    final owner =
        row['identityId'] ??
        (row['intent'] as Map?)?['identityId'] ??
        (kind == 'photo_draft' ? row['senderId'] : null);
    return owner is String ? owner : null;
  }

  Future<void> _requireIdentity(String identity) async {
    if (await _get('account-closed') != null) throw const PostStorageFailure();
    final directory = await _get('identity-directory');
    if (directory != null &&
        !(directory['active'] as List).contains(identity)) {
      throw const PostStorageFailure();
    }
  }

  /// Called only with the complete, authenticated identity directory, never a
  /// partial page or a failed fetch. Removal and media GC are one transaction.
  Future<void> reconcileIdentities(List<String> active) => _run(
    () => _transaction(() async {
      final previous = await _get('identity-directory');
      final removed = (previous?['removed'] as List? ?? [])
          .cast<String>()
          .toSet();
      final allowed = active.toSet()..removeAll(removed);
      final rows = <Map<String, dynamic>>[];
      final owners = <String, String>{};
      for (final raw in _db.select(
        "SELECT * FROM dm_records WHERE kind NOT IN ('media','media_meta')",
      )) {
        final row = await _decode(raw);
        rows.add(row);
        final owner = _recordOwner(row['_kind'], row);
        if (owner != null) {
          if (!allowed.contains(owner)) removed.add(owner);
          if (row['_pair'] != '') owners[row['_pair']] = owner;
        }
      }
      removed.addAll(
        (previous?['active'] as List? ?? []).cast<String>().where(
          (id) => !allowed.contains(id),
        ),
      );
      for (final row in rows) {
        final owner = _recordOwner(row['_kind'], row) ?? owners[row['_pair']];
        // Pre-owner-index draft-only records cannot be attributed safely. They
        // are erased, not reassigned to whichever identity is selected now.
        if (owner != null ? !allowed.contains(owner) : row['_pair'] != '') {
          _db.execute('DELETE FROM dm_records WHERE id=?', [row['_id']]);
        } else if (owner != null &&
            row['_kind'] == 'draft' &&
            row['identityId'] == null) {
          await _put(
            row['_id'],
            row['_kind'],
            row['_pair'],
            row['_ordinal'],
            row['_state'],
            {...row, 'identityId': owner},
          );
        }
      }
      await _collectPhotoGarbage();
      await _put('identity-directory', 'metadata', '', 0, 'saved', {
        'active': allowed.toList(),
        'removed': removed.toList(),
      });
    }),
  );

  Future<void> _collectPhotoGarbage() async {
    final referenced = <String>{};
    for (final raw in _db.select(
      "SELECT * FROM dm_records WHERE kind IN ('message','hidden_message','photo_draft')",
    )) {
      final row = await _decode(raw);
      if (row['_kind'] == 'photo_draft') {
        final directory = await _get('conversation:${row['_pair']}');
        final owner = row['senderId'] ?? directory?['identityId'];
        if (owner is String) {
          for (final photo in row['photos'] as List? ?? []) {
            referenced.add(await _mediaKey(owner, photo['mediaId']));
          }
        }
      } else {
        final outgoing = row['outgoing'] == true;
        final descriptor = outgoing
            ? row['intent'] as Map?
            : row['media'] as Map?;
        final owner = outgoing ? (descriptor?['identityId']) : row['senderId'];
        final id = descriptor?['mediaId'];
        if (owner is String && id is String) {
          referenced.add(await _mediaKey(owner, id));
        }
      }
    }
    for (final raw
        in _db
            .select(
              "SELECT DISTINCT pair FROM dm_records WHERE kind IN ('media','media_meta')",
            )
            .toList()) {
      if (!referenced.contains(raw['pair'])) {
        _db.execute(
          "DELETE FROM dm_records WHERE kind IN ('media','media_meta') AND pair=?",
          [raw['pair']],
        );
      }
    }
  }

  /// File-store fallback/test seam. Production additionally deletes the native
  /// database and key through purgeNativeClosedAccount after all handles drain.
  Future<void> purgeClosedAccount() => _run(() async {
    await _transaction(() async {
      await _put('account-closed', 'metadata', '', 0, 'closed', {
        'closed': true,
      });
      _db.execute("DELETE FROM dm_records WHERE id != 'account-closed'");
    });
    _db.execute('VACUUM');
  });
}
