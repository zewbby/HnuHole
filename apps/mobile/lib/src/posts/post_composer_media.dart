part of 'post_controller.dart';

class PostImageUploadProgress {
  PostImageUploadProgress({
    required this.total,
    this.completed = 0,
    this.busy = true,
    this.message,
  });
  final int total;
  int completed;
  bool busy;
  String? message;
  final failed = <int>{};
}

extension PostComposerMedia on PostController {
  Future<List<StoredPostEntry>> _restorePickerCheckpoint(
    PostStore store,
    List<StoredPostEntry> entries,
    int epoch,
  ) async {
    if (_photoPicker == null) return entries;
    if (!_lostSelectionChecked) {
      _lostSelectionChecked = true;
      try {
        await _photoPicker.discardUnboundLostSelection();
      } catch (_) {
        /* No account-unbound pixels are imported. */
      }
    }
    if (_disposed || epoch != _epoch) return entries;
    final result = <StoredPostEntry>[];
    for (final entry in entries) {
      if (entry.isDraft && entry.data['pickerPending'] == true) {
        final data = Map<String, dynamic>.of(entry.data)
          ..remove('pickerPending');
        data['pickerInterrupted'] = true;
        result.add(await store.saveDraft(entry.id, entry.revision, data));
      } else {
        result.add(entry);
      }
    }
    return result;
  }

  void clearEditorMedia(PostDraftEditor e) {
    e.images.clear();
    e._originals.clear();
    e.mediaError = null;
  }

  Future<void> pickDraftPhotos(PostDraftEditor e, {int? replaceIndex}) async {
    if (!editorCurrent(e) ||
        e.submitted ||
        e.mediaBusy ||
        _photoPicker == null) {
      return;
    }
    final limit = replaceIndex == null ? 9 - e.images.length : 1;
    if (limit < 1 ||
        replaceIndex != null &&
            (replaceIndex < 0 || replaceIndex >= e.images.length)) {
      return;
    }
    e.mediaBusy = true;
    e.pickerPending = true;
    e.mediaError = null;
    _notify();
    try {
      // Store the text and existing originals before opening an external picker.
      if (!await saveDraft(e) || !editorCurrent(e)) return;
      final files = await _photoPicker.pick(limit);
      if (!editorCurrent(e)) return;
      for (final file in files.take(limit)) {
        final mediaId = newPostMediaId(), blobId = newPostMediaId();
        final index = replaceIndex ?? e.images.length;
        final pending = DraftPostImage(blobId: blobId, mediaId: mediaId);
        if (replaceIndex == null) {
          e.images.add(pending);
        } else {
          e.images[index] = pending;
        }
        e.mediaTouched = true;
        e.saved = false;
        _notify();
        try {
          final result = await inspectPostPhoto(
            file,
            mediaId,
          ).timeout(const Duration(seconds: 20));
          if (!editorCurrent(e)) return;
          e.images[index] = DraftPostImage(
            blobId: blobId,
            mediaId: mediaId,
            selection: result.selection,
          );
          e._originals[blobId] = result.bytes;
        } catch (_) {
          if (!editorCurrent(e)) return;
          e.mediaError = '部分图片无法读取或不符合格式、大小限制，请重新选择或移除。';
        }
        if (!editorCurrent(e)) return;
        // A failed disk write leaves this original in the editor for Retry.
        await saveDraft(e);
      }
    } on PostPhotoSelectionUnavailable {
      if (editorCurrent(e)) e.mediaError = '此设备的原格式选图尚未启用，文字和已保存图片仍保留。';
    } catch (_) {
      if (editorCurrent(e)) e.mediaError = '暂时无法选择图片，已保留其他图片和文字。';
    } finally {
      e.mediaBusy = false;
      e.pickerPending = false;
      if (editorCurrent(e)) {
        if (!e.isRetry &&
            e.images.isEmpty &&
            !PostContentRules.hasMeaningfulText(e.title) &&
            !PostContentRules.hasMeaningfulText(e.body)) {
          await discardDraft(e);
        } else {
          await saveDraft(e);
        }
        _notify();
      }
    }
  }

  Future<Uint8List> draftPhotoBytes(
    PostDraftEditor e,
    DraftPostImage image,
  ) async {
    if (!editorCurrent(e) || image.selection == null) {
      throw const PostStorageFailure();
    }
    final pending = e._originals[image.blobId];
    if (pending != null) return pending;
    final a = await _authority(storage: true);
    final selection = image.selection!;
    final bytes = await a.store!.readMedia(
      image.blobId,
      selection.byteLength,
      selection.sha256,
    );
    if (!_current(a) || !editorCurrent(e)) throw const PostStorageFailure();
    return bytes;
  }

  Future<void> _preserveCancelledImages(
    _PostAuthority a,
    StoredPostEntry entry,
  ) async {
    if (entry.intents.last.operation != 'CANCEL' ||
        DraftPostImage.list(entry.data['images']).isEmpty) {
      return;
    }
    final id = 'cancelled-${entry.id}';
    if (await a.store!.get(id) != null) return;
    if (!_current(a)) throw _StalePostAuthority();
    await a.store!.createDraft(id, {
      'channelId': entry.data['channelId'],
      'identityId': entry.data['identityId'],
      'title': entry.data['title'] ?? '',
      'body': entry.data['body'] ?? '',
      'images': entry.data['images'],
      'editedAt': _clock().toUtc().toIso8601String(),
    });
  }

  PostImageUploadProgress? imageUploadProgress(String id) => _imageProgress[id];
  Future<void> resumeImageUpload(String id, {bool automatic = false}) async {
    _PostAuthority? a;
    String? key;
    PostImageUploadProgress? progress;
    StoredPostEntry? original;
    var protectedRequest = true;
    var entered = false;
    try {
      a = await _authority(storage: true);
      if (_uploadApi == null) return;
      key = '${a.epoch}/$id';
      if (!_uploadingImages.add(key)) return;
      entered = true;
      final entry = await a.store!.get(id);
      original = entry;
      if (!_current(a) ||
          entry == null ||
          entry.state != 'ACCEPTED' ||
          entry.intents.isEmpty ||
          !{'CREATE', 'RETRY'}.contains(entry.intents.last.operation) ||
          automatic &&
              (entry.data['mediaUploadPaused'] == true ||
                  _imageProgress[id]?.message != null)) {
        return;
      }
      final images = DraftPostImage.list(entry.data['images']);
      if (images.isEmpty) return;
      final manifest = PostImageSelection.list(
        entry.intents.last.payload['images'],
      );
      if (images.any((e) => !e.ready) ||
          jsonEncode(images.map((e) => e.selection!.toJson()).toList()) !=
              jsonEncode(manifest.map((e) => e.toJson()).toList())) {
        throw const PostStorageFailure();
      }
      final task = entry.data['taskId'] as String,
          version = entry.data['attemptVersion'] as int;
      progress = PostImageUploadProgress(total: images.length);
      _imageProgress[id] = progress;
      _notify();
      final state = await _accept(
        a,
        await _uploadApi.uploads(
          sessionToken: a.token,
          taskId: task,
          version: version,
        ),
      );
      if (state.postId != entry.data['postId'] ||
          jsonEncode(state.images.map((e) => e.toJson()).toList()) !=
              jsonEncode(manifest.map((e) => e.toJson()).toList())) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      bool current() => _current(a!);
      Future<bool> stillAccepted() async {
        if (!current()) return false;
        final latest = await a!.store!.get(id);
        return current() &&
            latest?.state == 'ACCEPTED' &&
            latest!.intents.last.commandId == entry.intents.last.commandId &&
            latest.data['attemptVersion'] == version;
      }

      for (var i = 0; i < images.length; i++) {
        if (state.uploaded[i]) {
          progress.completed++;
          _notify();
          continue;
        }
        if (!await stillAccepted()) return;
        try {
          protectedRequest = true;
          final selected = manifest[i];
          final bytes = await a.store!.readMedia(
            images[i].blobId,
            selected.byteLength,
            selected.sha256,
          );
          if (!await stillAccepted()) return;
          final watch = Stopwatch()..start();
          final response = await _uploadApi.uploadGrant(
            sessionToken: a.token,
            taskId: task,
            version: version,
            mediaId: selected.mediaId,
          );
          final grant = await _accept(a, response);
          if (!await stillAccepted() ||
              grant.expiresAt.difference(response.serverTime) <=
                  watch.elapsed) {
            return;
          }
          protectedRequest = false; // Upload capability rejection must not revoke a Bearer session.
          await _uploadApi.putOriginal(
            uploadToken: grant.uploadToken,
            taskId: task,
            version: version,
            image: selected,
            bytes: bytes,
          );
          if (!await stillAccepted()) return;
          progress.completed++;
        } catch (error) {
          if (!_current(a)) return;
          if (protectedRequest &&
              error is PostFailure &&
              {
                PostFailureKind.unauthorized,
                PostFailureKind.unavailable,
              }.contains(error.kind)) {
            _failure(error, a);
            return;
          }
          progress.failed.add(i);
        }
        _notify();
      }
      if (!_current(a)) return;
      if (progress.failed.isNotEmpty) {
        progress.message =
            '${progress.failed.length}张图片尚未确认上传，可继续补传；已完成的图片会保留。';
        final latest = await a.store!.get(id);
        if (await stillAccepted() && latest != null) {
          await a.store!.recordResult(
            id,
            latest.revision,
            latest.state,
            Map<String, dynamic>.of(latest.data)..['mediaUploadPaused'] = true,
          );
          await _refreshLocal(a);
        }
      }
      if (_current(a)) unawaited(reconcile(id));
    } catch (error) {
      if (a != null && _current(a)) {
        if (protectedRequest &&
            error is PostFailure &&
            {
              PostFailureKind.unauthorized,
              PostFailureKind.unavailable,
            }.contains(error.kind)) {
          _failure(error, a);
        }
        progress ??= PostImageUploadProgress(
          total: DraftPostImage.list(original?.data['images']).length,
        );
        progress.message = '图片状态暂时无法核对，请稍后继续上传。';
        _imageProgress[id] = progress;
      }
    } finally {
      if (entered && key != null) _uploadingImages.remove(key);
      if (progress != null) progress.busy = false;
      if (a != null && _current(a)) _notify();
    }
  }
}
