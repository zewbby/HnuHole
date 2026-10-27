import 'dart:async';
import 'dart:math';

import '../auth/auth_crypto.dart';
import 'comment_http.dart';

const commentSnapshotUnavailableCodes = {
  'COMMENT_SNAPSHOT_UNAVAILABLE',
  'COMMENT_SNAPSHOT_CAPACITY',
  'COMMENT_SNAPSHOT_INTEGRITY',
};

String commentSnapshotNonce() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  if (bytes.every((b) => b == 0)) bytes[0] = 1;
  return AuthCrypto.encode(bytes);
}

class CommentReadCancelled implements Exception {
  const CommentReadCancelled();
}

/// Owns the one logical retry budget for a snapshot page. Transport and runtime
/// never retry it again. The initial nonce survives response loss and the delay.
class CommentSnapshotReader {
  CommentSnapshotReader(this.request, {Future<void> Function()? pause})
    : _pause =
          pause ??
          (() => Future<void>.delayed(const Duration(milliseconds: 250)));

  final CommentRequest request;
  final Future<void> Function() _pause;

  Future<Map<String, dynamic>> load(
    String path, {
    Map<String, String>? query,
    String? nonce,
    required bool Function() current,
  }) async {
    final initial = query?['cursor'] == null;
    final requestNonce = initial ? nonce ?? commentSnapshotNonce() : null;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!current()) throw const CommentReadCancelled();
      try {
        final value = await request(
          'GET',
          path,
          query: query,
          snapshotRequest: requestNonce,
        );
        if (!current()) throw const CommentReadCancelled();
        return value;
      } on CommentHttpFailure catch (e) {
        final temporary =
            (e.status == null && {'TIMEOUT', 'TRANSPORT'}.contains(e.code)) ||
            e.status == 503 && e.code == 'COMMENT_SNAPSHOT_UNAVAILABLE';
        if (attempt != 0 || !temporary || !current()) rethrow;
        await _pause();
      }
    }
    throw StateError('Snapshot retry budget exhausted');
  }
}

bool commentCursorInvalid(Object e) =>
    e is CommentHttpFailure && e.status == 400 && e.code == 'CURSOR_INVALID';

String commentSnapshotMessage(Object e, {bool replies = false}) {
  final list = replies ? '这层回复' : '评论列表';
  if (commentCursorInvalid(e)) {
    return '$list已更新，请刷新${replies ? '这层回复' : '评论'}。';
  }
  if (e is CommentHttpFailure) {
    if (e.code == 'COMMENT_SNAPSHOT_TOO_LARGE') return '$list规模超限，暂时无法加载。';
    if (e.code == 'COMMENT_SNAPSHOT_CAPACITY') return '$list暂时繁忙，请稍后重试。';
    if (e.status == 429) {
      final seconds = e.retryAfterSeconds;
      return seconds == null ? '读取过于频繁，请稍后重试。' : '读取过于频繁，请在 $seconds 秒后重试。';
    }
  }
  return replies ? '回复暂时无法读取，请重试。' : '评论暂时无法读取，请重新核对。';
}
