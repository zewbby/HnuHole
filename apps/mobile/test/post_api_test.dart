import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_models.dart';
import 'package:hnuhole_mobile/src/posts/post_protocol.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _time = '2026-10-08T00:00:00Z';
const _expiry = '2026-10-08T01:00:00Z';
final _token = AuthCrypto.encode(List.filled(32, 7));
final _key = AuthCrypto.encode(List.filled(16, 8));
final _requestId = AuthCrypto.encode(List.filled(16, 10));

class _Captured {
  _Captured(this.method, this.uri, this.headers, this.body);
  final String method, body;
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
        final body = await utf8.decoder.bind(request).join();
        endpoint.requests.add(
          _Captured(request.method, request.uri, headers, body),
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
  late _Endpoint endpoint;
  late HttpPostApi api;
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
const _certificate = '''-----BEGIN CERTIFICATE-----
MIIDGjCCAgKgAwIBAgIUeainJsU//PbE0FJ/JhfwvJw81PwwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJMTI3LjAuMC4xMB4XDTI2MDkzMDEzNTMyMVoXDTM2MDky
NzEzNTMyMVowFDESMBAGA1UEAwwJMTI3LjAuMC4xMIIBIjANBgkqhkiG9w0BAQEF
AAOCAQ8AMIIBCgKCAQEAwnKcMVYoOlJPk3cP0T9epaBny4sjJWRZYGDXEMU2dMNP
gQvQprguHdpKXWbYCkESP7vIGl6dQ6Mg3+7a23VHwUmOHxtyfQ5da4btwCaNEdD4
HMAwmceqNP/5uRUsVqV2ophXPRSqPueQ/n8thHJoJjaaG5FuWXmyYtXMotpB1NGc
FKaRMYciz+5kPyxWwOdlgqcVGU5CQmUrr+1PmbGjQuyFwlqPdil93177FjgqG8CO
vmpshHVRwLtMBmu0a3GmryZVz5yWwkhhrw0/+Qo1P0AHh0lQ5xA2EsFM7bqzR9qn
67OPR3LS/lhLaZ755bkh1GG1qfAJ8ZmVH5EOjHP9PwIDAQABo2QwYjAdBgNVHQ4E
FgQUl06WpXjlpqVFYxuCGCiiwfNdw3owHwYDVR0jBBgwFoAUl06WpXjlpqVFYxuC
GCiiwfNdw3owDwYDVR0TAQH/BAUwAwEB/zAPBgNVHREECDAGhwR/AAABMA0GCSqG
SIb3DQEBCwUAA4IBAQCGKenINT9a7mNzSu2hWkIWGI/7MS4ZghtSKZuAI1iAbMyg
UyTL2BcmqDHzWsRUv8RVH5dLTOrsz7br4V1N2z2cAcjtgS97CvjaqH4RyBe4PYe9
+XynhGBktryTNV/4imJg0dHSjKbj9phuqsdXaFqHWf03zhtnCj+LmBzys/QRGHNn
8jA2traXXVVhkYR1rlOX8Asd4FtbgpqV2BtUBUGiRoDQNz06/tt8y94Ji5nSH14L
a5FNGUlV6d5LG7fErLvV2YUqK4/hm1CCReTKsaoZUf7u0A7pBcETJCNM9eHlQCqC
X4Q8nT4lS+LPikYXrjZVoohYlBc0+LIkQTjhWd4L
-----END CERTIFICATE-----
''';
const _privateKey = '''-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDCcpwxVig6Uk+T
dw/RP16loGfLiyMlZFlgYNcQxTZ0w0+BC9CmuC4d2kpdZtgKQRI/u8gaXp1DoyDf
7trbdUfBSY4fG3J9Dl1rhu3AJo0R0PgcwDCZx6o0//m5FSxWpXaimFc9FKo+55D+
fy2EcmgmNpobkW5ZebJi1cyi2kHU0ZwUppExhyLP7mQ/LFbA52WCpxUZTkJCZSuv
7U+ZsaNC7IXCWo92KX3fXvsWOCobwI6+amyEdVHAu0wGa7RrcaavJlXPnJbCSGGv
DT/5CjU/QAeHSVDnEDYSwUzturNH2qfrs49HctL+WEtpnvnluSHUYbWp8AnxmZUf
kQ6Mc/0/AgMBAAECggEACBm4/6X3zdr8YHrqS5MY2n+HM24opash8HQeux647D5V
6cNYCuOYKdUCzUdQIrhsdGYNqdBdO6JOtH8bDcXVNAX51LpSl63pUf+jmFV2AdMA
MxQFy+VxTGOJjLgg47v66D6+cgrFWN+FJWtsHJ0DhIWe/+nPSUAnoIE8CC2Qs1C0
vbnUuhazEX+tnxuOTOqCe5tT+3J9YB57eicJNC0ffpnWx2W63pRGPVxxYzq/BPKN
+1ezfl+FdRnaAF3SAGnGTP/nd61J8qUCccEjTzqGSuuUUonw671wJNQRSRG+LVHN
h/KL8saVqquRc4FrGCFhHhfIeaT2tSIlDcsaNzM7mQKBgQDmFLsYWX64/7AQ4xzG
5jgTMsVu/C7Qw640Rm9FVCCKSycXZM2hAAuhajoF2upiyCWJgXejGYKMs4gehr+l
KOVfeZWSy9vE3bzjYe0o7ncDN6cbB8L2dsaqye/XTpsaUmRMo2e7k0NsU9xDkuz8
vMQR5PcbNtjcURBdkjVTV1QclQKBgQDYWkGxv6a2kgtJcMQ19qBM4aYqLRgD004U
g4eqJESYuMkSNXIqFhsCR4wuLahe6zCte5OJLlr1rTEpWkHmlMOlS+ZrjS5HsBif
JDntCYpVIahVv7E8e243rSpgYU9p8E6dIStzMDmi5WdfOL/PXpWkNcTdkJEihB63
/6nIAZ+pgwKBgFfvpHJyAhUC5HAP3XfHlbcAuKTqjZoMsBAau3xr4uP4RUCTrmPS
eJ+A0hxaxypqBK7BZNBZd6P/Gg9QwP6G2uPavGgWsjBT71WYn+P9AE+ifaO/G6zH
SLcN5zULPgyZYOxJp+PxLNvCUXUiOqF+JBISyL8F/2x1LyQUNX1c6zDhAoGBAJkh
ePIIRkVepSJ78ESJpPgFloivlhnPC6q1VeZ0+SBnWdnLflyPfNpmLa/ZnRxhtvhz
SP+Fkdfll7A/M/myPa/XQuXI7YLL/wFUsLM3V3Pd+LmIjjfS3TYHGMFS3tSKw/mv
KoPDFGhZmorpLcnmll+9tvNjiXY2sU9mY5MuowVlAoGBAOF15/Gtdf/wwl4YNJJY
0+1x/xg+b3fm+gvi7un0AUcw1DRc9KyrOWQ4N9emzuiNWfWIFSB9L8hmpcWqxP1d
uy9I9Uv/X6qVEJQGS2Pi3LgxZMVj/vyxQd6AGn4IXspDoCMQhBTFuxH+3txbJnc7
DCfSU0aufQ19SXd2zMP8ywH0
-----END PRIVATE KEY-----
''';
