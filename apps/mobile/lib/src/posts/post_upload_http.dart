part of 'http_post_api.dart';

class HttpPostUploadApi extends HttpPostApi implements PostUploadApi {
  HttpPostUploadApi({
    required super.communityBaseUri,
    super.client,
    super.timeout,
  });
  @override
  Future<PostResponse<PostCommandResult>> createWithImages({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
    required List<PostImageSelection> images,
  }) => _input(() {
    PostContentRules.validate(title, body, imageCount: images.length);
    final manifest = PostImageSelection.list(
      images.map((e) => e.toJson()).toList(),
    );
    return _command(
      sessionToken,
      'PUT',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}',
      operation: PostOperation.create,
      expected: 202,
      maxRequestBytes: 262144,
      body: {
        'channelId': PostProtocol.resourceId(channelId),
        'identityId': PostProtocol.resourceId(identityId),
        'title': title,
        'body': body,
        if (manifest.isNotEmpty)
          'images': manifest.map((e) => e.toJson()).toList(),
      },
    );
  });
  @override
  Future<PostResponse<PostCommandResult>> retryWithImages({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
    required List<PostImageSelection> images,
  }) => _input(() {
    PostContentRules.validate(title, body, imageCount: images.length);
    final manifest = PostImageSelection.list(
      images.map((e) => e.toJson()).toList(),
    );
    return _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/retry',
      operation: PostOperation.retry,
      commandId: commandId,
      taskId: taskId,
      expectedAttemptVersion: PostProtocol.version(expectedAttemptVersion),
      expected: 202,
      maxRequestBytes: 262144,
      body: {
        'expectedAttemptVersion': expectedAttemptVersion,
        'title': title,
        'body': body,
        if (manifest.isNotEmpty)
          'images': manifest.map((e) => e.toJson()).toList(),
      },
    );
  });
  @override
  Future<PostResponse<PostUploadState>> uploads({
    required String sessionToken,
    required String taskId,
    required int version,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/attempts/${PostProtocol.version(version)}/images',
      decode: (raw) => PostUploadState.fromJson(raw, taskId, version),
    ),
  );
  @override
  Future<PostResponse<PostUploadGrant>> uploadGrant({
    required String sessionToken,
    required String taskId,
    required int version,
    required String mediaId,
  }) => _input(() async {
    final response = await _send(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/attempts/${PostProtocol.version(version)}/images/${PostProtocol.resourceId(mediaId)}/upload-grant',
      decode: (raw) {
        final m = PostJson.record(raw, {
          'taskId',
          'mediaId',
          'attemptVersion',
          'uploadToken',
          'expiresAt',
        });
        if (PostJson.id(m, 'taskId') != taskId ||
            PostJson.id(m, 'mediaId') != mediaId ||
            PostJson.integer(m, 'attemptVersion', 1, 2147483647) != version) {
          throw const FormatException('Mismatched upload grant');
        }
        final token = PostJson.text(m, 'uploadToken');
        AuthCrypto.decode(token, bytes: 32);
        return PostUploadGrant(
          uploadToken: token,
          expiresAt: PostJson.date(m, 'expiresAt'),
        );
      },
    );
    if (!response.value.expiresAt.isAfter(response.serverTime) ||
        response.value.expiresAt.isAfter(
          response.serverTime.add(const Duration(minutes: 15)),
        )) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    return response;
  });
  @override
  Future<DateTime> putOriginal({
    required String uploadToken,
    required String taskId,
    required int version,
    required PostImageSelection image,
    required Uint8List bytes,
  }) => _input(() async {
    AuthCrypto.decode(uploadToken, bytes: 32);
    PostImageSelection.fromJson(image.toJson());
    if (bytes.length != image.byteLength ||
        hashes.sha256.convert(bytes).toString() != image.sha256) {
      throw const FormatException('Original changed');
    }
    final path =
        '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/attempts/${PostProtocol.version(version)}/images/${image.mediaId}/bytes';
    HttpClientRequest? active;
    var expired = false;
    try {
      return await (() async {
        final request = await _client.openUrl(
          'PUT',
          communityBaseUri.resolve(path),
        );
        active = request;
        if (expired) {
          request.abort();
          throw const PostFailure(kind: PostFailureKind.transport);
        }
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.persistentConnection = false;
        request.headers.set('Authorization', 'Upload $uploadToken');
        request.headers.set('Content-Type', image.mimeType);
        request.headers.set('Accept', 'application/json');
        request.contentLength = bytes.length;
        request.add(bytes);
        final response = await request.close();
        if (response.contentLength > 32768) {
          throw const FormatException('Invalid upload response');
        }
        final data = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (data.length + chunk.length > 32768) {
            throw const FormatException('Invalid upload response');
          }
          data.add(chunk);
        }
        final h = response.headers;
        final id = HttpPostApi._single(h, 'x-request-id');
        AuthCrypto.decode(id, bytes: 16);
        if (HttpPostApi._single(h, 'cache-control') != 'no-store' ||
            h['set-cookie'] != null) {
          throw const FormatException('Invalid upload policy');
        }
        if (response.statusCode != 204) {
          final type = ContentType.parse(
            HttpPostApi._single(h, 'content-type'),
          );
          if (type.mimeType != 'application/json' ||
              type.charset != null && type.charset!.toLowerCase() != 'utf-8') {
            throw const FormatException('Invalid upload error');
          }
          throw HttpPostApi._failure(
            response.statusCode,
            _PostStrictJson(
              utf8.decode(data.takeBytes(), allowMalformed: false),
            ).decode(),
            h,
            id,
          );
        }
        if (data.length != 0 ||
            h['session-expires-at'] != null ||
            HttpPostApi._single(h, 'x-content-type-options') != 'nosniff') {
          throw const FormatException('Invalid upload receipt');
        }
        return PostJson.utc(HttpPostApi._single(h, 'server-time'));
      })().timeout(timeout);
    } on PostFailure {
      rethrow;
    } on TimeoutException {
      expired = true;
      active?.abort();
      throw const PostFailure(kind: PostFailureKind.transport, code: 'TIMEOUT');
    } on IOException {
      active?.abort();
      throw const PostFailure(kind: PostFailureKind.transport);
    } on FormatException {
      active?.abort();
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
  });
}
