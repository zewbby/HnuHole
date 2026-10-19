// Runs only against the owned TLS/PostgreSQL harness. The private fixture and
// temporary CA are supplied by Go; shipped transport verification stays enabled.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/posts/post_upload_models.dart';

void check(bool value, String code) {
  if (!value) throw FormatException(code);
}

Future<void> main(List<String> args) async {
  final f =
      jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
  final phase = args[1];
  final out = <String, dynamic>{'status': 'PASS', 'phase': phase};
  final tls = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(f['certificatePem'] as String));
  final http = CommentHttp(
    Uri.parse(f['url'] as String),
    client: HttpClient(context: tls),
  );
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
  }) async => (await http.send(
    f['token'] as String,
    method,
    path,
    body: body,
    query: query,
    bytes: bytes,
    mime: mime,
  )).value;
  final binding = CommentBinding(
    postId: f['postId'] as String,
    identityId: f['identityId'] as String,
    rootCommentId: f['root'] as String?,
    targetCommentId: f['target'] as String?,
  );
  final api = HttpCommentApi(request, (i, v) async {
    await request(
      'PUT',
      '/api/v1/me/comment-tasks/${i.taskId}/attempts/$v/image',
      bytes: base64Decode(f['imageBytes'] as String),
      mime: i.content!.image!.selection.mimeType,
    );
  });
  CommentIntent intent() => CommentIntent(
    commandId: f['key'] as String,
    taskId: f['taskId'] as String,
    operation: phase == 'retry'
        ? CommentOperation.retry
        : phase == 'abandon'
        ? CommentOperation.abandon
        : CommentOperation.create,
    binding: binding,
    expectedAttemptVersion: phase == 'retry' || phase == 'abandon'
        ? f['version'] as int
        : null,
    content: phase == 'abandon'
        ? null
        : CommentContent(
            body: f['body'] as String,
            image: f['image'] == null
                ? null
                : CommentImage(
                    blobId: f['image']['mediaId'] as String,
                    selection: PostImageSelection.fromJson(f['image']),
                  ),
          ),
  );
  try {
    if ({'create', 'retry', 'abandon'}.contains(phase)) {
      CommentTask? t;
      try {
        t = await api.execute(intent());
      } on CommentHttpFailure {
        out['unknownObserved'] = true;
        t = await api.query(intent());
      }
      check(t != null, 'missing task');
      out['taskId'] = t!.taskId;
      out['state'] = t.state.name;
      out['version'] = t.attemptVersion;
    } else if (phase == 'read') {
      final t = await api.queryTask(
        taskId: f['taskId'] as String,
        binding: binding,
      );
      check(t!.state == CommentTaskState.published, 'not published');
      out['commentId'] = t.commentId;
      final page = await request(
        'GET',
        '/api/v1/posts/${binding.postId}/comments',
      );
      final rows = page['comments'] as List;
      check(rows.isNotEmpty, 'missing public row');
      final row = await request(
        'GET',
        '/api/v1/posts/${binding.postId}/comments/${t.commentId}',
      );
      check(row['body'] == f['body'], 'changed body');
      final location = await request(
        'GET',
        '/api/v1/posts/${binding.postId}/comments/${t.commentId}/location',
      );
      check(location['commentId'] == t.commentId, 'wrong location');
      final history = await request(
        'GET',
        '/api/v1/me/comments',
        query: {'identityId': binding.identityId},
      );
      check(
        (history['items'] as List).any((r) => r['id'] == t.commentId),
        'history missing',
      );
      if (row['image'] case final Map image) {
        final original = await http.image(
          f['token'] as String,
          '/api/v1/posts/${binding.postId}/comments/${t.commentId}/images/${image['contentVersionId']}/original',
          image['mimeType'] as String,
        );
        check(
          base64Encode(original.bytes) == f['imageBytes'],
          'changed original',
        );
      }
    } else if (phase == 'failed') {
      final t = await api.queryTask(
        taskId: f['taskId'] as String,
        binding: binding,
      );
      check(t!.state == CommentTaskState.failed, 'not failed');
      check(t.canAbandon, 'cannot abandon');
      out['version'] = t.attemptVersion;
    } else if (phase == 'like') {
      final path =
          '/api/v1/comments/${f['commentId']}/like-commands/${f['key']}';
      final first = await request('PUT', path, body: {'liked': true});
      final replay = await request('PUT', path, body: {'liked': true});
      check(
        first['likeCount'] == 1 && replay['likeCount'] == 1,
        'duplicate like',
      );
    } else if (phase == 'delete') {
      final path =
          '/api/v1/comments/${f['commentId']}/delete-commands/${f['key']}';
      final first = await request('PUT', path, body: {});
      final replay = await request(
        'GET',
        '/api/v1/comment-commands/${f['key']}',
      );
      check(
        first['deletedCount'] == replay['deletedCount'] &&
            first['state'] == 'APPLIED',
        'delete receipt',
      );
    } else {
      throw const FormatException('unknown phase');
    }
  } catch (e) {
    out['status'] = 'FAIL';
    out['check'] = e is FormatException ? e.message : 'transport_or_protocol';
  } finally {
    http.close();
    await File(args[2]).writeAsString(jsonEncode(out));
  }
  if (out['status'] == 'FAIL') exitCode = 1;
}
