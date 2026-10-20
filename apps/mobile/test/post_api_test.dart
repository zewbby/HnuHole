import 'dart:convert';
import 'dart:io';

import 'loopback_tls_fixture.dart';

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;

import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_models.dart';
import 'package:hnuhole_mobile/src/posts/post_media_api.dart';
import 'package:hnuhole_mobile/src/posts/post_controller.dart';
import 'package:hnuhole_mobile/src/posts/post_media_repository.dart';
import 'package:hnuhole_mobile/src/posts/post_upload_models.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';

import 'identity_test_support.dart';

import 'package:hnuhole_mobile/src/posts/post_protocol.dart';

import 'post_media_test_support.dart';

import 'package:hnuhole_mobile/src/posts/feed_api.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _time = '2026-10-08T00:00:00Z';
const _expiry = '2026-10-08T01:00:00Z';
final _token = AuthCrypto.encode(List.filled(32, 7));
final _key = AuthCrypto.encode(List.filled(16, 8));
final _requestId = AuthCrypto.encode(List.filled(16, 10));

class _Captured {
  _Captured(this.method, this.uri, this.headers, this.body, this.bytes);
  final String method, body;
  final List<int> bytes;
  final Uri uri;
  final Map<String, List<String>> headers;
}

class _Endpoint {
  _Endpoint(this.server);
  final HttpServer server;
  final requests = <_Captured>[];
  late Future<void> Function(HttpRequest) respond;
  Uri get uri => Uri.parse('https://127.0.0.1:${server.port}');
  static Future<_Endpoint> start() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_certificate))
      ..usePrivateKeyBytes(utf8.encode(_privateKey));
    final endpoint = _Endpoint(
      await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context),
    );
    endpoint.server.listen((request) async {
      try {
        final headers = <String, List<String>>{};
        request.headers.forEach(
          (key, values) => headers[key] = List.from(values),
        );
        final raw = await request.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (b, chunk) => b..add(chunk),
        );
        final bytes = raw.takeBytes();
        final body = utf8.decode(bytes, allowMalformed: true);
        endpoint.requests.add(
          _Captured(request.method, request.uri, headers, body, bytes),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('X-Request-ID', _requestId);
        await endpoint.respond(request);
      } on Object {
        // 超时测试会主动终止客户端；该测试服务不记录正文与网络异常。
      }
    });
    return endpoint;
  }

  HttpClient client() =>
      HttpClient(
          context: SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificatesBytes(utf8.encode(_certificate)),
        )
        ..badCertificateCallback = (certificate, host, port) =>
            host == '127.0.0.1' &&
            port == server.port &&
            certificate.pem.trim() == _certificate.trim();
  Future<void> close() => server.close(force: true);
}

class _FailingClient implements HttpClient {
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('private Bearer, body, and URL'));
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _json(
  HttpRequest request,
  int status,
  Object payload, {
  bool success = true,
}) async {
  request.response.statusCode = status;
  if (success) {
    request.response.headers.set('Session-Expires-At', _expiry);
    request.response.headers.set('Server-Time', _time);
  }
  request.response.write(jsonEncode(payload));
  await request.response.close();
}

Map<String, Object> _accepted([String operation = 'CREATE', int version = 1]) =>
    {
      'state': 'ACCEPTED',
      'operation': operation,
      'taskId': _id,
      'postId': _id,
      'attemptVersion': version,
    };
Map<String, Object> _error(String code) => {
  'error': {'code': code, 'message': '请求未能完成。'},
  'requestId': _requestId,
};
Map<String, Object> _card() => {
  'postId': _id,
  'channelId': _id,
  'title': ' 标题 ',
  'author': {'state': 'ACTIVE', 'nickname': '甲', 'avatar': 'default-v1'},
  'publishedAt': _time,
};
Map<String, Object?> _task({String? body}) => {
  'task': {
    'taskId': _id,
    'postId': _id,
    'channelId': _id,
    'identityId': _other,
    'attemptVersion': 1,
    'state': 'ACCEPTED',
    'acceptedAt': _time,
    'serverSortAt': _time,
    'terminalAt': null,
    'failureCode': null,
    'visible': true,
    'contentAvailable': true,
    'canRetry': false,
    'canCancel': true,
    'canHide': false,
  },
  'content': {'title': ' 标题 ', 'body': body ?? ' 原始\r\n正文 '},
};
Matcher _failure(PostFailureKind kind, {int? status, String? code}) =>
    isA<PostFailure>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.statusCode, 'status', status)
        .having((e) => e.code, 'code', code);

void main() {
  late LoopbackTlsFixture tls;
  setUpAll(() async {
    tls = await LoopbackTlsFixture.create();
    _certificate = tls.certificate;
    _privateKey = tls.privateKey;
  });
  tearDownAll(() => tls.dispose());

  TestWidgetsFlutterBinding.ensureInitialized();
  // This isolate intentionally contacts only its own loopback TLS fixture.
  // Undo the test binding's blanket HTTP substitute, never production TLS rules.
  HttpOverrides.global = null;
  late _Endpoint endpoint;
  late HttpPostApi api;
  Map<String, Object> interaction({String id = _id, bool liked = true}) => {
    'postId': id,
    'likeCount': 12,
    'favoriteCount': 3,
    'commentCount': 8,
    'likedByMe': liked,
    'favoritedByMe': false,
  };
  final version = '"${List.filled(64, 'a').join()}"';
  List<String> interactionIds(int count) => [
    for (var i = 1; i <= count; i++)
      '10000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
  ];
  for (final count in [26, 50]) {
    test('interaction batch accepts $count unique IDs over real TLS', () async {
      final ids = interactionIds(count);
      endpoint.respond = (r) => _json(r, 200, {
        'items': [for (final id in ids) interaction(id: id)],
      });
      final response = await api.interactions(
        sessionToken: _token,
        postIds: ids,
      );
      expect(response.value.map((item) => item.postId).toList(), ids);
      expect(endpoint.requests, hasLength(1));
      final request = endpoint.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/feed/interactions');
      expect(request.bytes.length, inInclusiveRange(1025, 4096));
      expect(jsonDecode(request.body), {'postIds': ids});
    });
  }
  test('interaction batch and conditional writes use exact private routes and headers', () async {
    endpoint.respond = (r) {
      r.response.headers.set('Interaction-Version', version);
      return _json(
        r,
        200,
        r.uri.path == '/api/v1/feed/interactions'
            ? {
                'items': [interaction()],
              }
            : interaction(),
      );
    };
    final batch = await api.interactions(sessionToken: _token, postIds: [_id]);
    expect(batch.value.single.commentCount, 8);
    expect(endpoint.requests.last.method, 'POST');
    expect(jsonDecode(endpoint.requests.last.body), {
      'postIds': [_id],
    });
    expect(endpoint.requests.last.headers['idempotency-key'], isNull);
    final read = await api.postInteractions(sessionToken: _token, postId: _id);
    expect(read.interactionVersion, version);
    await api.setPostLike(
      sessionToken: _token,
      postId: _id,
      liked: true,
      version: version,
    );
    final sent = endpoint.requests.last;
    expect(sent.method, 'PUT');
    expect(sent.uri.path, '/api/v1/posts/$_id/like');
    expect(sent.uri.hasQuery, false);
    expect(sent.headers['if-interaction-version'], [version]);
    expect(jsonDecode(sent.body), {'liked': true});
    await api.setPostFavorite(
      sessionToken: _token,
      postId: _id,
      favorited: false,
      version: version,
    );
    expect(endpoint.requests.last.uri.path, '/api/v1/posts/$_id/favorite');
    expect(jsonDecode(endpoint.requests.last.body), {'favorited': false});
  });
  test('interaction transport rejects malformed, missing and ambiguous write fence', () async {
    for (final tag in <String?>[null, 'weak', 'W/$version', '"AA"']) {
      endpoint.respond = (r) {
        if (tag != null) r.response.headers.set('Interaction-Version', tag);
        return _json(r, 200, interaction());
      };
      await expectLater(
        api.postInteractions(sessionToken: _token, postId: _id),
        throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
      );
    }
    endpoint.respond = (r) {
      r.response.headers.add('Interaction-Version', version);
      r.response.headers.add('Interaction-Version', version);
      return _json(r, 200, interaction());
    };
    await expectLater(
      api.postInteractions(sessionToken: _token, postId: _id),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
    );
  });
  test('interaction protocol rejects invalid batches before sending and mismatched responses', () async {
    for (final ids in <List<String>>[
      [],
      [_id, _id],
      interactionIds(51),
    ]) {
      await expectLater(
        api.interactions(sessionToken: _token, postIds: ids),
        throwsA(
          _failure(PostFailureKind.rejected, code: 'CLIENT_INPUT_INVALID'),
        ),
      );
    }
    await expectLater(
      api.setPostLike(
        sessionToken: _token,
        postId: _id,
        liked: true,
        version: '*',
      ),
      throwsA(_failure(PostFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    expect(endpoint.requests, isEmpty);
    endpoint.respond = (r) => _json(r, 200, {
      'items': [interaction(id: _other)],
    });
    await expectLater(
      api.interactions(sessionToken: _token, postIds: [_id]),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
    );
    endpoint.respond = (r) {
      r.response.headers.set('Interaction-Version', version);
      return _json(r, 200, interaction(liked: false));
    };
    await expectLater(
      api.setPostLike(
        sessionToken: _token,
        postId: _id,
        liked: true,
        version: version,
      ),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
    );
  });
  test(
    'interaction version conflict is an explicit rejection without renewal',
    () async {
      endpoint.respond = (r) =>
          _json(r, 412, _error('INTERACTION_VERSION_CONFLICT'), success: false);
      await expectLater(
        api.setPostLike(
          sessionToken: _token,
          postId: _id,
          liked: true,
          version: version,
        ),
        throwsA(
          _failure(
            PostFailureKind.rejected,
            status: 412,
            code: 'INTERACTION_VERSION_CONFLICT',
          ),
        ),
      );
    },
  );
  test(
    'feed uses new routes, opaque cursor and strict public projection',
    () async {
      endpoint.respond = (r) => _json(r, 200, {
        'items': [
          {..._card(), 'body': '真实正文', 'viewCount': 1234, 'imageCount': 2},
        ],
        'nextCursor': 'opaque_cursor',
      });
      final page = await api.timeline(sessionToken: _token, limit: 7);
      expect(page.value.items.single.body, '真实正文');
      expect(page.value.items.single.viewCount, 1234);
      expect(endpoint.requests.last.uri.path, '/api/v1/feed');
      expect(endpoint.requests.last.uri.queryParameters, {'limit': '7'});
      await api.timeline(
        sessionToken: _token,
        channelId: _id,
        cursor: page.value.nextCursor,
        limit: 7,
      );
      expect(endpoint.requests.last.uri.queryParameters, {
        'limit': '7',
        'channelId': _id,
        'cursor': 'opaque_cursor',
      });
      expect(endpoint.requests.last.headers['authorization'], [
        'Bearer $_token',
      ]);
      endpoint.respond = (r) => _json(r, 200, {
        'items': [
          {..._card(), 'body': '', 'imageCount': 1, 'viewCount': 0},
        ],
        'nextCursor': null,
      });
      expect(
        (await api.timeline(sessionToken: _token)).value.items.single.body,
        '',
      );
      endpoint.respond = (r) => _json(r, 200, {
        'items': [
          {..._card(), 'body': '正文', 'viewCount': 1, 'accountId': _id},
        ],
        'nextCursor': null,
      });
      await expectLater(
        api.timeline(sessionToken: _token),
        throwsA(isA<PostFailure>()),
      );
    },
  );
  test('preferences replace complete UUID set and views POST has no body or command key', () async {
    endpoint.respond = (r) => _json(r, 200, {
      'blockedChannelIds': [_id],
    });
    expect(
      (await api.feedPreferences(sessionToken: _token)).value.blockedChannelIds,
      {_id},
    );
    await api.saveFeedPreferences(
      sessionToken: _token,
      blockedChannelIds: {_id},
    );
    expect(endpoint.requests.last.method, 'PUT');
    expect(jsonDecode(endpoint.requests.last.body), {
      'blockedChannelIds': [_id],
    });
    endpoint.respond = (r) => _json(r, 200, {'blockedChannelIds': []});
    await api.saveFeedPreferences(sessionToken: _token, blockedChannelIds: {});
    expect(jsonDecode(endpoint.requests.last.body), {'blockedChannelIds': []});
    endpoint.respond = (r) => _json(r, 200, {'postId': _id, 'viewCount': 19});
    expect(
      (await api.registerPostView(
        sessionToken: _token,
        postId: _id,
      )).value.viewCount,
      19,
    );
    final request = endpoint.requests.last;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/posts/$_id/views');
    expect(request.uri.hasQuery, false);
    expect(request.body, '');
    expect(request.headers['idempotency-key'], isNull);
    endpoint.respond = (r) =>
        _json(r, 200, {'postId': _other, 'viewCount': 19});
    await expectLater(
      api.registerPostView(sessionToken: _token, postId: _id),
      throwsA(isA<PostFailure>()),
    );
  });
  test('feed preserves CURSOR_INVALID, 401 and 503 classifications', () async {
    for (final entry in [
      (400, 'CURSOR_INVALID', PostFailureKind.rejected),
      (401, 'session_replaced', PostFailureKind.unauthorized),
      (503, 'SERVICE_UNAVAILABLE', PostFailureKind.unavailable),
    ]) {
      endpoint.respond = (r) =>
          _json(r, entry.$1, _error(entry.$2), success: false);
      await expectLater(
        api.timeline(sessionToken: _token),
        throwsA(_failure(entry.$3, status: entry.$1, code: entry.$2)),
      );
    }
  });
  test('feed DTO rejects negative totals and duplicate preferences', () {
    expect(
      () => FeedPost.fromJson({..._card(), 'body': '正文', 'viewCount': -1}),
      throwsFormatException,
    );
    expect(
      () => FeedPreferences.fromJson({
        'blockedChannelIds': [_id, _id],
      }),
      throwsFormatException,
    );
  });

  test('media CREATE and RETRY preserve manifest and bind the existing intent routes', () async {
    final uploader = HttpPostUploadApi(
      communityBaseUri: endpoint.uri,
      client: endpoint.client(),
    );
    addTearDown(uploader.close);
    final selection = PostImageSelection.fromJson({
      'mediaId': _other,
      'sha256': 'a' * 64,
      'byteLength': 42,
      'mimeType': 'image/gif',
      'width': 1,
      'height': 1,
    });
    endpoint.respond = (r) => _json(
      r,
      202,
      r.uri.path.endsWith('/retry')
          ? {..._accepted('RETRY', 2), 'taskId': _id}
          : _accepted(),
    );
    await uploader.createWithImages(
      sessionToken: _token,
      commandId: _key,
      channelId: _id,
      identityId: _other,
      title: '纯图帖子',
      body: '',
      images: [selection],
    );
    expect(jsonDecode(endpoint.requests.last.body), {
      'channelId': _id,
      'identityId': _other,
      'title': '纯图帖子',
      'body': '',
      'images': [selection.toJson()],
    });
    await uploader.retryWithImages(
      sessionToken: _token,
      commandId: _key,
      taskId: _id,
      expectedAttemptVersion: 1,
      title: '重试',
      body: '',
      images: [selection],
    );
    expect(endpoint.requests.last.uri.path, '/api/v1/me/post-tasks/$_id/retry');
    expect(endpoint.requests.last.headers['idempotency-key'], [_key]);
  });

  test(
    'per-item status/grant and raw PUT isolate Upload capability from Bearer',
    () async {
      final uploader = HttpPostUploadApi(
        communityBaseUri: endpoint.uri,
        client: endpoint.client(),
      );
      addTearDown(uploader.close);
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final image = PostImageSelection.fromJson({
        'mediaId': _other,
        'sha256': hashes.sha256.convert(bytes).toString(),
        'byteLength': bytes.length,
        'mimeType': 'image/png',
        'width': 1,
        'height': 1,
      });
      final uploadToken = AuthCrypto.encode(List.filled(32, 31));
      endpoint.respond = (r) async {
        if (r.method == 'PUT') {
          r.response.statusCode = 204;
          r.response.headers.set('Server-Time', _time);
          r.response.headers.set('X-Content-Type-Options', 'nosniff');
          await r.response.close();
          return;
        }
        await _json(
          r,
          200,
          r.method == 'GET'
              ? {
                  'taskId': _id,
                  'postId': _id,
                  'attemptVersion': 1,
                  'items': [
                    {...image.toJson(), 'position': 0, 'uploaded': false},
                  ],
                }
              : {
                  'taskId': _id,
                  'mediaId': _other,
                  'attemptVersion': 1,
                  'uploadToken': uploadToken,
                  'expiresAt': '2026-10-08T00:10:00Z',
                },
        );
      };
      expect(
        (await uploader.uploads(
          sessionToken: _token,
          taskId: _id,
          version: 1,
        )).value.uploaded,
        [false],
      );
      final grant = await uploader.uploadGrant(
        sessionToken: _token,
        taskId: _id,
        version: 1,
        mediaId: _other,
      );
      expect(grant.value.toString(), isNot(contains(uploadToken)));
      expect(endpoint.requests.last.headers['idempotency-key'], isNull);
      expect(endpoint.requests.last.body, isEmpty);
      await uploader.putOriginal(
        uploadToken: grant.value.uploadToken,
        taskId: _id,
        version: 1,
        image: image,
        bytes: bytes,
      );
      expect(endpoint.requests.last.bytes, bytes);
      expect(endpoint.requests.last.headers['authorization'], [
        'Upload $uploadToken',
      ]);
      expect(endpoint.requests.last.headers['content-type'], ['image/png']);
      expect(endpoint.requests.last.headers['idempotency-key'], isNull);
      final count = endpoint.requests.length;
      await expectLater(
        uploader.putOriginal(
          uploadToken: uploadToken,
          taskId: _id,
          version: 1,
          image: image,
          bytes: Uint8List.fromList(List.filled(bytes.length, 0)),
        ),
        throwsA(isA<PostFailure>()),
      );
      expect(endpoint.requests.length, count);
      for (final code in ['MEDIA_INVALID', 'MEDIA_VALIDATOR_UNAVAILABLE']) {
        endpoint.respond = (r) => _json(
          r,
          code == 'MEDIA_INVALID' ? 422 : 503,
          _error(code),
          success: false,
        );
        await expectLater(
          uploader.putOriginal(
            uploadToken: uploadToken,
            taskId: _id,
            version: 1,
            image: image,
            bytes: bytes,
          ),
          throwsA(isA<PostFailure>().having((e) => e.code, 'code', code)),
        );
      }
    },
  );
  test('real host TLS adapter composes detail, renewable authority and original image group', () async {
    final auth = await IdentityTestFixture.create();
    final posts = PostController(
      api: api,
      mediaApi: api,
      sessions: auth.sessions,
      authStore: auth.store,
      identities: auth.api,
      pollInterval: Duration.zero,
      openStore: (_) async => throw const PostStorageFailure(),
    );
    final media = PostMediaRepository(posts);
    try {
      final bytes = await File(
        '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
      ).readAsBytes();
      endpoint.respond = (request) async {
        if (request.uri.path == '/api/v1/posts/$_id') {
          return _json(request, 200, {
            'post': {..._card(), 'body': '', 'imageCount': 1},
          });
        }
        if (request.uri.path == '/api/v1/posts/$_id/images') {
          return _json(
            request,
            200,
            mediaManifest(bytes: bytes.length, width: 640, height: 480),
          );
        }
        final h = request.response.headers;
        h.set('Content-Type', 'image/png');
        h.set('Content-Disposition', 'attachment');
        h.set('X-Content-Type-Options', 'nosniff');
        h.set('Server-Time', _time);
        h.set('Session-Expires-At', _expiry);
        request.response.add(bytes);
        await request.response.close();
      };
      expect((await posts.loadDetail(_id))!.imageCount, 1);
      final group = await media.load(_id);
      final source = await group.images.single.item.loadSource();
      expect((source.provider as MemoryImage).bytes, bytes);
      expect(source.pixelSize, const Size(640, 480));
      expect(await group.images.single.loadThumbnail!(), same(source.provider));
      await group.images.single.item.resolveOriginal!();
      expect(endpoint.requests.length, 4);
      expect(
        endpoint.requests.every(
          (r) =>
              r.headers['authorization']!.single == 'Bearer $identityTestToken',
        ),
        isTrue,
      );
      group.onRelease!();
      await expectLater(
        group.images.single.item.loadSource(),
        throwsA(isA<PostFailure>()),
      );
    } finally {
      media.dispose();
      posts.dispose();
      auth.dispose();
    }
  });
  test('protected media manifest and bytes use fixed C route and no credential provider', () async {
    endpoint.respond = (request) => _json(request, 200, mediaManifest());
    final group = (await api.imageManifest(
      sessionToken: _token,
      postId: _id,
    )).value;
    expect(group.images.single.contentVersionId, startsWith('44444444'));
    final bytes = [137, 80, 78, 71, 13, 10, 26, 10];
    endpoint.respond = (request) async {
      request.response.headers.set('Content-Type', 'image/png');
      request.response.headers.set('Content-Disposition', 'attachment');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      request.response.headers.set('Session-Expires-At', _expiry);
      request.response.headers.set('Server-Time', _time);
      request.response.add(bytes);
      await request.response.close();
    };
    final result = await api.imageBytes(
      sessionToken: _token,
      postId: _id,
      image: group.images.single,
    );
    expect(result.value, bytes);
    expect(endpoint.requests.last.uri.path, group.images.single.path);
    expect(endpoint.requests.last.body, isEmpty);
    expect(endpoint.requests.last.headers['authorization'], ['Bearer $_token']);
    await expectLater(
      api.imageBytes(
        sessionToken: _token,
        postId: _other,
        image: group.images.single,
      ),
      throwsA(isA<PostFailure>()),
    );
    expect(endpoint.requests.length, 2);
  });

  test('media manifest rejects wrong ownership, URL tricks, duplicates, budgets and lease extension', () async {
    final invalid = <Map<String, Object?>>[];
    invalid.add({...mediaManifest(), 'postId': _other});
    invalid.add({...mediaManifest(), 'accountId': _id});
    invalid.add(mediaManifest(count: 10));
    invalid.add(mediaManifest(lifetime: const Duration(seconds: 61)));
    invalid.add(mediaManifest(lifetime: Duration.zero));
    for (final path in [
      'https://evil.invalid/a',
      '//evil.invalid/a',
      '/api/v1/posts/$_other/images/a/original',
      '/api/v1/posts/$_id/../x',
      '/api/v1/posts/$_id/images/a/original?token=x',
    ]) {
      final m = mediaManifest();
      ((m['images'] as List).first['original'] as Map)['path'] = path;
      invalid.add(m);
    }
    for (final field in ['mediaId', 'contentVersionId', 'position']) {
      final m = mediaManifest(count: 2);
      final items = m['images'] as List;
      items[1][field] = items[0][field];
      invalid.add(m);
    }
    for (final change in [
      {'pixelWidth': 1},
      {'frames': 121},
      {'animated': true},
      {'width': 16384, 'height': 16384},
      {
        'width': 1024,
        'height': 1024,
        'pixelWidth': 1024,
        'pixelHeight': 1024,
        'frames': 120,
        'animated': true,
      },
    ]) {
      final m = mediaManifest();
      ((m['images'] as List).first as Map).addAll(change);
      invalid.add(m);
    }
    for (final m in invalid) {
      endpoint.respond = (request) => _json(request, 200, m);
      await expectLater(
        api.imageManifest(sessionToken: _token, postId: _id),
        throwsA(isA<PostFailure>()),
      );
    }
  });

  test(
    'media errors retain fixed classification and redirects are not followed',
    () async {
      final image = PostMediaManifest.fromJson(
        mediaManifest(),
        _id,
      ).images.single;
      endpoint.respond = (request) =>
          _json(request, 404, _error('MEDIA_NOT_FOUND'), success: false);
      await expectLater(
        api.imageBytes(sessionToken: _token, postId: _id, image: image),
        throwsA(
          _failure(
            PostFailureKind.rejected,
            status: 404,
            code: 'MEDIA_NOT_FOUND',
          ),
        ),
      );
      endpoint.respond = (request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          '${endpoint.uri}/must-not-fetch',
        );
        await request.response.close();
      };
      await expectLater(
        api.imageBytes(sessionToken: _token, postId: _id, image: image),
        throwsA(isA<PostFailure>()),
      );
      expect(endpoint.requests.length, 2);
    },
  );

  test(
    'image bytes reject wrong MIME, length, cache, cookies and download policy',
    () async {
      final image = PostMediaManifest.fromJson(
        mediaManifest(),
        _id,
      ).images.single;
      for (final kind in [
        'mime',
        'short',
        'long',
        'cache',
        'cookie',
        'disposition',
        'sniff',
      ]) {
        endpoint.respond = (request) async {
          final h = request.response.headers;
          h.set('Content-Type', kind == 'mime' ? 'image/gif' : 'image/png');
          h.set(
            'Content-Disposition',
            kind == 'disposition' ? 'inline' : 'attachment',
          );
          h.set(
            'X-Content-Type-Options',
            kind == 'sniff' ? 'sniff' : 'nosniff',
          );
          h.set('Session-Expires-At', _expiry);
          h.set('Server-Time', _time);
          if (kind == 'cache') h.set('Cache-Control', 'public');
          if (kind == 'cookie') h.add('Set-Cookie', 'test=synthetic');
          request.response.add(
            List.filled(
              kind == 'short'
                  ? 7
                  : kind == 'long'
                  ? 9
                  : 8,
              1,
            ),
          );
          await request.response.close();
        };
        await expectLater(
          api.imageBytes(sessionToken: _token, postId: _id, image: image),
          throwsA(isA<PostFailure>()),
        );
      }
    },
  );
  setUp(() async {
    endpoint = await _Endpoint.start();
    api = HttpPostApi(
      communityBaseUri: endpoint.uri,
      client: endpoint.client(),
    );
  });
  tearDown(() async {
    api.close();
    await endpoint.close();
  });

  test('all14 operations use fixed C origin, exact methods/DTOs and successful authority metadata', () async {
    endpoint.respond = (r) {
      final path = r.uri.path;
      if (path == '/api/v1/post-commands/$_key' && r.method == 'PUT') {
        return _json(r, 202, _accepted());
      }
      if (path == '/api/v1/post-commands/$_key') {
        return _json(r, 200, _accepted());
      }
      if (path.endsWith('/seal')) {
        return _json(r, 200, {
          'state': 'NOT_ACCEPTED',
          'operation': 'CREATE',
          'reason': 'COMMAND_SEALED',
        });
      }
      if (path == '/api/v1/me/post-tasks') {
        return _json(r, 200, {
          'items': [_task()],
          'nextCursor': 'abc_DEF-123',
        });
      }
      if (path == '/api/v1/me/post-tasks/$_id') return _json(r, 200, _task());
      if (path.endsWith('/cancel')) {
        return _json(r, 200, {
          'state': 'COMMITTED',
          'operation': 'CANCEL',
          'taskId': _id,
          'attemptVersion': 1,
          'taskState': 'CANCELLED',
        });
      }
      if (path.endsWith('/retry')) return _json(r, 202, _accepted('RETRY', 2));
      if (path.endsWith('/hide')) {
        return _json(r, 200, {
          'state': 'COMMITTED',
          'operation': 'HIDE_TASK',
          'taskId': _id,
          'attemptVersion': 1,
        });
      }
      if (path == '/api/v1/channels/$_id/posts') {
        return _json(r, 200, {
          'items': [_card()],
          'nextCursor': null,
        });
      }
      if (path == '/api/v1/posts/$_id') {
        return _json(r, 200, {
          'post': {..._card(), 'body': ' 原始\r\n正文 '},
        });
      }
      if (path == '/api/v1/me/posts') {
        return _json(r, 200, {
          'items': [
            {'post': _card(), 'serverSortAt': _time},
          ],
          'nextCursor': null,
        });
      }
      if (path.endsWith('/capabilities')) {
        return _json(r, 200, {
          'postId': _id,
          'canDelete': true,
          'canEdit': false,
        });
      }
      if (path.endsWith('/delete')) {
        return _json(r, 200, {
          'state': 'COMMITTED',
          'operation': 'DELETE_POST',
          'postId': _id,
        });
      }
      return _json(r, 200, {
        'selectionState': 'DEFAULT_AVAILABLE',
        'defaultIdentityId': _other,
      });
    };
    final created = await api.create(
      sessionToken: _token,
      commandId: _key,
      channelId: _id,
      identityId: _other,
      title: ' 标题 ',
      body: ' 原始\r\n正文 ',
    );
    expect(created.value.state, PostCommandState.accepted);
    expect(created.serverTime, DateTime.parse(_time));
    expect(created.sessionExpiresAt, DateTime.parse(_expiry));
    expect(created.requestId, _requestId);
    expect(created.statusCode, 202);
    await api.commandResult(sessionToken: _token, commandId: _key);
    final seal = await api.seal(
      sessionToken: _token,
      commandId: _key,
      operation: PostOperation.create,
      requestDigest: List.filled(64, 'a').join(),
    );
    expect(seal.value.state, PostCommandState.notAccepted);
    await api.tasks(sessionToken: _token, cursor: 'abc_DEF-123', limit: 20);
    final task = await api.task(sessionToken: _token, taskId: _id);
    expect(task.value.content!.body, ' 原始\r\n正文 ');
    await api.cancel(
      sessionToken: _token,
      commandId: _key,
      taskId: _id,
      expectedAttemptVersion: 1,
    );
    await api.retry(
      sessionToken: _token,
      commandId: _key,
      taskId: _id,
      expectedAttemptVersion: 1,
      title: '改文字',
      body: '不换身份',
    );
    await api.hide(
      sessionToken: _token,
      commandId: _key,
      taskId: _id,
      expectedAttemptVersion: 1,
    );
    await api.feed(sessionToken: _token, channelId: _id);
    await api.detail(sessionToken: _token, postId: _id);
    await api.ownPosts(sessionToken: _token);
    await api.capabilities(sessionToken: _token, postId: _id);
    await api.delete(sessionToken: _token, commandId: _key, postId: _id);
    await api.composerContext(sessionToken: _token);
    expect(endpoint.requests, hasLength(14));
    expect(endpoint.requests.map((r) => r.method), [
      'PUT',
      'GET',
      'POST',
      'GET',
      'GET',
      'POST',
      'POST',
      'POST',
      'GET',
      'GET',
      'GET',
      'GET',
      'POST',
      'GET',
    ]);
    for (final request in endpoint.requests) {
      expect(request.headers['authorization'], ['Bearer $_token']);
      expect(request.headers['cookie'], isNull);
      expect(request.headers['accept'], ['application/json']);
      if (request.method == 'GET') expect(request.body, isEmpty);
    }
    expect(jsonDecode(endpoint.requests.first.body), {
      'channelId': _id,
      'identityId': _other,
      'title': ' 标题 ',
      'body': ' 原始\r\n正文 ',
    });
    expect(endpoint.requests[3].uri.queryParameters, {
      'cursor': 'abc_DEF-123',
      'limit': '20',
    });
    expect(jsonDecode(endpoint.requests[6].body), {
      'expectedAttemptVersion': 1,
      'title': '改文字',
      'body': '不换身份',
    });
    for (final index in [5, 6, 7, 12]) {
      expect(endpoint.requests[index].headers['idempotency-key'], [_key]);
    }
    for (final index in [0, 1, 2]) {
      expect(endpoint.requests[index].headers['idempotency-key'], isNull);
    }
    expect(endpoint.requests[12].body, isEmpty);
  });

  test('409 mutation rejection never renews; original GET exposes durable rejected receipt', () async {
    endpoint.respond = (r) => r.method == 'PUT'
        ? _json(r, 409, _error('POST_IDENTITY_UNAVAILABLE'), success: false)
        : _json(r, 200, {
            'state': 'REJECTED',
            'operation': 'CREATE',
            'errorCode': 'POST_IDENTITY_UNAVAILABLE',
          });
    await expectLater(
      api.create(
        sessionToken: _token,
        commandId: _key,
        channelId: _id,
        identityId: _other,
        title: '标题',
        body: '正文',
      ),
      throwsA(
        _failure(
          PostFailureKind.rejected,
          status: 409,
          code: 'POST_IDENTITY_UNAVAILABLE',
        ),
      ),
    );
    final observed = await api.commandResult(
      sessionToken: _token,
      commandId: _key,
    );
    expect(observed.value.state, PostCommandState.rejected);
    expect(observed.value.errorCode, 'POST_IDENTITY_UNAVAILABLE');
    expect(observed.sessionExpiresAt, DateTime.parse(_expiry));
    expect(endpoint.requests, hasLength(2));
  });

  test(
    'UNKNOWN is query-only uncertainty and cannot be fabricated as a seal',
    () async {
      endpoint.respond = (r) =>
          _json(r, 200, {'state': 'UNKNOWN_NOT_OBSERVED'});
      final result = await api.commandResult(
        sessionToken: _token,
        commandId: _key,
      );
      expect(result.value.state, PostCommandState.unknownNotObserved);
      await expectLater(
        api.seal(
          sessionToken: _token,
          commandId: _key,
          operation: PostOperation.create,
          requestDigest: List.filled(64, 'b').join(),
        ),
        throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
      );
    },
  );

  test(
    'valid error statuses retain safe codes and bounded retry delay',
    () async {
      for (final item in [
        (400, 'POST_CONTENT_INVALID'),
        (401, 'session_replaced'),
        (403, 'AUTHENTICATION_FAILED'),
        (404, 'POST_CHANNEL_UNAVAILABLE'),
        (409, 'TASK_VERSION_CONFLICT'),
        (413, 'PAYLOAD_TOO_LARGE'),
        (415, 'UNSUPPORTED_MEDIA_TYPE'),
        (429, 'RATE_LIMITED'),
        (503, 'AUTHORIZATION_UNAVAILABLE'),
      ]) {
        endpoint.respond = (r) {
          if (item.$1 == 429) r.response.headers.set('Retry-After', '300');
          return _json(r, item.$1, _error(item.$2), success: false);
        };
        final kind = item.$1 == 401
            ? PostFailureKind.unauthorized
            : item.$1 == 503
            ? PostFailureKind.unavailable
            : PostFailureKind.rejected;
        await expectLater(
          api.feed(sessionToken: _token, channelId: _id),
          throwsA(_failure(kind, status: item.$1, code: item.$2)),
        );
      }
      endpoint.respond = (r) {
        r.response.headers.set('Retry-After', '301');
        return _json(r, 429, _error('RATE_LIMITED'), success: false);
      };
      await expectLater(
        api.feed(sessionToken: _token, channelId: _id),
        throwsA(_failure(PostFailureKind.invalidResponse, status: 429)),
      );
    },
  );

  test('malformed401 still invalidates affected bearer; malformed503 remains unavailable', () async {
    for (final status in [401, 503]) {
      endpoint.respond = (r) =>
          _json(r, status, {'unexpected': 'private value'}, success: false);
      await expectLater(
        api.composerContext(sessionToken: _token),
        throwsA(
          _failure(
            status == 401
                ? PostFailureKind.unauthorized
                : PostFailureKind.unavailable,
            status: status,
          ),
        ),
      );
    }
  });

  test('strict JSON rejects duplicate keys, bad UTF8/scalars and trailing/oversized input', () async {
    final badPayloads = [
      utf8.encode(
        '{"selectionState":"SELECTION_REQUIRED","selectionState":"DEFAULT_AVAILABLE","defaultIdentityId":null}',
      ),
      utf8.encode(
        '{"selectionState":"SELECTION_REQUIRED","defaultIdentityId":null,"defaultIdentityId":null}',
      ),
      utf8.encode(
        '{"selectionState":"SELECTION_REQUIRED","defaultIdentityId":null}true',
      ),
      utf8.encode(
        '{"selectionState":"SELECTION_REQUIRED","defaultIdentityId":"\\ud800"}',
      ),
      [0xff],
      List.filled(32769, 0x20),
    ];
    for (final payload in badPayloads) {
      endpoint.respond = (r) async {
        r.response.headers.set('Session-Expires-At', _expiry);
        r.response.headers.set('Server-Time', _time);
        r.response.add(payload);
        await r.response.close();
      };
      await expectLater(
        api.composerContext(sessionToken: _token),
        throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
      );
    }
  });

  test(
    'success rejects missing/duplicate authority headers, expiry and cookies',
    () async {
      for (final change in [
        (HttpHeaders h) => h.removeAll('Server-Time'),
        (HttpHeaders h) => h.add('Server-Time', _time),
        (HttpHeaders h) => h.removeAll('Session-Expires-At'),
        (HttpHeaders h) => h.set('Session-Expires-At', _time),
        (HttpHeaders h) => h.set('Session-Expires-At', '2026-02-30T00:00:00Z'),
        (HttpHeaders h) => h.add('X-Request-ID', _key),
        (HttpHeaders h) => h.set('X-Request-ID', 'bad'),
        (HttpHeaders h) => h.set('Cache-Control', 'public'),
        (HttpHeaders h) => h.set('Content-Type', 'text/html'),
        (HttpHeaders h) =>
            h.set('Content-Type', 'application/json; charset=iso-8859-1'),
        (HttpHeaders h) => h.add('Set-Cookie', 'unwanted=1'),
      ]) {
        endpoint.respond = (r) async {
          r.response.headers.set('Server-Time', _time);
          r.response.headers.set('Session-Expires-At', _expiry);
          change(r.response.headers);
          r.response.write(
            jsonEncode({
              'selectionState': 'SELECTION_REQUIRED',
              'defaultIdentityId': null,
            }),
          );
          await r.response.close();
        };
        await expectLater(
          api.composerContext(sessionToken: _token),
          throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
        );
      }
    },
  );

  test('errors reject private extensions, status/code mismatch and success renewal', () async {
    for (final payload in [
      {..._error('POST_NOT_FOUND'), 'accountId': _other},
      {
        'error': {
          'code': 'POST_NOT_FOUND',
          'message': 'safe',
          'details': {'ownerId': _other},
        },
        'requestId': _requestId,
      },
      {..._error('POST_NOT_FOUND'), 'requestId': _key},
      _error('SQL_FAILURE'),
      _error('RATE_LIMITED'),
    ]) {
      endpoint.respond = (r) => _json(r, 404, payload, success: false);
      await expectLater(
        api.detail(sessionToken: _token, postId: _id),
        throwsA(_failure(PostFailureKind.invalidResponse, status: 404)),
      );
    }
    endpoint.respond = (r) => _json(r, 409, _error('TASK_VERSION_CONFLICT'));
    await expectLater(
      api.cancel(
        sessionToken: _token,
        commandId: _key,
        taskId: _id,
        expectedAttemptVersion: 1,
      ),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 409)),
    );
  });

  test('a mismatched command/resource/channel and noncontract successful status are rejected', () async {
    endpoint.respond = (r) => _json(r, 202, _accepted('RETRY', 1));
    await expectLater(
      api.create(
        sessionToken: _token,
        commandId: _key,
        channelId: _id,
        identityId: _other,
        title: '标题',
        body: '正文',
      ),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 202)),
    );
    endpoint.respond = (r) => _json(r, 200, {
      'post': {..._card(), 'postId': _other, 'body': '正文'},
    });
    await expectLater(
      api.detail(sessionToken: _token, postId: _id),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
    );
    endpoint.respond = (r) => _json(r, 200, {
      'items': [
        {..._card(), 'channelId': _other},
      ],
      'nextCursor': null,
    });
    await expectLater(
      api.feed(sessionToken: _token, channelId: _id),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 200)),
    );
    endpoint.respond = (r) => _json(r, 201, _accepted());
    await expectLater(
      api.create(
        sessionToken: _token,
        commandId: _key,
        channelId: _id,
        identityId: _other,
        title: '标题',
        body: '正文',
      ),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 201)),
    );
  });

  test('maximum50 legitimate own tasks and detail exceed auth response limit without truncation', () async {
    final body = '😀${List.filled(32766, '\u0301').join()}';
    endpoint.respond = (r) => r.uri.path == '/api/v1/me/post-tasks'
        ? _json(r, 200, {
            'items': List.generate(50, (_) => _task(body: body)),
            'nextCursor': null,
          })
        : _json(r, 200, _task(body: body));
    final page = await api.tasks(sessionToken: _token, limit: 50);
    expect(page.value.items, hasLength(50));
    expect(page.value.items.last.content!.body, body);
    final task = await api.task(sessionToken: _token, taskId: _id);
    expect(task.value.content!.body, body);
  });

  test('redirect never forwards a bearer to another endpoint', () async {
    final destination = await _Endpoint.start();
    addTearDown(destination.close);
    destination.respond = (r) => _json(r, 200, {'stolen': true});
    endpoint.respond = (r) {
      r.response.headers.set('Location', '${destination.uri}/stolen');
      return _json(r, 307, _error('SERVICE_UNAVAILABLE'), success: false);
    };
    await expectLater(
      api.composerContext(sessionToken: _token),
      throwsA(_failure(PostFailureKind.invalidResponse, status: 307)),
    );
    expect(endpoint.requests, hasLength(1));
    expect(destination.requests, isEmpty);
  });

  test('timeout aborts and transport never retries a mutation', () async {
    api.close();
    api = HttpPostApi(
      communityBaseUri: endpoint.uri,
      client: endpoint.client(),
      timeout: const Duration(milliseconds: 100),
    );
    endpoint.respond = (r) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _json(r, 202, _accepted());
    };
    await expectLater(
      api.create(
        sessionToken: _token,
        commandId: _key,
        channelId: _id,
        identityId: _other,
        title: '标题',
        body: '正文',
      ),
      throwsA(_failure(PostFailureKind.transport, code: 'TIMEOUT')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(endpoint.requests, hasLength(1));
  });

  test(
    'transport exceptions retain no credential, URL or body diagnostics',
    () async {
      api.close();
      api = HttpPostApi(
        communityBaseUri: endpoint.uri,
        client: _FailingClient(),
      );
      try {
        await api.composerContext(sessionToken: _token);
        fail('Expected transport failure');
      } on PostFailure catch (failure) {
        expect(failure.kind, PostFailureKind.transport);
        expect(failure.toString(), isNot(contains('Bearer')));
        expect(failure.toString(), isNot(contains('body')));
        expect(failure.toString(), isNot(contains('URL')));
      }
    },
  );

  test('client rejects invalid input before any request and origin cannot be caller-selected', () async {
    await expectLater(
      api.create(
        sessionToken: _token,
        commandId: _key,
        channelId: _id,
        identityId: _other,
        title: ' \u200b ',
        body: '正文',
      ),
      throwsA(_failure(PostFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    await expectLater(
      api.composerContext(sessionToken: '$_token='),
      throwsA(_failure(PostFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    await expectLater(
      api.tasks(sessionToken: _token, limit: 51),
      throwsA(_failure(PostFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    await expectLater(
      api.commandResult(
        sessionToken: _token,
        commandId: 'AAAAAAAAAAAAAAAAAAAAAA',
      ),
      throwsA(_failure(PostFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    expect(endpoint.requests, isEmpty);
    for (final uri in [
      'http://example.com',
      'https://u:p@example.com',
      'https://example.com/path',
      'https://example.com?select=V',
      'https://example.com#fragment',
    ]) {
      expect(
        () => HttpPostApi(communityBaseUri: Uri.parse(uri)),
        throwsArgumentError,
      );
    }
  });
}

// 合成的公开 loopback TLS 测试材料；不作为设备、真实 C 服务或生产证据。
late String _certificate;
late String _privateKey;
