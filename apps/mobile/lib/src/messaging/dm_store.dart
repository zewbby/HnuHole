import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';

import '../storage/post_store.dart'
    show BusinessKeyVault, PostStorageFailure, PostStorageLostKey;
import 'dm_protocol.dart';

class _DmVault implements BusinessKeyVault {
  _DmVault(this.native);
  final DurableBusinessVault native;
  @override
  Future<String?> read() => native.read();
  @override
  Future<void> write(String value) => native.write(value);
}

/// Separate, encrypted, account-scoped database. All changes are serialized;
/// SQLite FULL transactions finish before enqueue/receive resolves to callers.
class DmStore {
  static final _opening = <String, Future<void>>{};
  DmStore._(this._db, this.scope, this._key, this._vault, this._keyRecord);
  final Database _db;
  final String scope, _keyRecord;
  final SecretKey _key;
  final BusinessKeyVault _vault;
  final _cipher = AesGcm.with256bits();
  Future<void> _tail = Future.value();
  bool _closed = false, _closing = false;
  static String scopeFor(String environment, String account) => hashes.sha256
      .convert(utf8.encode(jsonEncode(['hnuhole.dm.v1', environment, account])))
      .toString();
  static Future<DmStore> openNative(String environment, String account) async {
    final vault = DurableBusinessVault(scopeFor(environment, account));
    return open(
      File(await vault.databasePath()),
      environment,
      account,
      _DmVault(vault),
    );
  }

  static Future<DmStore> open(
    File file,
    String environment,
    String account,
    BusinessKeyVault vault,
  ) async {
    final path = file.absolute.path;
    final previous = _opening[path];
    final done = Completer<void>();
    _opening[path] = done.future;
    try {
      await previous;
      return await _open(file, environment, account, vault);
    } finally {
      done.complete();
      if (identical(_opening[path], done.future)) _opening.remove(path);
    }
  }

  static Future<DmStore> _open(
    File file,
    String environment,
    String account,
    BusinessKeyVault vault,
  ) async {
    Database? db;
    try {
      if (environment.isEmpty || account.isEmpty) {
        throw const PostStorageFailure();
      }
      final exists = await file.exists();
      var record = await vault.read();
      if (record == null) {
        if (exists) throw const PostStorageLostKey();
        record = base64Encode(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        );
        await vault.write(record);
      }
      if (await vault.read() != record) throw const PostStorageFailure();
      final bytes = base64Decode(record);
      if (bytes.length != 32) throw const PostStorageFailure();
      db = sqlite3.open(file.path);
      final version = db.select('PRAGMA user_version').single.values.single;
      final objects = db.select(
        "SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      if (version != 0 && version != 1 ||
          version == 0 && objects.isNotEmpty ||
          version == 1 &&
              (objects.length != 2 ||
                  !objects.any((r) => r['name'] == 'dm_meta') ||
                  !objects.any((r) => r['name'] == 'dm_records'))) {
        throw const PostStorageFailure();
      }
      if (version == 1 &&
          (db
                      .select('PRAGMA table_info(dm_records)')
                      .map((r) => r['name'])
                      .join(',') !=
                  'id,kind,pair,ordinal,sort_key,state,payload' ||
              db
                      .select('PRAGMA table_info(dm_meta)')
                      .map((r) => r['name'])
                      .join(',') !=
                  'scope,payload')) {
        throw const PostStorageFailure();
      }
      db.execute('PRAGMA journal_mode=DELETE');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA secure_delete=ON');
      db.execute('PRAGMA busy_timeout=5000');
      final store = DmStore._(
        db,
        scopeFor(environment, account),
        SecretKey(bytes),
        vault,
        record,
      );
      await store._transaction(() async {
        if (version == 0) {
          db!.execute(
            'CREATE TABLE dm_meta(scope TEXT PRIMARY KEY,payload BLOB NOT NULL)',
          );
          db.execute(
            'CREATE TABLE dm_records(id TEXT PRIMARY KEY,kind TEXT NOT NULL,pair TEXT NOT NULL,ordinal INTEGER NOT NULL,sort_key INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)',
          );
          db.execute(
            'CREATE INDEX dm_history ON dm_records(kind,pair,sort_key,id)',
          );
          db.execute('CREATE INDEX dm_work ON dm_records(kind,state,ordinal)');
          final payload = await store._encrypt('meta', 'meta', '', 0, 'meta', {
            'version': 1,
          });
          db!.execute('INSERT INTO dm_meta VALUES(?,?)', [
            store.scope,
            payload,
          ]);
          db.execute('PRAGMA user_version=1');
        } else {
          final meta = db!.select('SELECT * FROM dm_meta');
          if (meta.length != 1 ||
              meta.single['scope'] != store.scope ||
              (await store._decrypt(
                    'meta',
                    'meta',
                    '',
                    0,
                    'meta',
                    meta.single['payload'],
                  ))['version'] !=
                  1) {
            throw const PostStorageFailure();
          }
        }
      });
      return store;
    } catch (_) {
      db?.close();
      throw const PostStorageFailure();
    }
  }

  Future<String> pairTag(String own, String peer) async => hashes.Hmac(
    hashes.sha256,
    await _key.extractBytes(),
  ).convert(utf8.encode(jsonEncode([own, peer]))).toString();

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_closing) throw const PostStorageFailure();
    final before = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await before;
    try {
      if (_closed || await _vault.read() != _keyRecord) {
        throw const PostStorageFailure();
      }
      return await action();
    } catch (_) {
      throw const PostStorageFailure();
    } finally {
      done.complete();
    }
  }

  Future<T> _transaction<T>(Future<T> Function() action) async {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final v = await action();
      _db.execute('COMMIT');
      return v;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<int> _aad(
    String id,
    String kind,
    String pair,
    int ordinal,
    String state,
  ) => utf8.encode(jsonEncode([scope, 1, id, kind, pair, ordinal, state]));
  Future<Uint8List> _encrypt(
    String id,
    String kind,
    String pair,
    int ordinal,
    String state,
    Map<String, dynamic> value,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: _key,
      aad: _aad(id, kind, pair, ordinal, state),
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Map<String, dynamic>> _decrypt(
    String id,
    String kind,
    String pair,
    int ordinal,
    String state,
    Uint8List bytes,
  ) async {
    if (bytes.length < 28 || bytes.length > 1024 * 1024) {
      throw const PostStorageFailure();
    }
    final plain = await _cipher.decrypt(
      SecretBox(
        bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: _key,
      aad: _aad(id, kind, pair, ordinal, state),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
  }

  Future<Map<String, dynamic>> _decode(Row r) async => {
    ...await _decrypt(
      r['id'],
      r['kind'],
      r['pair'],
      r['ordinal'],
      '${r['state']}:${r['sort_key']}',
      r['payload'],
    ),
    '_id': r['id'],
    '_state': r['state'],
    '_ordinal': r['ordinal'],
    '_sort': r['sort_key'],
    '_pair': r['pair'],
  };
  Future<void> _put(
    String id,
    String kind,
    String pair,
    int ordinal,
    String state,
    Map<String, dynamic> value,
  ) async {
    final data = Map<String, dynamic>.from(value)
      ..removeWhere((k, _) => k.startsWith('_'));
    // Confirmed messages follow the server's per-conversation sequence even
    // when an incoming message is delivered after a later outgoing receipt.
    // Unconfirmed local work stays at the end, in durable enqueue order.
    final sequence = data['outgoing'] == true
        ? ((data['receipt'] as Map?)?['sequence'] as int?)
        : data['sequence'] as int?;
    final sortKey = kind == 'message' ? sequence ?? (1 << 62) + ordinal : 0;
    final payload = await _encrypt(
      id,
      kind,
      pair,
      ordinal,
      '$state:$sortKey',
      data,
    );
    _db.execute(
      'INSERT INTO dm_records VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,pair=excluded.pair,ordinal=excluded.ordinal,sort_key=excluded.sort_key,state=excluded.state,payload=excluded.payload',
      [id, kind, pair, ordinal, sortKey, state, payload],
    );
  }

  Future<Map<String, dynamic>?> _get(String id) async {
    final rows = _db.select('SELECT * FROM dm_records WHERE id=?', [id]);
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<Map<String, dynamic>?> get(String id) => _run(() => _get(id));
  Future<List<Map<String, dynamic>>> work() => _run(
    () async => Future.wait(
      _db
          .select(
            "SELECT * FROM dm_records WHERE kind='message' AND state IN ('queued','unknown','received','read_pending') ORDER BY ordinal,id LIMIT 100",
          )
          .map(_decode),
    ),
  );
  Future<List<Map<String, dynamic>>> history(
    String own,
    String peer, {
    int limit = 40,
    int? before,
  }) => _run(() async {
    final pair = await pairTag(own, peer);
    return Future.wait(
      _db
          .select(
            "SELECT * FROM dm_records WHERE kind='message' AND pair=? AND sort_key<? ORDER BY sort_key DESC,id DESC LIMIT ?",
            [pair, before ?? 9223372036854775807, limit.clamp(1, 100)],
          )
          .reversed
          .map(_decode),
    );
  });
  Future<void> saveDraft(String own, String peer, String text) =>
      _run(() async {
        final pair = await pairTag(own, peer);
        await _transaction(
          () => _put('draft:$pair', 'draft', pair, 0, 'draft', {'text': text}),
        );
      });
  Future<String> draft(String own, String peer) => _run(
    () async =>
        (await _get('draft:${await pairTag(own, peer)}'))?['text'] as String? ??
        '',
  );
  Future<String> enqueue(Map<String, Object> intent, {String peerName = ''}) =>
      _run(() async {
        if (!dmValidText(intent['text'] as String)) {
          throw const PostStorageFailure();
        }
        final pair = await pairTag(
          intent['identityId'] as String,
          intent['peerId'] as String,
        );
        final id = dmId();
        // Stable enqueue order for unconfirmed work; confirmed history uses sequence.
        final ordinal = _nextOrdinal();
        await _transaction(() async {
          await _put(id, 'message', pair, ordinal, 'queued', {
            'intent': intent,
            'outgoing': true,
          });
          // Keep an offline first contact reachable from the inbox before the
          // server has accepted it or returned its conversation directory.
          if (await _get('conversation:$pair') == null) {
            final conversation = intent['conversationId'] as String;
            await _put(
              'conversation:$pair',
              'conversation',
              pair,
              0,
              'directory',
              {
                'id': conversation.isEmpty ? 'local:$pair' : conversation,
                'localOnly': conversation.isEmpty,
                'identityId': intent['identityId'],
                'peerId': intent['peerId'],
                'peerName': peerName.isEmpty ? '匿名身份' : peerName,
                'sourcePostId': intent['sourcePostId'],
                'sourceCommentId': intent['sourceCommentId'],
                'sequence': 0,
                'unread': 0,
                'waiting': false,
                'canSend': true,
              },
            );
          }
          // Preserve a draft changed after this exact send was initiated.
          final draft = await _get('draft:$pair');
          if (draft == null || draft['text'] == intent['text']) {
            await _put('draft:$pair', 'draft', pair, 0, 'draft', {'text': ''});
          }
        });
        return id;
      });
  int _nextOrdinal() =>
      (_db
              .select('SELECT COALESCE(MAX(ordinal),0)+1 AS n FROM dm_records')
              .single['n']
          as int);
  Future<void> transition(
    String id,
    String expected,
    String state, {
    Map<String, dynamic>? receipt,
  }) => _run(() async {
    await _transaction(() async {
      final row = await _get(id);
      if (row == null || row['_state'] != expected) {
        throw const PostStorageFailure();
      }
      if (receipt != null) row['receipt'] = receipt;
      await _put(id, 'message', row['_pair'], row['_ordinal'], state, row);
      if (state == 'sent' && receipt != null) {
        final directoryId = 'conversation:${row['_pair']}';
        final directory = await _get(directoryId);
        if (directory != null && directory['localOnly'] == true) {
          directory['id'] = receipt['conversationId'];
          directory['localOnly'] = false;
          directory['waiting'] = true;
          await _put(
            directoryId,
            'conversation',
            row['_pair'],
            0,
            'directory',
            directory,
          );
        }
      }
    });
  });
  Future<void> retry(String id) => _run(() async {
    await _transaction(() async {
      final row = await _get(id);
      if (row == null || row['_state'] != 'failed') {
        throw const PostStorageFailure();
      }
      final intent = Map<String, dynamic>.from(row['intent'] as Map);
      intent['attempt'] = (intent['attempt'] as int) + 1;
      row['intent'] = intent;
      await _put(id, 'message', row['_pair'], row['_ordinal'], 'queued', row);
    });
  });
  Future<void> receive(List<Map<String, dynamic>> items) => _run(
    () => _transaction(() async {
      // Entire fetched batch is committed before the caller can send any ACK.
      for (final item in items) {
        final id = item['messageId'] as String;
        final previous = await _get(id);
        if (previous != null) {
          for (final key in [
            'messageId',
            'conversationId',
            'identityId',
            'senderId',
            'sequence',
            'text',
            'acceptedAt',
          ]) {
            if (previous[key] != item[key]) throw const PostStorageFailure();
          }
          continue;
        }
        final pair = await pairTag(item['identityId'], item['senderId']);
        await _put(id, 'message', pair, _nextOrdinal(), 'received', {
          ...item,
          'outgoing': false,
        });
        // Keep committed incoming content reachable if the next network request
        // fails, even before the canonical directory and nickname arrive.
        final directoryId = 'conversation:$pair';
        final directory =
            await _get(directoryId) ??
            <String, dynamic>{
              'peerName': '匿名身份',
              'sourcePostId': '',
              'unread': 0,
              'canSend': true,
            };
        final lastSequence = (directory['sequence'] as int?) ?? 0;
        directory.addAll({
          'id': item['conversationId'],
          'localOnly': false,
          'identityId': item['identityId'],
          'peerId': item['senderId'],
          'sequence': max(lastSequence, item['sequence'] as int),
          'waiting': false,
          'unread':
              (directory['unread'] as int) +
              ((item['sequence'] as int) > lastSequence ? 1 : 0),
        });
        await _put(
          directoryId,
          'conversation',
          pair,
          0,
          'directory',
          directory,
        );
      }
    }),
  );
  Future<void> saveConversations(List<Map<String, dynamic>> items) => _run(
    () => _transaction(() async {
      for (final item in items) {
        final pair = await pairTag(item['identityId'], item['peerId']);
        await _put(
          'conversation:$pair',
          'conversation',
          pair,
          0,
          'directory',
          item,
        );
      }
    }),
  );
  Future<List<Map<String, dynamic>>> conversations() => _run(
    () async => Future.wait(
      _db
          .select("SELECT * FROM dm_records WHERE kind='conversation'")
          .map(_decode),
    ),
  );
  Future<bool> markVisible(List<String> ids) => _run(
    () => _transaction(() async {
      var changed = false;
      for (final id in ids) {
        final row = await _get(id);
        // Incoming records become eligible only after server ACK succeeded.
        if (row == null || row['_state'] != 'inbox') continue;
        await _put(
          id,
          'message',
          row['_pair'],
          row['_ordinal'],
          'read_pending',
          row,
        );
        changed = true;
      }
      return changed;
    }),
  );
  Future<void> close() async {
    _closing = true;
    await _tail;
    if (!_closed) {
      _closed = true;
      _db.close();
    }
  }
}
