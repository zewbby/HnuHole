import '../rate_limit.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../auth/auth_crypto.dart';
import '../posts/post_models.dart';
import '../system_notifications/governance_api.dart' show GovernanceStrictJson;
import 'comment_api.dart';
import 'comment_models.dart';
import 'comment_protocol.dart';

class CommentHttpFailure implements Exception {
  const CommentHttpFailure(this.status, this.code, {this.retryAfterSeconds});
  final int? retryAfterSeconds;
  final int? status;
  final String code;
}

typedef CommentRequest = Future<Map<String, dynamic>> Function(
  String method,
  String path, {
  Map<String, dynamic>? body,
  Map<String, String>? query,
  Uint8List? bytes,
  String? mime,
});

/// Fixed HTTPS C origin, bounded strict JSON, no redirects or command replay.
class CommentHttp {
  CommentHttp(this.origin, {HttpClient? client})
    : _client = client ?? HttpClient() {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !{'', '/'}.contains(origin.path)) {
      throw ArgumentError('Fixed HTTPS C origin required');
    }
    _client.connectionTimeout = const Duration(seconds: 20);
  }
  final Uri origin;
  final HttpClient _client;
  void close() => _client.close(force: true);
  Future<({Map<String, dynamic> value, DateTime expires})> send(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
  }) async {
    final r = await _send(
      token,
      method,
      path,
      body: body,
      query: query,
      bytes: bytes,
      mime: mime,
    );
    return (
      value: Map<String, dynamic>.from(r.value as Map),
      expires: r.expires,
    );
  }

  Future<({Uint8List bytes, Duration lease})> image(
    String token,
    String path,
    String mime,
  ) async {
    final r = await _send(token, 'GET', path, binaryMime: mime);
    return (bytes: r.value as Uint8List, lease: r.lease!);
  }

  Future<({Object? value, DateTime expires, Duration? lease})> _send(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
    String? binaryMime,
  }) async {
    AuthCrypto.decode(token, bytes: 32);
    if (!RegExp(
      r'^/api/v1/(comment-commands|comments|posts|me/(comment-tasks|comments))(/[a-zA-Z0-9_-]+)*$',
    ).hasMatch(path)) {
      throw const FormatException('Invalid comment path');
    }
    final data = bytes ?? (body == null ? null : utf8.encode(jsonEncode(body)));
    if (data != null && data.length > 10 * 1024 * 1024) {
      throw const FormatException('Comment request budget');
    }
    HttpClientRequest? active;
    var expired = false;
    try {
      return await (() async {
        final request = await _client.openUrl(
          method,
          origin.resolve(path).replace(queryParameters: query),
        );
        active = request;
        if (expired) {
          request.abort();
          throw const CommentHttpFailure(null, 'TIMEOUT');
        }
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.persistentConnection = false;
        request.headers.set('Authorization', 'Bearer $token');
        request.headers.set('Accept', binaryMime ?? 'application/json');
        if (data != null) {
          request.headers.set(
            'Content-Type',
            mime ?? 'application/json; charset=utf-8',
          );
          request.contentLength = data.length;
          request.add(data);
        }
        final response = await request.close();
        final success =
            response.statusCode == 200 || response.statusCode == 202;
        final max = success
            ? (binaryMime == null ? 4 * 1024 * 1024 : 10 * 1024 * 1024)
            : 32768;
        if (response.contentLength > max) {
          throw const FormatException('Comment response budget');
        }
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (buffer.length + chunk.length > max) {
            throw const FormatException('Comment response budget');
          }
          buffer.add(chunk);
        }
        String h(String key) {
          final v = response.headers[key];
          if (v == null || v.length != 1 || v.single.isEmpty) {
            throw const FormatException('Comment headers');
          }
          return v.single;
        }

        AuthCrypto.decode(h('x-request-id'), bytes: 16);
        if (h('cache-control') != 'no-store' ||
            response.headers['set-cookie'] != null) {
          throw const FormatException('Comment cache policy');
        }
        final raw = buffer.takeBytes();
        final type = ContentType.parse(h('content-type'));
        Object? value;
        if (success && binaryMime != null) {
          if (type.mimeType != binaryMime ||
              type.parameters.isNotEmpty ||
              h('x-content-type-options') != 'nosniff' ||
              h('content-disposition') != 'attachment') {
            throw const FormatException('Comment image response');
          }
          value = raw;
        } else {
          if (type.mimeType != 'application/json' ||
              type.charset != null && type.charset!.toLowerCase() != 'utf-8') {
            throw const FormatException('Comment response type');
          }
          value = GovernanceStrictJson(utf8.decode(raw, allowMalformed: false))
              .decode();
        }
        if (!success) {
          if (response.headers['session-expires-at'] != null ||
              response.headers['server-time'] != null) {
            throw const FormatException('Renewal on error');
          }
          final m = PostJson.record(value, {'error', 'requestId'});
          if (m['requestId'] != h('x-request-id')) {
            throw const FormatException('Request mismatch');
          }
          final e = PostJson.record(m['error'], {'code', 'message'});
          throw CommentHttpFailure(
            response.statusCode,
            PostJson.text(e, 'code'),
            retryAfterSeconds: response.statusCode == 429
                ? parseRetryAfterSeconds(h('retry-after'))
                : null,
          );
        }
        final at = PostJson.utc(h('server-time')),
            until = PostJson.utc(h('session-expires-at'));
        if (!until.isAfter(at)) throw const FormatException('Comment deadline');
        Duration? lease;
        if (binaryMime != null) {
          final expiry = PostJson.utc(h('access-valid-until'));
          lease = expiry.difference(at);
          if (lease <= Duration.zero ||
              lease > const Duration(seconds: 60) ||
              expiry.isAfter(until)) {
            throw const FormatException('Comment media lease');
          }
        }
        return (value: value, expires: until, lease: lease);
      })().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      expired = true;
      active?.abort();
      throw const CommentHttpFailure(null, 'TIMEOUT');
    } on IOException {
      active?.abort();
      throw const CommentHttpFailure(null, 'TRANSPORT');
    }
  }
}

class HttpCommentApi implements CommentApi {
  HttpCommentApi(this.request, this.upload, {this.identityMissing});
  final Future<bool> Function(CommentBinding)? identityMissing;
  final CommentRequest request;
  final Future<void> Function(CommentIntent intent, int version) upload;
  static Map<String, dynamic> intentBody(CommentIntent i) => {
    'operation': i.operation.name.toUpperCase(),
    'taskId': i.taskId,
    if (i.operation == CommentOperation.create) ...{
      'postId': i.binding.postId,
      'identityId': i.binding.identityId,
      'rootCommentId': i.binding.rootCommentId,
      'targetCommentId': i.binding.targetCommentId,
    },
    if (i.expectedAttemptVersion != null)
      'expectedAttemptVersion': i.expectedAttemptVersion,
    if (i.operation != CommentOperation.abandon) ...{
      'body': i.content!.body,
      'image': i.content!.image?.selection.toJson(),
    },
  };
  @override
  Future<CommentTask> execute(CommentIntent i) async => (await _receipt(
    i,
    await request(
      'PUT',
      '/api/v1/comment-commands/${i.commandId}',
      body: intentBody(i),
    ),
  ))!;
  @override
  Future<CommentTask?> query(CommentIntent i) async => _receipt(
    i,
    await request('GET', '/api/v1/comment-commands/${i.commandId}'),
  );
  Future<CommentTask?> _receipt(CommentIntent i, Map<String, dynamic> r) async {
    final state = r['state'];
    if (state == 'UNKNOWN_NOT_OBSERVED') {
      PostJson.record(r, {'state'});
      return null;
    }
    if (r['operation'] != i.operation.name.toUpperCase()) {
      throw const FormatException('Comment operation mismatch');
    }
    if (state == 'REJECTED' || state == 'NOT_ACCEPTED') {
      PostJson.record(r, {'state', 'operation', 'errorCode'});
      throw CommentCommandRejected(PostJson.text(r, 'errorCode'));
    }
    PostJson.record(r, {'state', 'operation', 'taskId', 'attemptVersion'});
    if (r['taskId'] != i.taskId ||
        state !=
            (i.operation == CommentOperation.abandon
                ? 'APPLIED'
                : 'ACCEPTED')) {
      throw const FormatException('Comment receipt');
    }
    final version = PostJson.integer(r, 'attemptVersion', 1, 2147483647);
    if (i.operation == CommentOperation.create
        ? version != 1
        : version !=
              (i.expectedAttemptVersion! +
                  (i.operation == CommentOperation.retry ? 1 : 0))) {
      throw const FormatException('Comment version');
    }
    // Uploads are idempotent writes to this exact accepted manifest, never
    // create/retry command replay. First query state to avoid late upload loops.
    var t = await queryTask(taskId: i.taskId, binding: i.binding);
    if (t?.state == CommentTaskState.accepted &&
        i.content?.image != null &&
        !i.reconciliationOnly) {
      await upload(i, version);
      t = await queryTask(taskId: i.taskId, binding: i.binding);
    }
    return t;
  }

  @override
  Future<CommentTask?> queryTask({
    required String taskId,
    required CommentBinding binding,
  }) async {
    try {
      final r = await request('GET', '/api/v1/me/comment-tasks/$taskId');
      final t = parseTask(r, binding: binding);
      if (t.taskId != taskId) {
        throw const FormatException('Task resource mismatch');
      }
      return t;
    } on CommentHttpFailure catch (e) {
      if (e.status == 404 &&
          identityMissing != null &&
          await identityMissing!(binding)) {
        throw const CommentIdentityDeleted();
      }
      rethrow;
    }
  }

  static CommentTask parseTask(
    Map<String, dynamic> r, {
    CommentBinding? binding,
  }) {
    PostJson.record(r, {
      'taskId',
      'ownerIdentityId',
      'postId',
      'rootCommentId',
      'targetCommentId',
      'attemptVersion',
      'state',
      'failureCode',
      'materialsAvailable',
      'content',
      'allowedActions',
      'publishedCommentId',
    });
    final b = CommentBinding(
      postId: PostJson.id(r, 'postId'),
      identityId: PostJson.id(r, 'ownerIdentityId'),
      rootCommentId: r['rootCommentId'] as String?,
      targetCommentId: r['targetCommentId'] as String?,
    );
    if (binding != null && !binding.sameAs(b)) {
      throw const FormatException('Comment binding changed');
    }
    final actions = (r['allowedActions'] as List).cast<String>();
    if (actions.toSet().length != actions.length ||
        actions.any((a) => !{'RETRY', 'ABANDON'}.contains(a))) {
      throw const FormatException('Comment actions');
    }
    return CommentTask(
      taskId: PostJson.id(r, 'taskId'),
      binding: b,
      attemptVersion: PostJson.integer(r, 'attemptVersion', 1, 2147483647),
      state: CommentTaskState.values.byName(
        (r['state'] as String).toLowerCase(),
      ),
      contentAvailable: r['materialsAvailable'] as bool,
      canRetry: actions.contains('RETRY'),
      canAbandon: actions.contains('ABANDON'),
      commentId: r['publishedCommentId'] as String?,
      failureCode: r['failureCode'] as String?,
    );
  }

  static String digest(CommentIntent i) =>
      CommentProtocol.digest(switch (i.operation) {
        CommentOperation.create => CommentProtocol.create(
          taskId: i.taskId,
          postId: i.binding.postId,
          identityId: i.binding.identityId,
          rootCommentId: i.binding.rootCommentId,
          targetCommentId: i.binding.targetCommentId,
          body: i.content!.body,
          image: i.content!.image?.selection,
        ),
        CommentOperation.retry => CommentProtocol.retry(
          taskId: i.taskId,
          expectedAttemptVersion: i.expectedAttemptVersion!,
          body: i.content!.body,
          image: i.content!.image?.selection,
        ),
        CommentOperation.abandon => CommentProtocol.abandon(
          taskId: i.taskId,
          expectedAttemptVersion: i.expectedAttemptVersion!,
        ),
      });
}
