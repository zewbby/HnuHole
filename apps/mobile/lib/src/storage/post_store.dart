import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _postSchemaV1 = <String, String>{
  'post_meta': 'CREATE TABLE post_meta(scope TEXT PRIMARY KEY NOT NULL,payload BLOB NOT NULL)',
  'post_entries': 'CREATE TABLE post_entries(id TEXT PRIMARY KEY NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),state TEXT NOT NULL,payload BLOB NOT NULL)',
  'post_command_index': 'CREATE TABLE post_command_index(command_tag TEXT PRIMARY KEY NOT NULL,entry_id TEXT NOT NULL REFERENCES post_entries(id))',
};

String _schemaSql(String sql) =>
    sql.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// Runs before any persistent PRAGMA or Drift version update. Unsupported or
/// malformed existing files must remain untouched instead of being downgraded.
void _checkPostSchema(sqlite.Database database) {
  final version = database.select('PRAGMA user_version').single.values.single;
  final objects = database.select(
    "SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND type IN ('table','view')",
  );
  if (version == 0 && objects.isEmpty) return;
  if (version != 1 || objects.length != _postSchemaV1.length) {
    throw const PostStorageFailure();
  }
  for (final row in objects) {
    final expected = _postSchemaV1[row['name']];
    if (row['type'] != 'table' ||
        expected == null ||
        row['sql'] is! String ||
        _schemaSql(row['sql'] as String) != _schemaSql(expected)) {
      throw const PostStorageFailure();
    }
  }
}

class PostStorageFailure implements Exception {
  const PostStorageFailure();
  @override
  String toString() => 'Business storage unavailable';
}

class PostStorageLostKey extends PostStorageFailure {
  const PostStorageLostKey();
  @override
  String toString() => 'Business storage key unavailable';
}

class PostStorageConflict extends PostStorageFailure {
  const PostStorageConflict();
}

class PostStorageClosed extends PostStorageFailure {
  const PostStorageClosed();
}

/// 此接口只保存独立业务密钥；测试替身结果不代表原生安全存储通过。
abstract interface class BusinessKeyVault {
  Future<String?> read();
  Future<void> write(String value);
}

class _NativeBusinessKeyVault implements BusinessKeyVault {
  _NativeBusinessKeyVault(this.vault);
  final DurableBusinessVault vault;
  @override
  Future<String?> read() => vault.read();
  @override
  Future<void> write(String value) => vault.write(value);
}

class StoredPostIntent {
  StoredPostIntent({
    required this.commandId,
    required this.operation,
    required this.digest,
    required Map<String, dynamic> payload,
  }) : payload = _freezeMap(payload) {
    if (commandId.isEmpty || operation.isEmpty || digest.isEmpty) {
      throw const FormatException('Invalid stored intent');
    }
  }
  final String commandId, operation, digest;
  final Map<String, dynamic> payload;
  Map<String, dynamic> toJson() => {
    'commandId': commandId,
    'operation': operation,
    'digest': digest,
    'payload': payload,
  };
  static StoredPostIntent _parse(Map<String, dynamic> value) =>
      StoredPostIntent(
        commandId: value['commandId'] as String,
        operation: value['operation'] as String,
        digest: value['digest'] as String,
        payload: Map<String, dynamic>.from(value['payload'] as Map),
      );
}

class StoredPostEntry {
  StoredPostEntry({
    required this.id,
    required this.revision,
    required this.state,
    required Map<String, dynamic> data,
    required List<StoredPostIntent> intents,
  }) : data = _freezeMap(data),
       intents = List.unmodifiable(intents);
  final String id, state;
  final int revision;
  final Map<String, dynamic> data;
  final List<StoredPostIntent> intents;
  bool get isDraft => state == 'draft';
}

/// 每个环境／账号一个 SQLite 文件；数据和命令锚点只以认证密文落盘。
/// UI 必须等待写入完成再离开编辑页。普通退出、401、冻结均不触发删除。
class PostStore {
  PostStore._(
    this._db,
    this.environment,
    this.accountId,
    this.scope,
    this._key,
    this._vault,
    this._keyRecord,
  );
  final _PostDatabase _db;
  final String environment, accountId, scope;
  final SecretKey _key;
  final BusinessKeyVault _vault;
  final String _keyRecord;
  final _cipher = AesGcm.with256bits();
  Future<void> _tail = Future.value();
  bool _closed = false;

  static String scopeFor(String environment, String accountId) {
    if (environment.isEmpty || accountId.isEmpty) {
      throw const FormatException('Invalid business storage owner');
    }
    return hashes.sha256
        .convert(
          utf8.encode(
            jsonEncode(['hnuhole.business.v1', environment, accountId]),
          ),
        )
        .toString();
  }

  static Future<PostStore> openNative({
    required String environment,
    required String accountId,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const PostStorageFailure();
    }
    try {
      final native = DurableBusinessVault(scopeFor(environment, accountId));
      final file = File(await native.databasePath());
      return await openFile(
        file,
        environment: environment,
        accountId: accountId,
        vault: _NativeBusinessKeyVault(native),
      );
    } on PostStorageFailure {
      rethrow;
    } catch (_) {
      throw const PostStorageFailure();
    }
  }

  /// 不依赖数据库解密成功，权威 CLOSED 可清理丢钥的原账号资料。
  static Future<void> purgeNativeClosedAccount({
    required String environment,
    required String accountId,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const PostStorageFailure();
    }
    try {
      await DurableBusinessVault(scopeFor(environment, accountId))
          .purgeClosedAccount();
    } catch (_) {
      throw const PostStorageFailure();
    }
  }

  /// 实盘测试接缝；生产入口只接受原生提供的 noBackup 路径。
  static Future<PostStore> openFile(
    File file, {
    required String environment,
    required String accountId,
    required BusinessKeyVault vault,
  }) async {
    _PostDatabase? database;
    try {
      final existing = await file.exists();
      var keyRecord = await vault.read();
      if (keyRecord == null) {
        if (existing) throw const PostStorageLostKey();
        final bytes = List<int>.generate(
          32,
          (_) => Random.secure().nextInt(256),
        );
        keyRecord = jsonEncode({'version': 1, 'key': base64UrlEncode(bytes)});
        await vault.write(keyRecord);
        if (await vault.read() != keyRecord) throw const PostStorageFailure();
      }
      final parsed = jsonDecode(keyRecord) as Map<String, dynamic>;
      if (parsed.length != 2 ||
          parsed['version'] != 1 ||
          parsed['key'] is! String) {
        throw const PostStorageFailure();
      }
      final keyBytes = base64Url.decode(parsed['key'] as String);
      if (keyBytes.length != 32) throw const PostStorageFailure();
      database = _PostDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: (raw) {
            _checkPostSchema(raw);
            raw.execute('PRAGMA journal_mode = DELETE');
            raw.execute('PRAGMA synchronous = FULL');
            raw.execute('PRAGMA secure_delete = ON');
            raw.execute('PRAGMA foreign_keys = ON');
            raw.execute('PRAGMA busy_timeout = 5000');
          },
        ),
      );
      final store = PostStore._(
        database,
        environment,
        accountId,
        scopeFor(environment, accountId),
        SecretKey(keyBytes),
        vault,
        keyRecord,
      );
      await store._initialize();
      return store;
    } on PostStorageFailure {
      await database?.close();
      rethrow;
    } catch (_) {
      await database?.close();
      throw const PostStorageFailure();
    }
  }

  Future<void> _initialize() async {
    await _db.transaction(() async {
      final rows = await _db
          .customSelect('SELECT scope, payload FROM post_meta')
          .get();
      if (rows.isEmpty) {
        final counts = await _db
            .customSelect(
              'SELECT (SELECT COUNT(*) FROM post_entries) + '
              '(SELECT COUNT(*) FROM post_command_index) AS n',
            )
            .getSingle();
        if (counts.read<int>('n') != 0) throw const PostStorageFailure();
        final check = await _encrypt('meta', 1, 'meta', {
          'schema': 1,
          'scope': scope,
          'closed': false,
        });
        await _db.customStatement(
          'INSERT INTO post_meta(scope,payload) VALUES (?,?)',
          [scope, check],
        );
      } else {
        if (rows.length != 1 || rows.single.read<String>('scope') != scope) {
          throw const PostStorageFailure();
        }
        final check = await _decrypt(
          'meta',
          1,
          'meta',
          rows.single.read<Uint8List>('payload'),
        );
        if (check['schema'] != 1 ||
            check['scope'] != scope ||
            check['closed'] is! bool) {
          throw const PostStorageFailure();
        }
        if (check['closed'] == true) throw const PostStorageClosed();
      }
      await _migrateLegacyRetryBuffers();
    });
  }

  /// The old controller included the private task/version in a retry row key.
  /// Rebind its AAD and FK references atomically without changing the original
  /// revision, encrypted task link, command payload, digest or terminal fact.
  Future<void> _migrateLegacyRetryBuffers() async {
    await _checkActive();
    final rows = await _db
        .customSelect(
          "SELECT id,revision,state,payload FROM post_entries WHERE id LIKE 'retry-%' ORDER BY id",
        )
        .get();
    final legacy = <StoredPostEntry>[];
    for (final row in rows) {
      final entry = await _decodeRow(row);
      if (entry.data['isRetryBuffer'] != true) continue;
      final taskId = entry.data['taskId'];
      final version = entry.data['attemptVersion'];
      if (taskId is! String ||
          taskId.isEmpty ||
          version is! int ||
          version < 1 ||
          entry.id != 'retry-$taskId-$version') {
        throw const PostStorageFailure();
      }
      legacy.add(entry);
    }
    // Decode every legacy candidate before writing anything. The surrounding
    // initialization transaction rolls back every remap if any write fails.
    for (final old in legacy) {
      final random = Random.secure();
      String? id;
      for (var attempt = 0; attempt < 16; attempt++) {
        final candidate = base64UrlEncode(
          List<int>.generate(16, (_) => random.nextInt(256)),
        ).replaceAll('=', '');
        if (await _get(candidate) == null) {
          id = candidate;
          break;
        }
      }
      if (id == null) throw const PostStorageConflict();
      final moved = StoredPostEntry(
        id: id,
        revision: old.revision,
        state: old.state,
        data: old.data,
        intents: old.intents,
      );
      await _db.customStatement(
        'INSERT INTO post_entries(id,revision,state,payload) VALUES (?,?,?,?)',
        [id, old.revision, old.state, await _entryPayload(moved)],
      );
      await _db.customStatement(
        'UPDATE post_command_index SET entry_id=? WHERE entry_id=?',
        [id, old.id],
      );
      final removed = await _db.customUpdate(
        'DELETE FROM post_entries WHERE id=? AND revision=?',
        variables: [Variable<String>(old.id), Variable<int>(old.revision)],
      );
      if (removed != 1) throw const PostStorageConflict();
    }
  }

  Future<StoredPostEntry?> get(String id) => _run(() async {
    await _checkActive();
    return _get(id);
  });
  Future<List<StoredPostEntry>> list() => _run(() async {
    await _checkActive();
    final rows = await _db
        .customSelect(
          'SELECT id,revision,state,payload FROM post_entries ORDER BY id',
        )
        .get();
    return Future.wait(rows.map(_decodeRow));
  });

  /// Private task/version association is compared only after decryption; it
  /// never becomes a row key or plaintext task-derived index.
  Future<StoredPostEntry?> findRetryBuffer(String taskId, int attemptVersion) =>
      _run(() async {
        if (taskId.isEmpty || attemptVersion < 1) {
          throw const PostStorageFailure();
        }
        await _checkActive();
        final rows = await _db
            .customSelect(
              "SELECT id,revision,state,payload FROM post_entries WHERE state='draft' ORDER BY id",
            )
            .get();
        StoredPostEntry? found;
        for (final row in rows) {
          final entry = await _decodeRow(row);
          if (entry.data['isRetryBuffer'] != true ||
              entry.data['taskId'] != taskId ||
              entry.data['attemptVersion'] != attemptVersion) {
            continue;
          }
          if (found != null) throw const PostStorageConflict();
          found = entry;
        }
        return found;
      });

  Future<StoredPostEntry> createDraft(
    String id,
    Map<String, dynamic> data,
  ) => _run(() async {
    _validId(id);
    final entry = StoredPostEntry(
      id: id,
      revision: 1,
      state: 'draft',
      data: data,
      intents: [],
    );
    await _db.transaction(() async {
      await _checkActive();
      if (await _get(id) != null) throw const PostStorageConflict();
      await _db.customStatement(
        'INSERT INTO post_entries(id,revision,state,payload) VALUES (?,?,?,?)',
        [id, 1, 'draft', await _entryPayload(entry)],
      );
    });
    return entry;
  });

  /// 跨设备任务与维护命令直接建立不可编辑锚点，中途不能出现草稿状态。
  Future<StoredPostEntry> createSubmitted(
    String id,
    StoredPostIntent intent,
    Map<String, dynamic> data, {
    String state = 'submitted',
  }) => _run(() async {
    _validId(id);
    _validState(state);
    if (state.toLowerCase() == 'draft') throw const PostStorageConflict();
    final entry = StoredPostEntry(
      id: id,
      revision: 1,
      state: state,
      data: data,
      intents: [intent],
    );
    await _db.transaction(() async {
      await _checkActive();
      if (await _get(id) != null) throw const PostStorageConflict();
      await _db.customStatement(
        'INSERT INTO post_entries(id,revision,state,payload) VALUES (?,?,?,?)',
        [id, 1, state, await _entryPayload(entry)],
      );
      await _insertIntentIndex(id, intent);
    });
    return entry;
  });

  Future<StoredPostEntry> saveDraft(
    String id,
    int expectedRevision,
    Map<String, dynamic> data,
  ) => _replace(id, expectedRevision, (old) {
    if (!old.isDraft || old.intents.isNotEmpty) {
      throw const PostStorageConflict();
    }
    return _next(old, 'draft', data, []);
  });

  Future<void> deleteDraft(String id, int expectedRevision) => _run(() async {
    await _db.transaction(() async {
      await _checkActive();
      final old = await _required(id, expectedRevision);
      if (!old.isDraft || old.intents.isNotEmpty) {
        throw const PostStorageConflict();
      }
      final count = await _db.customUpdate(
        'DELETE FROM post_entries WHERE id=? AND revision=?',
        variables: [Variable<String>(id), Variable<int>(expectedRevision)],
      );
      if (count != 1) throw const PostStorageConflict();
    });
  });

  Future<StoredPostEntry> submitDraft(
    String id,
    int expectedRevision,
    StoredPostIntent intent,
    Map<String, dynamic> data,
  ) => _replace(id, expectedRevision, (old) {
    if (!old.isDraft || old.intents.isNotEmpty) {
      throw const PostStorageConflict();
    }
    return _next(old, 'submitted', data, [intent]);
  }, newIntent: intent);

  /// 已提交项目保持独立状态；UNKNOWN 不能还原成可换身份的新草稿。
  Future<StoredPostEntry> recordResult(
    String id,
    int expectedRevision,
    String state,
    Map<String, dynamic> data,
  ) => _replace(id, expectedRevision, (old) {
    if (old.isDraft || state == 'draft') throw const PostStorageConflict();
    if (old.intents.any((intent) => intent.payload['compacted'] == true) &&
        state != old.state) {
      throw const PostStorageConflict();
    }
    _validState(state);
    return _next(
      old,
      state,
      old.intents.any((intent) => intent.payload['compacted'] == true)
          ? _withoutContent(data)
          : data,
      old.intents,
    );
  });

  Future<StoredPostEntry> appendIntent(
    String id,
    int expectedRevision,
    StoredPostIntent intent,
    Map<String, dynamic> data,
  ) => _run(() async {
    return _db.transaction(() async {
      await _checkActive();
      final current = await _get(id);
      if (current == null || current.isDraft) throw const PostStorageConflict();
      final replay = current.intents.where(
        (i) => i.commandId == intent.commandId,
      );
      if (replay.isNotEmpty) {
        if (!_jsonEqual(replay.single.toJson(), intent.toJson())) {
          throw const PostStorageConflict();
        }
        return current;
      }
      final old = await _required(id, expectedRevision);
      if (old.intents.any((intent) => intent.payload['compacted'] == true)) {
        throw const PostStorageConflict();
      }
      final next = _next(old, 'submitted', data, [...old.intents, intent]);
      await _insertIntentIndex(id, intent);
      await _update(next, expectedRevision);
      return next;
    });
  });

  /// 仅明确终态可擦除正文；NOT_ACCEPTED 还须调用方先取得用户明确放弃。
  /// 已公开原文由服务端持有，本机只保留防重事实；未决仍留精确 payload。
  Future<StoredPostEntry> compactTerminal(
    String id,
    int expectedRevision,
    String state,
    Map<String, dynamic> data,
  ) => _replace(id, expectedRevision, (old) {
    if (old.isDraft ||
        !{
          'published',
          'cancelled',
          'notaccepted',
          'hidden',
          'deleted',
          'contentunavailable',
        }.contains(state.replaceAll('_', '').toLowerCase())) {
      throw const PostStorageConflict();
    }
    return _next(
      old,
      state,
      _withoutContent(data),
      old.intents
          .map(
            (intent) => StoredPostIntent(
              commandId: intent.commandId,
              operation: intent.operation,
              digest: intent.digest,
              payload: {'compacted': true},
            ),
          )
          .toList(),
    );
  });

  /// 调用方只在服务端权威 CLOSED 终态后使用；本对象只覆盖原账号文件。
  Future<void> purgeClosedAccount() => _run(() async {
    await _db.transaction(() async {
      // 先提交永久墓碑；别的连接的迟到写在事务内检查后拒绝。
      await _checkActive(allowClosed: true);
      await _db.customStatement(
        'UPDATE post_meta SET payload=? WHERE scope=?',
        [
          await _encrypt('meta', 1, 'meta', {
            'schema': 1,
            'scope': scope,
            'closed': true,
          }),
          scope,
        ],
      );
      await _db.customStatement('DELETE FROM post_command_index');
      await _db.customStatement('DELETE FROM post_entries');
    });
    await _db.customStatement('VACUUM');
  });

  Future<void> close() async {
    await _tail;
    if (!_closed) {
      _closed = true;
      await _db.close();
    }
  }

  Future<StoredPostEntry> _replace(
    String id,
    int expectedRevision,
    StoredPostEntry Function(StoredPostEntry) transform, {
    StoredPostIntent? newIntent,
  }) => _run(() async {
    return _db.transaction(() async {
      await _checkActive();
      final old = await _required(id, expectedRevision);
      final next = transform(old);
      if (newIntent != null) await _insertIntentIndex(id, newIntent);
      await _update(next, expectedRevision);
      return next;
    });
  });

  Future<void> _checkActive({bool allowClosed = false}) async {
    // 原生闭号 marker 或密钥变化也应使已打开实例停止写入。
    if (await _vault.read() != _keyRecord) throw const PostStorageLostKey();
    final rows = await _db
        .customSelect('SELECT scope,payload FROM post_meta')
        .get();
    if (rows.length != 1 || rows.single.read<String>('scope') != scope) {
      throw const PostStorageFailure();
    }
    final check = await _decrypt(
      'meta',
      1,
      'meta',
      rows.single.read<Uint8List>('payload'),
    );
    if (check['schema'] != 1 ||
        check['scope'] != scope ||
        check['closed'] is! bool) {
      throw const PostStorageFailure();
    }
    if (check['closed'] == true && !allowClosed) {
      throw const PostStorageClosed();
    }
  }

  Future<void> _insertIntentIndex(String id, StoredPostIntent intent) async {
    final bytes = await _key.extractBytes();
    final tag = hashes.Hmac(hashes.sha256, bytes)
        .convert(
          utf8.encode(jsonEncode(['post-command-v1', scope, intent.commandId])),
        )
        .toString();
    final exists = await _db
        .customSelect(
          'SELECT entry_id FROM post_command_index WHERE command_tag=?',
          variables: [Variable<String>(tag)],
        )
        .get();
    if (exists.isNotEmpty) throw const PostStorageConflict();
    await _db.customStatement(
      'INSERT INTO post_command_index(command_tag,entry_id) VALUES (?,?)',
      [tag, id],
    );
  }

  Future<void> _update(StoredPostEntry next, int expected) async {
    final count = await _db.customUpdate(
      'UPDATE post_entries SET revision=?,state=?,payload=? WHERE id=? AND revision=?',
      variables: [
        Variable<int>(next.revision),
        Variable<String>(next.state),
        Variable<Uint8List>(await _entryPayload(next)),
        Variable<String>(next.id),
        Variable<int>(expected),
      ],
    );
    if (count != 1) throw const PostStorageConflict();
  }

  StoredPostEntry _next(
    StoredPostEntry old,
    String state,
    Map<String, dynamic> data,
    List<StoredPostIntent> intents,
  ) => StoredPostEntry(
    id: old.id,
    revision: old.revision + 1,
    state: state,
    data: data,
    intents: intents,
  );

  Future<StoredPostEntry> _required(String id, int revision) async {
    final value = await _get(id);
    if (value == null || value.revision != revision) {
      throw const PostStorageConflict();
    }
    return value;
  }

  Future<StoredPostEntry?> _get(String id) async {
    _validId(id);
    final rows = await _db
        .customSelect(
          'SELECT id,revision,state,payload FROM post_entries WHERE id=?',
          variables: [Variable<String>(id)],
        )
        .get();
    return rows.isEmpty ? null : _decodeRow(rows.single);
  }

  Future<StoredPostEntry> _decodeRow(QueryRow row) async {
    final id = row.read<String>('id');
    final revision = row.read<int>('revision');
    final state = row.read<String>('state');
    _validId(id);
    _validState(state);
    if (revision < 1) throw const PostStorageFailure();
    final plain = await _decrypt(
      id,
      revision,
      state,
      row.read<Uint8List>('payload'),
    );
    if (plain.keys.toSet().difference({'data', 'intents'}).isNotEmpty ||
        plain.length != 2) {
      throw const PostStorageFailure();
    }
    final intents = (plain['intents'] as List)
        .map(
          (e) => StoredPostIntent._parse(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (intents.map((i) => i.commandId).toSet().length != intents.length ||
        (state == 'draft') != intents.isEmpty) {
      throw const PostStorageFailure();
    }
    return StoredPostEntry(
      id: id,
      revision: revision,
      state: state,
      data: Map<String, dynamic>.from(plain['data'] as Map),
      intents: intents,
    );
  }

  Future<Uint8List> _entryPayload(StoredPostEntry entry) =>
      _encrypt(entry.id, entry.revision, entry.state, {
        'data': entry.data,
        'intents': entry.intents.map((i) => i.toJson()).toList(),
      });

  List<int> _aad(String id, int revision, String state) => utf8.encode(
    jsonEncode([
      'hnuhole.posts.payload',
      1,
      environment,
      accountId,
      scope,
      id,
      revision,
      state,
    ]),
  );

  Future<Uint8List> _encrypt(
    String id,
    int revision,
    String state,
    Map<String, dynamic> value,
  ) async {
    final plain = utf8.encode(jsonEncode(value));
    if (plain.length > 1024 * 1024) throw const PostStorageFailure();
    final box = await _cipher.encrypt(
      plain,
      secretKey: _key,
      aad: _aad(id, revision, state),
    );
    return Uint8List.fromList([
      1,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Map<String, dynamic>> _decrypt(
    String id,
    int revision,
    String state,
    Uint8List bytes,
  ) async {
    if (bytes.length < 29 || bytes.length > 1024 * 1024 + 29 || bytes[0] != 1) {
      throw const PostStorageFailure();
    }
    final box = SecretBox(
      bytes.sublist(13, bytes.length - 16),
      nonce: bytes.sublist(1, 13),
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    final plain = await _cipher.decrypt(
      box,
      secretKey: _key,
      aad: _aad(id, revision, state),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (_closed) throw const PostStorageFailure();
      return await action();
    } on PostStorageFailure {
      rethrow;
    } catch (_) {
      // 不泄露文件名、明文、密钥、SQLite 诊断；调用方保留当前输入。
      throw const PostStorageFailure();
    } finally {
      done.complete();
    }
  }
}

class _PostDatabase extends GeneratedDatabase {
  _PostDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final sql in _postSchemaV1.values) {
        await customStatement(sql);
      }
    },
    onUpgrade: (_, __, ___) async {
      throw const PostStorageFailure();
    },
  );
}

void _validId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(id)) {
    throw const PostStorageFailure();
  }
}

void _validState(String state) {
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(state)) {
    throw const PostStorageFailure();
  }
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
  const forbidden = {
    'token',
    'bearer',
    'password',
    'recoveryCode',
    'recoveryCodes',
    'revocationSecret',
  };
  dynamic freeze(dynamic input) {
    if (input is Map) {
      final output = <String, dynamic>{};
      for (final entry in input.entries) {
        if (entry.key is! String || forbidden.contains(entry.key)) {
          throw const PostStorageFailure();
        }
        output[entry.key as String] = freeze(entry.value);
      }
      return Map<String, dynamic>.unmodifiable(output);
    }
    if (input is List) return List<dynamic>.unmodifiable(input.map(freeze));
    if (input == null ||
        input is String ||
        input is bool ||
        input is int ||
        input is double) {
      return input;
    }
    throw const PostStorageFailure();
  }

  return freeze(value) as Map<String, dynamic>;
}

bool _jsonEqual(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _jsonEqual(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _jsonEqual(a[i], b[i]));
  }
  return a == b;
}

Map<String, dynamic> _withoutContent(Map<String, dynamic> value) {
  dynamic compact(dynamic input) {
    if (input is Map) {
      return <String, dynamic>{
        for (final entry in input.entries)
          if (!{'title', 'body', 'content'}.contains(entry.key))
            entry.key as String: compact(entry.value),
      };
    }
    if (input is List) return input.map(compact).toList();
    return input;
  }

  return compact(value) as Map<String, dynamic>;
}
