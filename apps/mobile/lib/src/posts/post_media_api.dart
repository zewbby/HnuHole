import 'dart:typed_data';

import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

/// Host-only protected transport. Credentials never enter viewer models/providers.
abstract interface class PostMediaApi {
  Future<PostResponse<PostMediaManifest>> imageManifest({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<Uint8List>> imageBytes({
    required String sessionToken,
    required String postId,
    required PostMediaImage image,
  });
}

class PostMediaManifest {
  PostMediaManifest._(this.postId, this.images, this.accessValidUntil);
  final String postId;
  final List<PostMediaImage> images;
  final DateTime accessValidUntil;

  static PostMediaManifest fromJson(Object? raw, String expectedPost) {
    final m = PostJson.record(raw, {'postId', 'images', 'accessValidUntil'});
    final post = PostJson.id(m, 'postId');
    final items = m['images'];
    if (post != expectedPost || items is! List || items.length > 9) {
      throw const FormatException('Invalid post media group');
    }
    final images = <PostMediaImage>[];
    final versions = <String>{}, media = <String>{};
    for (var i = 0; i < items.length; i++) {
      final image = PostMediaImage._fromJson(items[i], post, i);
      if (!versions.add(image.contentVersionId) || !media.add(image.mediaId)) {
        throw const FormatException('Repeated post media ID');
      }
      images.add(image);
    }
    return PostMediaManifest._(
      post,
      List.unmodifiable(images),
      PostJson.date(m, 'accessValidUntil'),
    );
  }
}

class PostMediaImage {
  PostMediaImage._({
    required this.mediaId,
    required this.contentVersionId,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.frames,
    required this.saveAllowed,
    required this.path,
    required this.mimeType,
    required this.byteLength,
  });
  final String mediaId, contentVersionId, path, mimeType;
  final int pixelWidth, pixelHeight, frames, byteLength;
  final bool saveAllowed;
  static const maxBytes = 10 * 1024 * 1024;

  static PostMediaImage _fromJson(Object? raw, String post, int position) {
    final m = PostJson.record(raw, {
      'mediaId',
      'contentVersionId',
      'position',
      'width',
      'height',
      'pixelWidth',
      'pixelHeight',
      'frames',
      'animated',
      'saveAllowed',
      'thumbnail',
      'full',
      'original',
    });
    final id = PostJson.id(m, 'contentVersionId');
    final width = PostJson.integer(m, 'width', 1, 16384);
    final height = PostJson.integer(m, 'height', 1, 16384);
    final pw = PostJson.integer(m, 'pixelWidth', 1, 16384);
    final ph = PostJson.integer(m, 'pixelHeight', 1, 16384);
    final frames = PostJson.integer(m, 'frames', 1, 120);
    final expectedPath = '/api/v1/posts/$post/images/$id/original';
    final source = PostJson.record(m['original'], {
      'path',
      'mimeType',
      'byteLength',
    });
    final mime = PostJson.text(source, 'mimeType');
    final size = PostJson.integer(source, 'byteLength', 1, maxBytes);
    if (PostJson.integer(m, 'position', 0, 8) != position ||
        width * height > 12 * 1024 * 1024 ||
        !((pw == width && ph == height) || (pw == height && ph == width)) ||
        PostJson.boolean(m, 'animated') != (frames > 1) ||
        frames > 1 &&
            (width * height > 1024 * 1024 ||
                width * height * frames > 16 * 1024 * 1024) ||
        !{
          'image/jpeg',
          'image/png',
          'image/gif',
          'image/webp',
        }.contains(mime)) {
      throw const FormatException('Invalid post image metadata');
    }
    for (final key in ['thumbnail', 'full', 'original']) {
      final s = PostJson.record(m[key], {'path', 'mimeType', 'byteLength'});
      if (s['path'] != expectedPath ||
          s['mimeType'] != mime ||
          s['byteLength'] != size) {
        throw const FormatException('Invalid protected post image source');
      }
    }
    return PostMediaImage._(
      mediaId: PostJson.id(m, 'mediaId'),
      contentVersionId: id,
      pixelWidth: pw,
      pixelHeight: ph,
      frames: frames,
      saveAllowed: PostJson.boolean(m, 'saveAllowed'),
      path: expectedPath,
      mimeType: mime,
      byteLength: size,
    );
  }

  void validatePost(String postId) {
    PostProtocol.resourceId(postId);
    if (path != '/api/v1/posts/$postId/images/$contentVersionId/original') {
      throw const FormatException('Mismatched protected image resource');
    }
  }
}
