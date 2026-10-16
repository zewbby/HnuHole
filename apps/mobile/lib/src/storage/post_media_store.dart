part of 'post_store.dart';

const _mediaChunkBytes = 256 * 1024;
bool _blobId(String id) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(id);

/// Reuses the encrypted, account/environment-bound v1 row envelope. Each chunk
/// stays under the existing 1MiB limit; schema and vault formats are unchanged.
extension PostMediaStorage on PostStore {
  Future<StoredPostEntry> saveMediaDraft(
    String id,
    int? revision,
    Map<String, dynamic> data,
    Map<String, Uint8List> originals,
  ) => _run(() async {
    _validId(id);
    return _db.transaction(() async {
      await _checkActive();
      final old = await _get(id);
      if (revision == null
          ? old != null
          : old == null ||
                old.revision != revision ||
                !old.isDraft ||
                old.intents.isNotEmpty) {
        throw const PostStorageConflict();
      }
      for (final entry in originals.entries) {
        if (!_blobId(entry.key) ||
            entry.value.isEmpty ||
            entry.value.length > 10 * 1024 * 1024) {
          throw const PostStorageFailure();
        }
        for (
          var start = 0, index = 0;
          start < entry.value.length;
          start += _mediaChunkBytes, index++
        ) {
          final chunkId = '${entry.key}.${index.toString().padLeft(2, '0')}';
          if (await _get(chunkId) != null) throw const PostStorageConflict();
          final chunk = entry.value.sublist(
            start,
            min(start + _mediaChunkBytes, entry.value.length),
          );
          final row = StoredPostEntry(
            id: chunkId,
            revision: 1,
            state: 'mediaChunk',
            data: {'bytes': base64Encode(chunk)},
            intents: [],
          );
          await _db.customStatement(
            'INSERT INTO post_entries(id,revision,state,payload) VALUES (?,?,?,?)',
            [chunkId, 1, 'mediaChunk', await _entryPayload(row)],
          );
        }
        if (await _get(entry.key) != null) throw const PostStorageConflict();
        final root = StoredPostEntry(
          id: entry.key,
          revision: 1,
          state: 'mediaRoot',
          data: {
            'length': entry.value.length,
            'sha256': hashes.sha256.convert(entry.value).toString(),
          },
          intents: [],
        );
        await _db.customStatement(
          'INSERT INTO post_entries(id,revision,state,payload) VALUES (?,?,?,?)',
          [entry.key, 1, 'mediaRoot', await _entryPayload(root)],
        );
      }
      // Refuse a durable draft that claims unavailable original chunks.
      final images = data['images'] as List? ?? const [];
      for (final raw in images) {
        final item = raw as Map;
        if (item['selection'] == null) continue;
        final selection = item['selection'] as Map;
        final root = await _get(item['blobId'] as String);
        if (root == null ||
            root.state != 'mediaRoot' ||
            root.data['length'] != selection['byteLength'] ||
            root.data['sha256'] != selection['sha256']) {
          throw const PostStorageFailure();
        }
      }
      final next = StoredPostEntry(
        id: id,
        revision: (old?.revision ?? 0) + 1,
        state: 'draft',
        data: data,
        intents: [],
      );
      if (old == null) {
        await _db.customStatement(
          'INSERT INTO post_entries(id,revision,state,payload) VALUES (?,?,?,?)',
          [id, next.revision, 'draft', await _entryPayload(next)],
        );
      } else {
        await _update(next, revision!);
      }
      await _collectMedia(this);
      return next;
    });
  });

  Future<Uint8List> readMedia(String blobId, int length, String sha256) =>
      _run(() async {
        await _checkActive();
        return _readMedia(this, blobId, length, sha256);
      });
}

Future<Uint8List> _readMedia(
  PostStore store,
  String blobId,
  int length,
  String sha256,
) async {
  if (!_blobId(blobId) ||
      length < 1 ||
      length > 10 * 1024 * 1024 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
    throw const PostStorageFailure();
  }
  final root = await store._get(blobId);
  if (root == null ||
      root.state != 'mediaRoot' ||
      root.data['length'] != length ||
      root.data['sha256'] != sha256) {
    throw const PostStorageFailure();
  }
  final bytes = BytesBuilder(copy: false);
  final count = (length + _mediaChunkBytes - 1) ~/ _mediaChunkBytes;
  for (var index = 0; index < count; index++) {
    final row = await store._get('$blobId.${index.toString().padLeft(2, '0')}');
    if (row == null ||
        row.state != 'mediaChunk' ||
        row.data.length != 1 ||
        row.data['bytes'] is! String) {
      throw const PostStorageFailure();
    }
    final chunk = base64Decode(row.data['bytes'] as String);
    if (chunk.length !=
        min(_mediaChunkBytes, length - index * _mediaChunkBytes)) {
      throw const PostStorageFailure();
    }
    bytes.add(chunk);
  }
  final value = bytes.takeBytes();
  if (hashes.sha256.convert(value).toString() != sha256) {
    throw const PostStorageFailure();
  }
  return value;
}

Future<void> _collectMedia(PostStore store) async {
  final referenced = <String>{};
  void refs(Object? value) {
    if (value is Map) {
      if (value['blobId'] is String) referenced.add(value['blobId'] as String);
      for (final nested in value.values) {
        refs(nested);
      }
    } else if (value is List) {
      for (final nested in value) {
        refs(nested);
      }
    }
  }

  final rows = await store._db
      .customSelect(
        "SELECT id,revision,state,payload FROM post_entries WHERE state NOT IN ('mediaChunk','mediaRoot')",
      )
      .get();
  for (final row in rows) {
    refs((await store._decodeRow(row)).data);
  }
  final chunks = await store._db
      .customSelect(
        "SELECT id FROM post_entries WHERE state IN ('mediaChunk','mediaRoot')",
      )
      .get();
  for (final chunk in chunks) {
    final id = chunk.read<String>('id');
    final split = id.lastIndexOf('.');
    if (!referenced.contains(split < 0 ? id : id.substring(0, split))) {
      await store._db.customStatement(
        "DELETE FROM post_entries WHERE id=? AND state IN ('mediaChunk','mediaRoot')",
        [id],
      );
    }
  }
}
