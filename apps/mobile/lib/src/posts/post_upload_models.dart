import 'dart:math';

import 'post_models.dart';
import 'post_protocol.dart';

String newPostMediaId() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class PostImageSelection {
  PostImageSelection._(
    this.mediaId,
    this.sha256,
    this.mimeType,
    this.byteLength,
    this.width,
    this.height,
  );
  final String mediaId, sha256, mimeType;
  final int byteLength, width, height;
  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'sha256': sha256,
    'mimeType': mimeType,
    'byteLength': byteLength,
    'width': width,
    'height': height,
  };
  static PostImageSelection fromJson(Object? raw) {
    final m = PostJson.record(raw, {
      'mediaId',
      'sha256',
      'mimeType',
      'byteLength',
      'width',
      'height',
    });
    final width = PostJson.integer(m, 'width', 1, 16384),
        height = PostJson.integer(m, 'height', 1, 16384);
    final mime = PostJson.text(m, 'mimeType');
    if (width * height > 12 * 1024 * 1024 ||
        !{
          'image/jpeg',
          'image/png',
          'image/gif',
          'image/webp',
        }.contains(mime)) {
      throw const FormatException('Invalid image selection');
    }
    return PostImageSelection._(
      PostJson.id(m, 'mediaId'),
      PostProtocol.digestValue(PostJson.text(m, 'sha256')),
      mime,
      PostJson.integer(m, 'byteLength', 1, 10 * 1024 * 1024),
      width,
      height,
    );
  }

  static List<PostImageSelection> list(Object? raw) {
    if (raw is! List || raw.length > 9) {
      throw const FormatException('Invalid image selection count');
    }
    final values = raw.map(fromJson).toList();
    if (values.map((e) => e.mediaId).toSet().length != values.length) {
      throw const FormatException('Duplicate media ID');
    }
    return List.unmodifiable(values);
  }
}

/// Only local random references and metadata are persisted, never picker paths.
class DraftPostImage {
  DraftPostImage({
    required this.blobId,
    required this.mediaId,
    this.selection,
  }) {
    PostProtocol.resourceId(blobId);
    PostProtocol.resourceId(mediaId);
    if (selection != null && selection!.mediaId != mediaId) {
      throw const FormatException('Mismatched selection');
    }
  }
  final String blobId, mediaId;
  final PostImageSelection? selection;
  bool get ready => selection != null;
  Map<String, dynamic> toJson() => {
    'blobId': blobId,
    'mediaId': mediaId,
    if (selection != null) 'selection': selection!.toJson(),
  };
  static DraftPostImage fromJson(Object? raw) {
    final m = PostJson.record(
      raw,
      {'blobId', 'mediaId'},
      optional: {'selection'},
    );
    return DraftPostImage(
      blobId: PostJson.id(m, 'blobId'),
      mediaId: PostJson.id(m, 'mediaId'),
      selection: m.containsKey('selection')
          ? PostImageSelection.fromJson(m['selection'])
          : null,
    );
  }

  static List<DraftPostImage> list(Object? raw) {
    if (raw == null) return [];
    if (raw is! List || raw.length > 9) {
      throw const FormatException('Invalid draft images');
    }
    final values = raw.map(fromJson).toList();
    if (values.map((e) => e.mediaId).toSet().length != values.length ||
        values.map((e) => e.blobId).toSet().length != values.length) {
      throw const FormatException('Duplicate draft image');
    }
    return values;
  }
}

class PostUploadState {
  PostUploadState._(
    this.taskId,
    this.postId,
    this.version,
    this.images,
    this.uploaded,
  );
  final String taskId, postId;
  final int version;
  final List<PostImageSelection> images;
  final List<bool> uploaded;
  static PostUploadState fromJson(Object? raw, String task, int version) {
    final m = PostJson.record(raw, {
      'taskId',
      'postId',
      'attemptVersion',
      'items',
    });
    if (PostJson.id(m, 'taskId') != task ||
        PostJson.integer(m, 'attemptVersion', 1, 2147483647) != version ||
        m['items'] is! List) {
      throw const FormatException('Mismatched upload state');
    }
    final items = m['items'] as List;
    final selections = <Object?>[], uploaded = <bool>[];
    for (var i = 0; i < items.length; i++) {
      final item = PostJson.record(items[i], {
        'mediaId',
        'sha256',
        'mimeType',
        'byteLength',
        'width',
        'height',
        'position',
        'uploaded',
      });
      if (PostJson.integer(item, 'position', 0, 8) != i) {
        throw const FormatException('Invalid upload order');
      }
      uploaded.add(PostJson.boolean(item, 'uploaded'));
      selections.add({
        for (final k in [
          'mediaId',
          'sha256',
          'mimeType',
          'byteLength',
          'width',
          'height',
        ])
          k: item[k],
      });
    }
    return PostUploadState._(
      task,
      PostJson.id(m, 'postId'),
      version,
      PostImageSelection.list(selections),
      List.unmodifiable(uploaded),
    );
  }
}

class PostUploadGrant {
  PostUploadGrant({required this.uploadToken, required this.expiresAt});
  final String uploadToken;
  final DateTime expiresAt;
  @override
  String toString() => 'PostUploadGrant(redacted)';
}
