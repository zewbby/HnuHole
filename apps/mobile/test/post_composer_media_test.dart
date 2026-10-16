import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'post_upload_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaComposerFixture f;
  late Uint8List png;
  setUp(() async {
    f = await MediaComposerFixture.create();
    png = await File(
      '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
    ).readAsBytes();
  });
  tearDown(() async {
    await f.close();
  });
  Future<PostDraftEditor> selected(int count) async {
    final editor = f.editor();
    f.picker.next = List.generate(count, (_) => pickedBytes(png));
    await f.posts.pickDraftPhotos(editor);
    expect(editor.images.length, count);
    return editor;
  }

  test('same-phone durable originals and order survive restart without picker paths or plaintext', () async {
    final editor = await selected(2);
    final first = editor.images.removeAt(0);
    editor.images.add(first);
    editor.mediaTouched = true;
    expect(await f.posts.saveDraft(editor), isTrue);
    final order = editor.images.map((e) => e.mediaId).toList();
    await f.restart();
    final restored = (await f.posts.restoreDraft(editor.id))!;
    expect(restored.images.map((e) => e.mediaId), order);
    for (final image in restored.images) {
      expect(await f.posts.draftPhotoBytes(restored, image), png);
    }
    final rows = await f.current!.list();
    expect(rows.length, 1);
    final encoded = jsonEncode(rows.single.data);
    expect(encoded.contains('path'), isFalse);
    expect(encoded.contains(base64Encode(png)), isFalse);
    final raw = await File('${f.root.path}/draft.sqlite3').readAsBytes();
    expect(utf8.decode(raw, allowMalformed: true).contains('图片标题'), isFalse);
  });

  test('failed selection preserves other photos and text; replacement and remove are durable', () async {
    final editor = f.editor()..body = '保留正文';
    f.picker.next = [
      pickedBytes(png),
      pickedBytes(Uint8List.fromList([1, 2, 3])),
    ];
    await f.posts.pickDraftPhotos(editor);
    expect(editor.images.map((e) => e.ready), [true, false]);
    expect(editor.body, '保留正文');
    expect(await f.posts.publish(editor), isFalse);
    expect(f.api.creates, 0);
    f.picker.next = [pickedBytes(png)];
    await f.posts.pickDraftPhotos(editor, replaceIndex: 1);
    expect(editor.images.every((e) => e.ready), isTrue);
    final removed = editor.images.removeAt(0);
    editor.mediaTouched = true;
    expect(await f.posts.saveDraft(editor), isTrue);
    await expectLater(
      f.current!.readMedia(
        removed.blobId,
        removed.selection!.byteLength,
        removed.selection!.sha256,
      ),
      throwsA(isA<PostStorageFailure>()),
    );
    expect((await f.posts.restoreDraft(editor.id))!.images.length, 1);
  });

  test('nine item cap is enforced even if platform ignores limit', () async {
    final editor = f.editor();
    f.picker.next = List.generate(12, (_) => pickedBytes(png));
    await f.posts.pickDraftPhotos(editor);
    expect(editor.images.length, 9);
    await f.posts.pickDraftPhotos(editor);
    expect(editor.images.length, 9);
  });

  test('partial upload retains successful items; manual retry only puts missing items', () async {
    final editor = await selected(3);
    f.api.rejected.add(1);
    expect(await f.posts.publish(editor), isTrue);
    await f.until(
      () =>
          f.posts.imageUploadProgress(editor.id)?.message != null &&
          f.posts.imageUploadProgress(editor.id)?.busy == false,
    );
    expect(f.api.putIndices, [0, 1, 2]);
    expect(f.api.received.keys.toSet(), {0, 2});
    final paused = await f.current!.get(editor.id);
    expect(paused!.state, 'ACCEPTED');
    expect(paused.data['mediaUploadPaused'], isTrue);
    f.api.rejected.clear();
    await f.posts.resumeImageUpload(editor.id);
    await f.until(() => f.posts.latestPublicationNotice != null);
    expect(f.api.putIndices, [0, 1, 2, 1]);
    expect(f.api.creates, 1);
    expect(
      f.api.received.values.every((b) => base64Encode(b) == base64Encode(png)),
      isTrue,
    );
    expect(
      (await f.current!.get(editor.id))!.data.containsKey('images'),
      isFalse,
    );
    final image = editor.images.first;
    await expectLater(
      f.current!.readMedia(
        image.blobId,
        image.selection!.byteLength,
        image.selection!.sha256,
      ),
      throwsA(isA<PostStorageFailure>()),
    );
  });

  test(
    'lost PUT receipt is reconciled and never resends an already uploaded item',
    () async {
      final editor = await selected(2);
      f.api.autoPublish = false;
      f.api.losePutOnce.add(0);
      expect(await f.posts.publish(editor), isTrue);
      await f.until(
        () => f.posts.imageUploadProgress(editor.id)?.message != null,
      );
      expect(f.api.putIndices, [0, 1]);
      await f.posts.resumeImageUpload(editor.id);
      expect(f.api.putIndices, [0, 1]);
      expect(f.api.creates, 1);
    },
  );

  test('lost CREATE response and restart keep original command and exact image intent', () async {
    final editor = await selected(1);
    f.api.createWait = Completer();
    expect(await f.posts.publish(editor), isTrue);
    await f.until(() => f.api.creates == 1);
    await f.restart();
    await f.until(() => f.posts.latestPublicationNotice != null);
    f.api.createWait!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(f.api.creates, 1);
    expect(f.api.putIndices, [0]);
  });

  test('explicit failed attempt editing keeps original identity/channel and images', () async {
    final editor = await selected(2);
    f.api.autoPublish = false;
    expect(await f.posts.publish(editor), isTrue);
    await f.until(() => f.posts.imageUploadProgress(editor.id)?.completed == 2);
    f.api.state = PostTaskState.failed;
    await f.posts.reconcile(editor.id);
    final retry = (await f.posts.editFailedTask(composerTask))!;
    expect(retry.identityId, editor.identityId);
    expect(retry.channelId, composerChannel);
    expect(
      retry.images.map((e) => e.mediaId),
      editor.images.map((e) => e.mediaId),
    );
    retry.images.removeLast();
    retry.body = '修改后的文字';
    retry.mediaTouched = true;
    f.api.autoPublish = true;
    expect(await f.posts.publish(retry), isTrue);
    await f.until(() => f.posts.latestPublicationNotice != null);
    expect(f.api.retries, 1);
    expect(f.api.images.length, 1);
    expect(f.api.version, 2);
  });

  test(
    'new retry intent clears previous partial-upload failure pause',
    () async {
      final editor = await selected(2);
      f.api.rejected.add(1);
      expect(await f.posts.publish(editor), isTrue);
      await f.until(
        () => f.posts.imageUploadProgress(editor.id)?.busy == false,
      );
      expect(f.posts.imageUploadProgress(editor.id)!.message, isNotNull);
      f.api.state = PostTaskState.failed;
      await f.posts.reconcile(editor.id);
      final retry = (await f.posts.editFailedTask(composerTask))!;
      retry.images.removeLast();
      retry.mediaTouched = true;
      f.api.rejected.clear();
      expect(await f.posts.publish(retry), isTrue);
      expect(
        (await f.current!.get(editor.id))!.data['mediaUploadPaused'],
        isNull,
      );
      await f.until(() => f.posts.latestPublicationNotice != null);
      expect(f.api.retries, 1);
      expect(f.api.putIndices, [0, 1, 0]);
      expect((await f.current!.get(editor.id))!.state, 'PUBLISHED');
    },
  );

  test('confirmed user cancellation preserves original draft images', () async {
    final editor = await selected(1);
    f.api.rejected.add(0);
    expect(await f.posts.publish(editor), isTrue);
    await f.until(
      () => f.posts.imageUploadProgress(editor.id)?.message != null,
    );
    await f.posts.cancelTask(composerTask);
    final draft = (await f.current!.list()).singleWhere((e) => e.isDraft);
    final restored = (await f.posts.restoreDraft(draft.id))!;
    expect(restored.images.length, 1);
    expect(
      await f.posts.draftPhotoBytes(restored, restored.images.single),
      png,
    );
    expect(f.api.creates, 1);
  });

  test(
    'late picker result after loss of authority never imports pixels',
    () async {
      final editor = f.editor();
      f.picker.wait = Completer();
      final picking = f.posts.pickDraftPhotos(editor);
      await f.until(() => editor.persisted);
      f.auth.sessions.sessionUnavailable(f.auth.store.current!.session!.token);
      var reads = 0;
      f.picker.wait!.complete([
        PostPickedFile(
          length: () async {
            reads++;
            return png.length;
          },
          openRead: () => Stream.value(png),
        ),
      ]);
      await picking;
      expect(reads, 0);
      expect(editor.images, isEmpty);
    },
  );

  test(
    'authority loss while draining startup picker cannot revive old drafts',
    () async {
      final editor = await selected(1);
      f.picker.lostWait = Completer<void>();
      await f.restart();
      await f.until(() => f.picker.discarded == 2);
      final opening = f.posts.restoreDraft(editor.id);
      f.auth.sessions.sessionUnavailable(f.auth.store.current!.session!.token);
      f.picker.lostWait!.complete();
      expect(await opening, isNull);
      expect(f.posts.personalItems, isEmpty);
      expect(f.posts.available, isFalse);
    },
  );

  test('interrupted native picker queue is drained without cross-account attachment', () async {
    final editor = f.editor()..pickerPending = true;
    expect(await f.posts.saveDraft(editor), isTrue);
    await f.restart();
    final restored = await f.posts.restoreDraft(editor.id);
    expect(restored!.mediaError, contains('上次选图被中断'));
    final record = (await f.current!.get(editor.id))!;
    expect(record.data['pickerPending'], isNull);
    expect(record.data['pickerInterrupted'], isTrue);
    expect(DraftPostImage.list(record.data['images']), isEmpty);
    expect(f.picker.discarded, 2);
  });

  test('encrypted originals span bounded chunks, roll back missing references and delete with draft', () async {
    final bytes = Uint8List.fromList(
      List.generate(2 * 1024 * 1024 + 31, (i) => (i * 7) % 251),
    );
    final blob = newPostMediaId(),
        id = newPostMediaId(),
        media = newPostMediaId();
    final selection = PostImageSelection.fromJson({
      'mediaId': media,
      'sha256': hashes.sha256.convert(bytes).toString(),
      'mimeType': 'image/png',
      'byteLength': bytes.length,
      'width': 2,
      'height': 2,
    });
    final data = {
      'title': 'chunk draft',
      'body': '',
      'images': [
        DraftPostImage(
          blobId: blob,
          mediaId: media,
          selection: selection,
        ).toJson(),
      ],
    };
    final row = await f.current!.saveMediaDraft(id, null, data, {blob: bytes});
    expect(
      await f.current!.readMedia(blob, bytes.length, selection.sha256),
      bytes,
    );
    await expectLater(
      f.current!.saveMediaDraft('bad-draft', null, {
        ...data,
        'images': [
          DraftPostImage(
            blobId: newPostMediaId(),
            mediaId: media,
            selection: selection,
          ).toJson(),
        ],
      }, {}),
      throwsA(isA<PostStorageFailure>()),
    );
    expect(await f.current!.get('bad-draft'), isNull);
    expect(
      await f.current!.readMedia(blob, bytes.length, selection.sha256),
      bytes,
    );
    await f.current!.deleteDraft(id, row.revision);
    await expectLater(
      f.current!.readMedia(blob, bytes.length, selection.sha256),
      throwsA(isA<PostStorageFailure>()),
    );
  });
  test('explicit NOT_ACCEPTED recovery copies original image refs before compacting old intent', () async {
    final e = await selected(1);
    final current = (await f.current!.get(e.id))!;
    final images = e.images.map((e) => e.selection!.toJson()).toList();
    final payload = {
      'channelId': composerChannel,
      'identityId': e.identityId,
      'title': e.title,
      'body': e.body,
      'images': images,
    };
    final intent = StoredPostIntent(
      commandId: AuthCrypto.randomEncoded(16),
      operation: 'CREATE',
      digest: PostProtocol.digest(
        PostProtocol.withImages(
          PostProtocol.create(
            channelId: composerChannel,
            identityId: e.identityId!,
            title: e.title,
            body: e.body,
          ),
          images,
        ),
      ),
      payload: payload,
    );
    final submitted = await f.current!.submitDraft(
      e.id,
      current.revision,
      intent,
      current.data,
    );
    await f.current!.recordResult(
      e.id,
      submitted.revision,
      'NOT_ACCEPTED',
      submitted.data,
    );
    final restored = (await f.posts.recoverUnaccepted(e.id))!;
    expect(restored.images.single.mediaId, e.images.single.mediaId);
    expect(
      await f.posts.draftPhotoBytes(restored, restored.images.single),
      png,
    );
    expect((await f.current!.get(e.id))!.data.containsKey('images'), isFalse);
    expect(f.api.creates, 0);
  });
}
