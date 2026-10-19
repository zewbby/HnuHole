import 'dart:typed_data';

import '../storage/post_store.dart';
import '../posts/post_upload_models.dart';
import 'comment_api.dart';
import 'comment_models.dart';

/// A distinct native encrypted namespace. Only submitted tasks and immutable
/// mutation commands enter this store; temporary editors never call it.
class NativeCommentJournal implements CommentJournal {
  NativeCommentJournal(this.openStore);
  final Future<PostStore> Function(String account) openStore;
  final _stores = <String, Future<PostStore>>{};
  final staged = <String, Uint8List>{};
  Future<PostStore> store(String account) =>
      _stores.putIfAbsent(account, () => openStore(account));
  @override
  Future<List<CommentJournalEntry>> read(String accountId) async => [
    for (final row in await (await store(accountId)).list())
      if (row.data['kind'] == 'comment-task') decode(row.data),
  ];
  @override
  Future<void> put(String accountId, CommentJournalEntry entry) async {
    final db = await store(accountId);
    final old = await db.get(entry.localId);
    final image = entry.content?.image;
    final originals = <String, Uint8List>{};
    if (image != null && await db.get(image.blobId) == null) {
      final bytes = staged[image.blobId];
      if (bytes == null) throw const PostStorageFailure();
      originals[image.blobId] = bytes;
    }
    await db.saveMediaDraft(
      entry.localId,
      old?.revision,
      encode(entry),
      originals,
    );
    if (image != null) staged.remove(image.blobId);
  }

  Future<Uint8List> bytes(String account, CommentImage image) async =>
      (await store(account)).readMedia(
        image.blobId,
        image.selection.byteLength,
        image.selection.sha256,
      );
  @override
  Future<void> remove(String accountId, String localId) async {
    final db = await store(accountId);
    final old = await db.get(localId);
    if (old != null) await db.deleteDraft(localId, old.revision);
  }

  Future<void> close() async {
    staged.clear();
    for (final db in _stores.values) {
      await (await db).close();
    }
    _stores.clear();
  }

  static Map<String, dynamic> binding(CommentBinding b) => {
    'post': b.postId,
    'identity': b.identityId,
    'root': b.rootCommentId,
    'target': b.targetCommentId,
  };
  static CommentBinding parseBinding(Map b) => CommentBinding(
    postId: b['post'] as String,
    identityId: b['identity'] as String,
    rootCommentId: b['root'] as String?,
    targetCommentId: b['target'] as String?,
  );
  static Map<String, dynamic>? content(CommentContent? c) => c == null
      ? null
      : {
          'body': c.body,
          'image': c.image == null
              ? null
              : {
                  'blobId': c.image!.blobId,
                  'selection': c.image!.selection.toJson(),
                },
        };
  static CommentContent? parseContent(Object? value) {
    if (value == null) return null;
    final m = value as Map;
    final i = m['image'] as Map?;
    return CommentContent(
      body: m['body'] as String,
      image: i == null
          ? null
          : CommentImage(
              blobId: i['blobId'] as String,
              selection: PostImageSelection.fromJson(i['selection']),
            ),
    );
  }

  static Map<String, dynamic> task(CommentTask t) => {
    'id': t.taskId,
    'binding': binding(t.binding),
    'version': t.attemptVersion,
    'state': t.state.name,
    'available': t.contentAvailable,
    'retry': t.canRetry,
    'abandon': t.canAbandon,
    'comment': t.commentId,
    'failure': t.failureCode,
  };
  static CommentTask parseTask(Map t) => CommentTask(
    taskId: t['id'] as String,
    binding: parseBinding(t['binding'] as Map),
    attemptVersion: t['version'] as int,
    state: CommentTaskState.values.byName(t['state'] as String),
    contentAvailable: t['available'] as bool,
    canRetry: t['retry'] as bool,
    canAbandon: t['abandon'] as bool,
    commentId: t['comment'] as String?,
    failureCode: t['failure'] as String?,
  );
  static Map<String, dynamic> encode(CommentJournalEntry e) => {
    'kind': 'comment-task',
    'v': 1,
    'id': e.localId,
    'command': e.intent.commandId,
    'operation': e.intent.operation.name,
    'binding': binding(e.intent.binding),
    'version': e.intent.expectedAttemptVersion,
    'content': content(e.intent.content),
    'reconcileOnly': e.intent.reconciliationOnly,
    'retained': content(e.retainedContent),
    'transport': e.transport.name,
    'task': e.task == null ? null : task(e.task!),
    'used': e.usedCommandIds,
    'deleted': e.identityDeleted,
    'rejection': e.rejectionCode,
    'images': [
      if (e.content?.image case final i?)
        {'blobId': i.blobId, 'selection': i.selection.toJson()},
    ],
  };
  static CommentJournalEntry decode(Map<String, dynamic> m) {
    if (m['v'] != 1 || m['kind'] != 'comment-task') {
      throw const FormatException('Unsupported comment journal');
    }
    return CommentJournalEntry(
      localId: m['id'] as String,
      intent: CommentIntent(
        commandId: m['command'] as String,
        taskId: m['id'] as String,
        operation: CommentOperation.values.byName(m['operation'] as String),
        binding: parseBinding(m['binding'] as Map),
        expectedAttemptVersion: m['version'] as int?,
        content: parseContent(m['content']),
        reconciliationOnly: m['reconcileOnly'] as bool,
      ),
      transport: CommentTransportState.values.byName(m['transport'] as String),
      task: m['task'] == null ? null : parseTask(m['task'] as Map),
      retainedContent: parseContent(m['retained']),
      usedCommandIds: (m['used'] as List).cast<String>(),
      identityDeleted: m['deleted'] as bool,
      rejectionCode: m['rejection'] as String?,
    );
  }
}
