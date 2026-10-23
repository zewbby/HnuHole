import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;

import '../auth/auth_store.dart';
import '../storage/post_store.dart';
import 'notification_models.dart';

/// Existing authenticated SQLite row/chunk storage, in a separate native
/// business namespace. The native vault holds only its encryption key (64 KiB
/// maximum); material and original request are committed in one DB transaction.
/// No PostController ever receives this store or these internal storage rows.
class GovernanceMaterialVault implements AuthVault {
  GovernanceMaterialVault({required this.openStore});
  final Future<PostStore> Function() openStore;
  Future<PostStore>? _opening;
  bool _closed = false;
  static const _recordId = '8c1d814d-a20b-4ca8-a9e4-bae80b5f9fd7';
  Future<PostStore> _store() async {
    if (_closed) throw const AuthStorageFailure();
    final opening = _opening ??= openStore();
    try {
      return await opening;
    } on Object {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  @override
  Future<String?> read() async {
    try {
      final store = await _store(), record = await store.get(_recordId);
      if (record == null) return null;
      final refs = record.data['chunks'];
      if (record.data.length != 1 ||
          refs is! List ||
          refs.isEmpty ||
          refs.length > 7) {
        throw const AuthStorageFailure();
      }
      final builder = BytesBuilder(copy: false);
      for (final raw in refs) {
        if (raw is! Map ||
            raw.length != 3 ||
            raw['blobId'] is! String ||
            raw['length'] is! int ||
            raw['sha256'] is! String) {
          throw const AuthStorageFailure();
        }
        builder.add(
          await store.readMedia(
            raw['blobId'] as String,
            raw['length'] as int,
            raw['sha256'] as String,
          ),
        );
        if (builder.length > 50 * 1024 * 1024) throw const AuthStorageFailure();
      }
      return utf8.decode(builder.takeBytes(), allowMalformed: false);
    } on Object {
      throw const AuthStorageFailure();
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      final bytes = utf8.encode(value);
      if (bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
        throw const AuthStorageFailure();
      }
      final store = await _store(), previous = await store.get(_recordId);
      final blobs = <String, Uint8List>{}, refs = <Map<String, dynamic>>[];
      const block = 8 * 1024 * 1024;
      for (var offset = 0; offset < bytes.length; offset += block) {
        final id = governanceId();
        final part = Uint8List.fromList(
          bytes.sublist(
            offset,
            offset + block > bytes.length ? bytes.length : offset + block,
          ),
        );
        blobs[id] = part;
        refs.add({
          'blobId': id,
          'length': part.length,
          'sha256': hashes.sha256.convert(part).toString(),
        });
      }
      await store.saveMediaDraft(_recordId, previous?.revision, {
        'chunks': refs,
      }, blobs);
    } on Object {
      throw const AuthStorageFailure();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final opening = _opening;
    if (opening != null) {
      try {
        await (await opening).close();
      } on Object {
        /* An unsuccessful open produced no usable writable store. */
      }
    }
  }
}
