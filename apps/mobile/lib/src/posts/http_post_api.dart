import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../messaging/dm_protocol.dart';

import '../auth/auth_crypto.dart';
import 'post_api.dart';
import 'feed_api.dart';
import 'post_interactions_api.dart';
import 'post_models.dart';
import 'post_media_api.dart';
import 'post_protocol.dart';
import 'post_upload_api.dart';
import 'post_upload_models.dart';

import 'package:crypto/crypto.dart' as hashes;

part 'post_upload_http.dart';
part 'feed_http.dart';
part 'post_interactions_http.dart';

/// 仅访问构造时固定的 C HTTPS origin，不跟随重定向或自动重送命令。
class HttpPostApi
    implements PostApi, PostMediaApi, FeedApi, PostInteractionsApi, DmApi {
  HttpPostApi({
    required this.communityBaseUri,
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient() {
    if (communityBaseUri.scheme != 'https' ||
        communityBaseUri.host.isEmpty ||
        communityBaseUri.userInfo.isNotEmpty ||
        communityBaseUri.hasQuery ||
        communityBaseUri.hasFragment ||
        communityBaseUri.path.isNotEmpty && communityBaseUri.path != '/' ||
        timeout <= Duration.zero) {
      throw ArgumentError(
        'A fixed C HTTPS origin and positive timeout are required',
      );
    }
    _client.connectionTimeout = timeout;
  }
  final Uri communityBaseUri;
  final Duration timeout;
  final HttpClient _client;
  void close() => _client.close(force: true);

  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) => _input(() {
    if (resource.startsWith('governance/blocks')) {
      if (resource != 'governance/blocks') {
        final parts = resource.split('/');
        if (parts.length != 3 || parts[1] != 'blocks') {
          throw const FormatException('Invalid DM governance route');
        }
        PostProtocol.resourceId(parts[2]);
      }
    } else if (resource.startsWith('chat/')) {
      final parts = resource.split('/');
      if (!{
            'pending',
            'conversations',
            'controls',
            'control-ack',
            'operations',
            'images',
            'media',
          }.contains(parts[1]) ||
          parts.length > 3) {
        throw const FormatException('Invalid DM chat route');
      }
      if (parts.length == 3) PostProtocol.resourceId(parts[2]);
    } else if (!{
      'pending',
      'conversations',
      'ack',
      'read',
      'contact',
    }.contains(resource)) {
      if (!resource.startsWith('commands/')) {
        throw const FormatException('Invalid DM route');
      }
      PostProtocol.resourceId(resource.substring('commands/'.length));
    }
    return _send(
      token,
      method,
      '/api/v1/dm/$resource',
      body: body,
      query: query,
      maxRequestBytes: resource.startsWith('chat/images/')
          ? 15 * 1024 * 1024
          : 100000,
      maxResponseBytes: resource.startsWith('chat/media/')
          ? 15 * 1024 * 1024
          : 8 * 1024 * 1024,
      decode: (raw) => decodeDm(raw, resource),
    );
  });

  @override
  Future<PostResponse<List<PostInteractions>>> interactions({
    required String sessionToken,
    required List<String> postIds,
  }) => _input(() {
    if (postIds.isEmpty ||
        postIds.length > 50 ||
        postIds.toSet().length != postIds.length) {
      throw const FormatException('Invalid interaction batch');
    }
    for (final id in postIds) {
      PostProtocol.resourceId(id);
    }
    return _send(
      sessionToken,
      'POST',
      '/api/v1/feed/interactions',
      body: {'postIds': postIds},
      maxRequestBytes: 4096,
      decode: (raw) {
        final m = PostJson.record(raw, {'items'});
        final items = m['items'];
        if (items is! List || items.length != postIds.length) {
          throw const FormatException('Invalid interaction batch');
        }
        final values = items.map(PostInteractions.fromJson).toList();
        for (var i = 0; i < values.length; i++) {
          if (values[i].postId != postIds[i]) {
            throw const FormatException('Mismatched interaction batch');
          }
        }
        return values;
      },
    );
  });
  @override
  Future<PostResponse<PostInteractions>> postInteractions({
    required String sessionToken,
    required String postId,
  }) => _interactionRequest(sessionToken, postId);
  @override
  Future<PostResponse<PostInteractions>> setPostLike({
    required String sessionToken,
    required String postId,
    required bool liked,
    required String version,
  }) => _interactionRequest(
    sessionToken,
    postId,
    action: 'like',
    desired: liked,
    version: version,
  );
  @override
  Future<PostResponse<PostInteractions>> setPostFavorite({
    required String sessionToken,
    required String postId,
    required bool favorited,
    required String version,
  }) => _interactionRequest(
    sessionToken,
    postId,
    action: 'favorite',
    desired: favorited,
    version: version,
  );

  @override
  Future<PostResponse<PostsPage<FeedPost>>> timeline({
    required String sessionToken,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) => _timeline(
    sessionToken: sessionToken,
    channelId: channelId,
    cursor: cursor,
    limit: limit,
  );
  @override
  Future<PostResponse<FeedPreferences>> feedPreferences({
    required String sessionToken,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/feed-preferences',
      decode: FeedPreferences.fromJson,
    ),
  );
  @override
  Future<PostResponse<FeedPreferences>> saveFeedPreferences({
    required String sessionToken,
    required Set<String> blockedChannelIds,
  }) => _input(() {
    final ids = FeedPreferences(blockedChannelIds).blockedChannelIds.toList()
      ..sort();
    return _send(
      sessionToken,
      'PUT',
      '/api/v1/me/feed-preferences',
      body: {'blockedChannelIds': ids},
      decode: FeedPreferences.fromJson,
    );
  });
  @override
  Future<PostResponse<PostViews>> registerPostView({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'POST',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}/views',
      decode: (raw) {
        final result = PostViews.fromJson(raw);
        if (result.postId != postId) {
          throw const FormatException('Mismatched view');
        }
        return result;
      },
    ),
  );

  @override
  Future<PostResponse<PostMediaManifest>> imageManifest({
    required String sessionToken,
    required String postId,
  }) => _input(() async {
    PostProtocol.resourceId(postId);
    final response = await _send(
      sessionToken,
      'GET',
      '/api/v1/posts/$postId/images',
      decode: (raw) => PostMediaManifest.fromJson(raw, postId),
    );
    final until = response.value.accessValidUntil;
    if (!until.isAfter(response.serverTime) ||
        until.isAfter(response.serverTime.add(const Duration(seconds: 60))) ||
        until.isAfter(response.sessionExpiresAt)) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    return response;
  });

  @override
  Future<PostResponse<Uint8List>> imageBytes({
    required String sessionToken,
    required String postId,
    required PostMediaImage image,
  }) => _input(() {
    image.validatePost(postId);
    return _send(
      sessionToken,
      'GET',
      image.path,
      binaryImage: image,
      maxResponseBytes: image.byteLength,
      decode: (raw) => raw as Uint8List,
    );
  });

  @override
  Future<PostResponse<PostCommandResult>> create({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
  }) => _input(() {
    PostContentRules.validate(title, body);
    return _command(
      sessionToken,
      'PUT',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}',
      operation: PostOperation.create,
      body: {
        'channelId': PostProtocol.resourceId(channelId),
        'identityId': PostProtocol.resourceId(identityId),
        'title': title,
        'body': body,
      },
      expected: 202,
      maxRequestBytes: 262144,
    );
  });
  @override
  Future<PostResponse<PostCommandResult>> commandResult({
    required String sessionToken,
    required String commandId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}',
      decode: PostCommandResult.fromJson,
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> seal({
    required String sessionToken,
    required String commandId,
    required PostOperation operation,
    required String requestDigest,
  }) => _input(
    () => _send(
      sessionToken,
      'POST',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}/seal',
      body: {
        'operation': operation.wire,
        'requestDigest': PostProtocol.digestValue(requestDigest),
      },
      decode: (raw) {
        final r = PostCommandResult.fromJson(raw);
        if (r.state == PostCommandState.unknownNotObserved ||
            r.operation != null && r.operation != operation) {
          throw const FormatException('Invalid seal operation outcome');
        }
        return r;
      },
    ),
  );
  @override
  Future<PostResponse<PostsPage<PostTask>>> tasks({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-tasks',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 24 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostTask.fromJson);
        if (page.items.length > limit ||
            page.items.any(
              (task) =>
                  !task.visible ||
                  task.state != PostTaskState.accepted &&
                      task.state != PostTaskState.failed,
            )) {
          throw const FormatException('Invalid own task page');
        }
        return page;
      },
    ),
  );
  @override
  Future<PostResponse<PostTask>> task({
    required String sessionToken,
    required String taskId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}',
      maxResponseBytes: 512 * 1024,
      decode: (raw) {
        final task = PostTask.fromJson(raw);
        if (task.taskId != taskId) {
          throw const FormatException('Mismatched task resource');
        }
        return task;
      },
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> cancel({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) => _input(
    () => _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/cancel',
      operation: PostOperation.cancel,
      commandId: commandId,
      taskId: taskId,
      body: {
        'expectedAttemptVersion': PostProtocol.version(expectedAttemptVersion),
      },
      expectedAttemptVersion: expectedAttemptVersion,
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> retry({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
  }) => _input(() {
    PostContentRules.validate(title, body);
    return _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/retry',
      operation: PostOperation.retry,
      commandId: commandId,
      taskId: taskId,
      expected: 202,
      body: {
        'expectedAttemptVersion': PostProtocol.version(expectedAttemptVersion),
        'title': title,
        'body': body,
      },
      expectedAttemptVersion: expectedAttemptVersion,
      maxRequestBytes: 262144,
    );
  });
  @override
  Future<PostResponse<PostCommandResult>> hide({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) => _input(
    () => _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/hide',
      operation: PostOperation.hideTask,
      commandId: commandId,
      taskId: taskId,
      body: {
        'expectedAttemptVersion': PostProtocol.version(expectedAttemptVersion),
      },
      expectedAttemptVersion: expectedAttemptVersion,
    ),
  );
  @override
  Future<PostResponse<PostsPage<PostCard>>> feed({
    required String sessionToken,
    required String channelId,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/channels/${PostProtocol.resourceId(channelId)}/posts',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 2 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostCard.fromJson);
        if (page.items.length > limit ||
            page.items.any((p) => p.channelId != channelId)) {
          throw const FormatException('Invalid channel feed page');
        }
        return page;
      },
    ),
  );
  @override
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}',
      maxResponseBytes: 512 * 1024,
      decode: (raw) {
        final post = PostDetail.fromJson(
          PostJson.record(raw, {'post'})['post'],
        );
        if (post.postId != postId) {
          throw const FormatException('Mismatched post resource');
        }
        return post;
      },
    ),
  );
  @override
  Future<PostResponse<PostsPage<OwnPostCard>>> ownPosts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/posts',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 2 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, OwnPostCard.fromJson);
        if (page.items.length > limit) {
          throw const FormatException('Invalid own post page size');
        }
        return page;
      },
    ),
  );
  @override
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/posts/${PostProtocol.resourceId(postId)}/capabilities',
      decode: (raw) {
        final caps = PostCapabilities.fromJson(raw);
        if (caps.postId != postId) {
          throw const FormatException('Mismatched capabilities resource');
        }
        return caps;
      },
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> delete({
    required String sessionToken,
    required String commandId,
    required String postId,
  }) => _input(
    () => _command(
      sessionToken,
      'POST',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}/delete',
      operation: PostOperation.deletePost,
      commandId: commandId,
      postId: postId,
    ),
  );
  @override
  Future<PostResponse<ComposerContext>> composerContext({
    required String sessionToken,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-composer-context',
      decode: ComposerContext.fromJson,
    ),
  );

  Future<PostResponse<PostCommandResult>> _command(
    String token,
    String method,
    String path, {
    required PostOperation operation,
    String? commandId,
    String? taskId,
    String? postId,
    int? expectedAttemptVersion,
    int expected = 200,
    Map<String, Object>? body,
    int maxRequestBytes = 1024,
  }) => _send(
    token,
    method,
    path,
    expected: expected,
    body: body,
    headers: commandId == null
        ? const {}
        : {'Idempotency-Key': PostProtocol.commandId(commandId)},
    maxRequestBytes: maxRequestBytes,
    decode: (raw) {
      final result = PostCommandResult.fromJson(raw);
      if (result.operation != operation ||
          result.state !=
              (expected == 202
                  ? PostCommandState.accepted
                  : PostCommandState.committed) ||
          taskId != null && result.taskId != taskId ||
          postId != null && result.postId != postId ||
          operation == PostOperation.create && result.attemptVersion != 1 ||
          operation == PostOperation.retry &&
              result.attemptVersion != expectedAttemptVersion! + 1 ||
          (operation == PostOperation.cancel ||
                  operation == PostOperation.hideTask) &&
              result.attemptVersion != expectedAttemptVersion) {
        throw const FormatException('Mismatched command receipt');
      }
      return result;
    },
  );

  static Map<String, String> _pageQuery(String? cursor, int limit) {
    if (limit < 1 || limit > 50) {
      throw const FormatException('Invalid page limit');
    }
    PostProtocol.cursor(cursor);
    return {'limit': '$limit', if (cursor != null) 'cursor': cursor};
  }

  Future<T> _input<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on FormatException {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }

  Future<PostResponse<T>> _send<T>(
    String token,
    String method,
    String path, {
    required T Function(Object?) decode,
    Map<String, Object>? body,
    Map<String, String> headers = const {},
    Map<String, String>? query,
    int expected = 200,
    int maxRequestBytes = 1024,
    int maxResponseBytes = 32768,
    PostMediaImage? binaryImage,
    bool readInteractionVersion = false,
  }) async {
    AuthCrypto.decode(token, bytes: 32);
    final bytes = body == null ? null : utf8.encode(jsonEncode(body));
    if (bytes != null && bytes.length > maxRequestBytes) {
      throw const FormatException('Post request too large');
    }
    HttpClientRequest? active;
    int? status;
    var expired = false;
    try {
      return await (() async {
        final uri = communityBaseUri
            .resolve(path)
            .replace(queryParameters: query);
        final request = await _client.openUrl(method, uri);
        active = request;
        if (expired) {
          request.abort();
          throw const PostFailure(
            kind: PostFailureKind.transport,
            code: 'TIMEOUT',
          );
        }
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.persistentConnection = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
        if (bytes != null) {
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json; charset=utf-8',
          );
          request.contentLength = bytes.length;
          request.add(bytes);
        }
        final response = await request.close();
        status = response.statusCode;
        final limit = status == expected ? maxResponseBytes : 32768;
        if (response.contentLength > limit) {
          throw const FormatException('Oversized post response');
        }
        final data = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (data.length + chunk.length > limit) {
            throw const FormatException('Oversized post response');
          }
          data.add(chunk);
        }
        final h = response.headers;
        final requestId = _single(h, 'x-request-id');
        AuthCrypto.decode(requestId, bytes: 16);
        if (_single(h, 'cache-control') != 'no-store' ||
            h[HttpHeaders.setCookieHeader] != null) {
          throw const FormatException('Invalid post cache or cookie policy');
        }
        final type = ContentType.parse(
          _single(h, HttpHeaders.contentTypeHeader),
        );
        final responseBytes = data.takeBytes();
        final Object? payload;
        if (status == expected && binaryImage != null) {
          if (type.mimeType != binaryImage.mimeType ||
              type.parameters.isNotEmpty ||
              responseBytes.length != binaryImage.byteLength ||
              _single(h, 'x-content-type-options') != 'nosniff' ||
              _single(h, 'content-disposition') != 'attachment') {
            throw const FormatException('Invalid protected image bytes');
          }
          payload = responseBytes;
        } else {
          if (type.mimeType != 'application/json' ||
              type.charset != null && type.charset!.toLowerCase() != 'utf-8') {
            throw const FormatException('Invalid post response type');
          }
          payload = _PostStrictJson(
            utf8.decode(responseBytes, allowMalformed: false),
          ).decode();
        }
        if (status != expected) throw _failure(status!, payload, h, requestId);
        final serverTime = PostJson.utc(_single(h, 'server-time'));
        final sessionExpiry = PostJson.utc(_single(h, 'session-expires-at'));
        if (!sessionExpiry.isAfter(serverTime)) {
          throw const FormatException('Invalid post session deadline');
        }
        final interactionVersion = readInteractionVersion
            ? _single(h, 'interaction-version')
            : null;
        if (interactionVersion != null &&
            !_validInteractionVersion(interactionVersion)) {
          throw const FormatException('Invalid interaction version');
        }
        return PostResponse<T>(
          value: decode(payload),
          serverTime: serverTime,
          sessionExpiresAt: sessionExpiry,
          requestId: requestId,
          statusCode: status!,
          interactionVersion: interactionVersion,
        );
      })().timeout(timeout);
    } on PostFailure {
      rethrow;
    } on TimeoutException {
      expired = true;
      active?.abort();
      throw const PostFailure(kind: PostFailureKind.transport, code: 'TIMEOUT');
    } on FormatException {
      active?.abort();
      throw PostFailure(
        kind: status == 401
            ? PostFailureKind.unauthorized
            : status == 503
            ? PostFailureKind.unavailable
            : PostFailureKind.invalidResponse,
        statusCode: status,
      );
    } on IOException {
      active?.abort();
      // 接口不复制异常文本；命令是否受理只能在原账号、原 command 下核对。
      throw const PostFailure(kind: PostFailureKind.transport);
    }
  }

  static String _single(HttpHeaders headers, String key) {
    final values = headers[key];
    if (values == null || values.length != 1 || values.single.isEmpty) {
      throw const FormatException('Missing or ambiguous post response header');
    }
    return values.single;
  }

  static PostFailure _failure(
    int status,
    Object? raw,
    HttpHeaders headers,
    String requestId,
  ) {
    // HTTP 错误不得提供成功续期元数据，尤其不能续期已持久拒绝的命令。
    if (headers['session-expires-at'] != null ||
        headers['server-time'] != null) {
      throw const FormatException('Unexpected renewal on post failure');
    }
    final m = PostJson.record(raw, {'error', 'requestId'});
    if (m['requestId'] != requestId) {
      throw const FormatException('Mismatched post request ID');
    }
    final e = PostJson.record(m['error'], {'code', 'message'});
    final code = PostJson.text(e, 'code');
    PostJson.text(e, 'message', maxLength: 256);
    final allowed = switch (status) {
      400 => {'MALFORMED_REQUEST', 'CURSOR_INVALID', 'POST_CONTENT_INVALID'},
      401 => {'AUTHENTICATION_FAILED', 'SESSION_INVALID', 'session_replaced'},
      403 => {
        'AUTHENTICATION_FAILED',
        'AUTHORIZATION_UNAVAILABLE',
        'POSTING_RESTRICTED',
        'ACCOUNT_CLOSING',
        'MEDIA_UPLOAD_DENIED',
      },
      404 => {
        'TASK_NOT_FOUND',
        'POST_NOT_FOUND',
        'POST_CHANNEL_UNAVAILABLE',
        'MEDIA_NOT_FOUND',
      },
      409 => {
        'COMMAND_CONFLICT',
        'COMMAND_SEALED',
        'RESULT_EXPIRED',
        ...PostJson.businessRejections,
        'MEDIA_UPLOAD_CLOSED',
      },
      413 => {'PAYLOAD_TOO_LARGE'},
      412 => {'INTERACTION_VERSION_CONFLICT'},
      415 => {'UNSUPPORTED_MEDIA_TYPE'},
      429 => {'RATE_LIMITED'},
      422 => {'MEDIA_INVALID'},
      503 => {
        'SERVICE_UNAVAILABLE',
        'AUTHORIZATION_UNAVAILABLE',
        'MEDIA_VALIDATOR_UNAVAILABLE',
      },
      _ => const <String>{},
    };
    if (!allowed.contains(code)) {
      throw const FormatException('Invalid post error status or code');
    }
    int? retry;
    if (status == 429) {
      final value = _single(headers, 'retry-after');
      if (!RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(value)) {
        throw const FormatException('Invalid post retry delay');
      }
      retry = int.parse(value);
      if (retry > 300) throw const FormatException('Invalid post retry delay');
    } else if (headers['retry-after'] != null) {
      throw const FormatException('Unexpected post retry delay');
    }
    return PostFailure(
      kind: status == 401
          ? PostFailureKind.unauthorized
          : status == 503
          ? PostFailureKind.unavailable
          : PostFailureKind.rejected,
      code: code,
      statusCode: status,
      requestId: requestId,
      retryAfterSeconds: retry,
    );
  }
}

/// JSON 原生 decoder 会覆盖重复键；这里先做有界严格解析再校验 DTO。
class _PostStrictJson {
  _PostStrictJson(this.input);
  final String input;
  int at = 0;
  Object? decode() {
    final value = _value(0);
    _space();
    if (at != input.length) throw const FormatException('Trailing JSON data');
    return value;
  }

  void _space() {
    while (at < input.length && ' \t\r\n'.contains(input[at])) {
      at++;
    }
  }

  Object? _value(int depth) {
    if (depth > 16) throw const FormatException('JSON nesting too deep');
    _space();
    if (at >= input.length) throw const FormatException('Missing JSON value');
    final c = input[at];
    if (c == '{') {
      at++;
      _space();
      final result = <String, Object?>{};
      if (_consume('}')) return result;
      while (true) {
        _space();
        final key = _string();
        _space();
        if (!_consume(':') || result.containsKey(key)) {
          throw const FormatException('Invalid JSON key');
        }
        result[key] = _value(depth + 1);
        _space();
        if (_consume('}')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON object');
      }
    }
    if (c == '[') {
      at++;
      _space();
      final result = <Object?>[];
      if (_consume(']')) return result;
      while (true) {
        if (result.length >= 50) {
          throw const FormatException('JSON list too large');
        }
        result.add(_value(depth + 1));
        _space();
        if (_consume(']')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON array');
      }
    }
    if (c == '"') return _string();
    if (input.startsWith('true', at)) {
      at += 4;
      return true;
    }
    if (input.startsWith('false', at)) {
      at += 5;
      return false;
    }
    if (input.startsWith('null', at)) {
      at += 4;
      return null;
    }
    final match = RegExp(r'-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?')
        .matchAsPrefix(input, at);
    if (match == null) throw const FormatException('Invalid JSON value');
    at = match.end;
    final number = num.tryParse(match.group(0)!);
    if (number == null || !number.isFinite) {
      throw const FormatException('Invalid JSON number');
    }
    return number;
  }

  String _string() {
    if (at >= input.length || input[at] != '"') {
      throw const FormatException('Missing JSON string');
    }
    final start = at++;
    while (at < input.length) {
      final c = input[at++];
      if (c == '"') {
        final value = jsonDecode(input.substring(start, at)) as String;
        PostContentRules.scalarText(value);
        return value;
      }
      if (c == '\\') {
        if (at >= input.length) {
          throw const FormatException('Incomplete JSON escape');
        }
        at++;
      }
    }
    throw const FormatException('Incomplete JSON string');
  }

  bool _consume(String c) {
    if (at < input.length && input[at] == c) {
      at++;
      return true;
    }
    return false;
  }
}
