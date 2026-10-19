import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/posts/post_upload_models.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';

class _Key implements BusinessKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const account = '11111111-1111-4111-8111-111111111111';
  const task = '22222222-2222-4222-8222-222222222222';
  const blob = '33333333-3333-4333-8333-333333333333';
  const identity = '44444444-4444-4444-8444-444444444444';
  const post = '55555555-5555-4555-8555-555555555555';
  test('closed native scope cleanup does not depend on decrypting a lost-key store', () async {
    var opened = 0;
    final purged = <String>[];
    final journal = NativeCommentJournal(
      (_) async {
        opened++;
        throw const PostStorageLostKey();
      },
      purgeStore: (a) async {
        purged.add(a);
      },
    );
    await expectLater(
      journal.store(account),
      throwsA(isA<PostStorageLostKey>()),
    );
    await journal.purgeClosedAccount(account);
    expect(opened, 1);
    expect(purged, [account]);
    await journal.close();
  });
  test('submitted original, immutable binding and unknown command survive encrypted SQLite reopen', () async {
    final dir = await Directory.systemTemp.createTemp(
      'hnuhole-comment-journal-',
    );
    final key = _Key();
    final file = File('${dir.path}/comments.sqlite3');
    NativeCommentJournal open() => NativeCommentJournal(
      (a) => PostStore.openFile(
        file,
        environment: 'isolated|comments-v1',
        accountId: a,
        vault: key,
      ),
    );
    var journal = open();
    final bytes = Uint8List.fromList(List.generate(400000, (i) => i % 253));
    final image = CommentImage(
      blobId: blob,
      selection: PostImageSelection.fromJson({
        'mediaId': blob,
        'sha256': sha256.convert(bytes).toString(),
        'byteLength': bytes.length,
        'mimeType': 'image/png',
        'width': 10,
        'height': 10,
      }),
    );
    final content = CommentContent(
      body: 'private-comment-marker\r\ne\u0301',
      image: image,
    );
    final entry = CommentJournalEntry(
      localId: task,
      intent: CommentIntent(
        commandId: base64Url.encode(List.filled(16, 7)).replaceAll('=', ''),
        taskId: task,
        operation: CommentOperation.create,
        binding: CommentBinding(postId: post, identityId: identity),
        content: content,
      ),
      transport: CommentTransportState.sending,
    );
    journal.staged[blob] = bytes;
    await journal.put(account, entry);
    expect(journal.staged, isEmpty);
    await journal.close();
    expect(
      latin1.decode(await file.readAsBytes()),
      isNot(contains('private-comment-marker')),
    );
    expect(key.value, isNot(contains('private-comment-marker')));
    journal = open();
    final restored = (await journal.read(account)).single;
    expect(restored.intent.commandId, entry.intent.commandId);
    expect(restored.content!.body, content.body);
    expect(restored.intent.binding.sameAs(entry.intent.binding), isTrue);
    expect(await journal.bytes(account, restored.content!.image!), bytes);
    await journal.put(
      account,
      restored.withState(CommentTransportState.unknown),
    );
    expect(
      (await journal.read(account)).single.transport,
      CommentTransportState.unknown,
    );
    await journal.remove(account, task);
    expect(await journal.read(account), isEmpty);
    expect((await (await journal.store(account)).list()), isEmpty);
    await journal.close();
    await dir.delete(recursive: true);
  });
  test(
    'missing original refuses persistence and never creates a partial task',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'hnuhole-comment-missing-',
      );
      final key = _Key();
      final journal = NativeCommentJournal(
        (a) => PostStore.openFile(
          File('${dir.path}/missing.sqlite3'),
          environment: 'comments-v1',
          accountId: a,
          vault: key,
        ),
      );
      final image = CommentImage(
        blobId: blob,
        selection: PostImageSelection.fromJson({
          'mediaId': blob,
          'sha256': 'a' * 64,
          'byteLength': 1,
          'mimeType': 'image/png',
          'width': 1,
          'height': 1,
        }),
      );
      final entry = CommentJournalEntry(
        localId: task,
        intent: CommentIntent(
          commandId: base64Url.encode(List.filled(16, 9)).replaceAll('=', ''),
          taskId: task,
          operation: CommentOperation.create,
          binding: CommentBinding(postId: post, identityId: identity),
          content: CommentContent(body: '', image: image),
        ),
        transport: CommentTransportState.sending,
      );
      await expectLater(
        journal.put(account, entry),
        throwsA(isA<PostStorageFailure>()),
      );
      expect(await journal.read(account), isEmpty);
      await journal.close();
      await dir.delete(recursive: true);
    },
  );
}
