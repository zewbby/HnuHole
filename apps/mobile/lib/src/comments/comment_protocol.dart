import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;

import '../posts/post_protocol.dart';
import '../posts/post_upload_models.dart';

/// Comment-only framing. Business validation and final C authorization are
/// separate so rejected input can still have an immutable command fingerprint.
class CommentProtocol {
  static const maxFrameBytes = 262144;

  static String commandId(String value) => PostProtocol.commandId(value);

  static Uint8List create({
    required String taskId,
    required String postId,
    required String identityId,
    String? rootCommentId,
    String? targetCommentId,
    required String body,
    PostImageSelection? image,
  }) {
    if ((rootCommentId == null) != (targetCommentId == null)) {
      throw const FormatException('Reply requires root and exact target');
    }
    return _frame(1, [
      _id(taskId),
      _id(postId),
      _id(identityId),
      rootCommentId == null ? Uint8List(16) : _id(rootCommentId),
      targetCommentId == null ? Uint8List(16) : _id(targetCommentId),
      _text(body),
      _image(image),
    ]);
  }

  static Uint8List retry({
    required String taskId,
    required int expectedAttemptVersion,
    required String body,
    PostImageSelection? image,
  }) => _frame(2, [
    _id(taskId),
    _version(expectedAttemptVersion),
    _text(body),
    _image(image),
  ]);

  static Uint8List abandon({
    required String taskId,
    required int expectedAttemptVersion,
  }) => _frame(3, [_id(taskId), _version(expectedAttemptVersion)]);

  static Uint8List delete({required String commentId}) =>
      _frame(4, [_id(commentId)]);

  static Uint8List setLike({required String commentId, required bool liked}) =>
      _frame(5, [
        _id(commentId),
        [liked ? 1 : 0],
      ]);

  static String digest(List<int> frame) =>
      hashes.sha256.convert(frame).toString();

  static Uint8List _frame(int operation, List<List<int>> fields) {
    final bytes = BytesBuilder(copy: false)
      ..add(ascii.encode('HNUHOLE/COMMENT-COMMAND/V1'))
      ..addByte(0)
      ..addByte(operation);
    for (final field in fields) {
      bytes.add(field);
    }
    if (bytes.length > maxFrameBytes) {
      throw const FormatException('Comment command frame too large');
    }
    return bytes.takeBytes();
  }

  static Uint8List _id(String value) {
    final hex = PostProtocol.resourceId(value).replaceAll('-', '');
    return Uint8List.fromList([
      for (var i = 0; i < 16; i++)
        int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ]);
  }

  static Uint8List _version(int value) =>
      (ByteData(8)..setUint64(0, PostProtocol.version(value), Endian.big))
          .buffer
          .asUint8List();

  static List<int> _text(String value) {
    PostContentRules.scalarText(value);
    final bytes = utf8.encode(value);
    if (bytes.length > maxFrameBytes) {
      throw const FormatException('Comment framing text too large');
    }
    return [
      ...(ByteData(
        4,
      )..setUint32(0, bytes.length, Endian.big)).buffer.asUint8List(),
      ...bytes,
    ];
  }

  static List<int> _image(PostImageSelection? image) {
    if (image == null) return [0];
    // Reuse the existing manifest validator rather than expanding post limits
    // or accepting an unchecked caller implementation of the selection type.
    final valid = PostImageSelection.fromJson(image.toJson());
    return [
      1,
      ..._id(valid.mediaId),
      ..._text(valid.sha256),
      ..._text(valid.mimeType),
      for (final value in [valid.byteLength, valid.width, valid.height])
        ...(ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List(),
    ];
  }
}
