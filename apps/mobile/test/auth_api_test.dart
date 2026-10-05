import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/http_auth_api.dart';
import 'package:hnuhole_mobile/src/identity/identity_api.dart';
import 'package:hnuhole_mobile/src/channels/channel.dart';
import 'package:hnuhole_mobile/src/channels/channel_repository.dart';
import 'package:hnuhole_mobile/src/channels/http_channel_repository.dart';

const _account = '01234567-89ab-4def-8123-456789abcdef';
const _expiry = '2026-10-30T10:00:00Z';
const _code = 'AAAQEAYEAUDAOCAJBIFQYDIOB4';
final _token = AuthCrypto.encode(List<int>.filled(32, 7));
final _key = AuthCrypto.encode(List<int>.filled(32, 8));
final _flow = AuthCrypto.encode(List<int>.filled(32, 9));
final _cInstallation = AuthCrypto.encode(List<int>.filled(16, 1));
final _vInstallation = AuthCrypto.encode(List<int>.filled(16, 2));

class _Captured {
  _Captured(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;
}

class _FailingChannelClient implements HttpClient {
  _FailingChannelClient(this.failure);
  final IOException failure;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) => Future.error(failure);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Endpoint {
  _Endpoint(this.server);
  final HttpServer server;
  final requests = <_Captured>[];
  Future<void> Function(HttpRequest request)? respond;
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
        final headers = <String, String>{};
        request.headers.forEach(
          (key, values) => headers[key] = values.join(','),
        );
        final body = await utf8.decoder.bind(request).join();
        endpoint.requests.add(
          _Captured(request.method, request.uri.toString(), headers, body),
        );
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.headers.set(
          'X-Request-ID',
          AuthCrypto.encode(List<int>.filled(16, 10)),
        );
        request.response.headers.contentType = ContentType.json;
        await endpoint.respond!(request);
      } on Object {
        // Client timeout intentionally aborts its socket.
      }
    });
    return endpoint;
  }

  Future<void> close() => server.close(force: true);
}

Future<void> _json(
  HttpRequest request,
  int status,
  Object payload, {
  bool session = false,
}) async {
  request.response.statusCode = status;
  if (session) request.response.headers.set('Session-Expires-At', _expiry);
  request.response.write(jsonEncode(payload));
  await request.response.close();
}

Map<String, Object> _session() => {
  'accountId': _account,
  'sessionToken': _token,
  'expiresAt': _expiry,
};
Map<String, Object> _error(String code) => {
  'error': {'code': code, 'message': 'generic failure'},
  'requestId': AuthCrypto.encode(List<int>.filled(16, 10)),
};
Matcher _failure(AuthFailureKind kind, {int? status, String? code}) =>
    isA<AuthFailure>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.statusCode, 'status', status)
        .having((e) => e.code, 'code', code);

void main() {
  late _Endpoint community;
  late _Endpoint verifier;
  late HttpAuthApi api;
  late HttpChannelRepository channels;

  setUp(() async {
    community = await _Endpoint.start();
    verifier = await _Endpoint.start();
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(_certificate));
    final client = HttpClient(context: context)
      ..badCertificateCallback = (certificate, host, port) =>
          host == '127.0.0.1' &&
          (port == community.server.port || port == verifier.server.port) &&
          certificate.pem.trim() == _certificate.trim();
    api = HttpAuthApi(
      communityBaseUri: community.uri,
      verifierBaseUri: verifier.uri,
      client: client,
    );
    channels = HttpChannelRepository(baseUri: community.uri, client: client);
  });
  tearDown(() async {
    api.close();
    channels.close();
    await community.close();
    await verifier.close();
  });

  Map<String, Object> directory() => {
    'channels': [
      for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
        {
          'id': '00000000-0000-0000-0000-00000000000${i + 1}',
          'code': ChannelDirectory.requiredCodes[i],
          'name': 'Channel ${i + 1}',
          'initiallyVisible': i < 5,
          'displayOrder': i + 1,
        },
    ],
  };

  Map<String, Object?> identityDirectory() => {
    'identities': [
      {
        'id': _account,
        'nickname': '春风',
        'avatar': 'default-v1',
        'isOriginal': true,
        'createdAt': '2026-10-02T10:00:00Z',
        'renameAvailableAt': null,
      },
    ],
    'createdCount': 1,
    'nextCreateAt': null,
    'serverTime': '2026-10-03T10:00:00Z',
  };
  Map<String, Object?> identityOutcome({
    String state = 'COMMITTED',
    String? operation = 'CREATE',
    String? id = _account,
    String? errorCode,
  }) => {
    'state': state,
    'operation': operation,
    'identityId': id,
    'errorCode': errorCode,
  };

  test('identity directory allows explicit lifecycle nulls and authoritative expiry', () async {
    community.respond = (request) =>
        _json(request, 200, identityDirectory(), session: true);
    final result = await api.identities(_token);
    expect(result.identities.single.nickname, '春风');
    expect(result.identities.single.renameAvailableAt, isNull);
    expect(result.createdCount, 1);
    expect(result.nextCreateAt, isNull);
    expect(result.sessionExpiresAt, DateTime.parse(_expiry));
    expect(community.requests.single.path, '/api/v1/identities');
    expect(
      community.requests.single.headers['authorization'],
      'Bearer $_token',
    );
    final empty = {
      'identities': [],
      'createdCount': 0,
      'nextCreateAt': null,
      'serverTime': '2026-10-03T10:00:00Z',
    };
    community.respond = (request) => _json(request, 200, empty, session: true);
    expect((await api.identities(_token)).identities, isEmpty);
  });

  test('identity mutation wire uses UUID targets key16 and immutable nickname only', () async {
    final key = AuthCrypto.encode(List<int>.filled(16, 8));
    for (final operation in IdentityOperation.values) {
      community.respond = (request) => _json(
        request,
        200,
        identityOutcome(operation: operation.name.toUpperCase()),
        session: true,
      );
      await api.changeIdentity(
        sessionToken: _token,
        idempotencyKey: key,
        operation: operation,
        identityId: operation == IdentityOperation.create ? null : _account,
        nickname: operation == IdentityOperation.delete ? null : '春风',
      );
    }
    expect(community.requests.map((r) => r.method), [
      'POST',
      'PATCH',
      'DELETE',
    ]);
    expect(community.requests.map((r) => r.path), [
      '/api/v1/identities',
      '/api/v1/identities/$_account',
      '/api/v1/identities/$_account',
    ]);
    expect(community.requests.map((r) => r.body), [
      '{"nickname":"春风"}',
      '{"nickname":"春风"}',
      '',
    ]);
    expect(
      community.requests.every((r) => r.headers['idempotency-key'] == key),
      isTrue,
    );
    await expectLater(
      api.changeIdentity(
        sessionToken: _token,
        idempotencyKey: _key,
        operation: IdentityOperation.create,
        nickname: '春风',
      ),
      throwsA(_failure(AuthFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    expect(community.requests, hasLength(3));
  });

  test('identity result is bodyless key16 query and rejects missing terminal field', () async {
    final key = AuthCrypto.encode(List<int>.filled(16, 8));
    community.respond = (request) => _json(
      request,
      200,
      identityOutcome(state: 'NOT_FOUND', operation: null, id: null),
      session: true,
    );
    final missing = await api.identityChangeResult(
      sessionToken: _token,
      idempotencyKey: key,
    );
    expect(missing.committed, isFalse);
    expect(missing.rejected, isFalse);
    expect(community.requests.single.method, 'GET');
    expect(community.requests.single.path, '/api/v1/identity-change-result');
    expect(community.requests.single.body, '');
    community.respond = (request) => _json(
      request,
      200,
      identityOutcome(
        state: 'REJECTED',
        operation: 'RENAME',
        id: null,
        errorCode: 'IDENTITY_DUPLICATE_NAME',
      ),
      session: true,
    );
    final rejected = await api.identityChangeResult(
      sessionToken: _token,
      idempotencyKey: key,
    );
    expect(rejected.rejected, isTrue);
    expect(rejected.operation, IdentityOperation.rename);
    for (final payload in [
      identityOutcome()..remove('errorCode'),
      identityOutcome(state: 'NOT_FOUND', operation: 'CREATE', id: null),
      identityOutcome(
        state: 'REJECTED',
        id: null,
        errorCode: 'SESSION_INVALID',
      ),
      identityOutcome(state: 'COMMITTED', errorCode: 'IDENTITY_LIMIT'),
    ]) {
      community.respond = (request) =>
          _json(request, 200, payload, session: true);
      await expectLater(
        api.identityChangeResult(sessionToken: _token, idempotencyKey: key),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
    }
  });

  test('identity response failure and malformed expiry never indicate committed outcome', () async {
    final key = AuthCrypto.encode(List<int>.filled(16, 8));
    community.respond = (request) => _json(request, 200, identityOutcome());
    await expectLater(
      api.changeIdentity(
        sessionToken: _token,
        idempotencyKey: key,
        operation: IdentityOperation.create,
        nickname: '春风',
      ),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
    community.respond = (request) => _json(
      request,
      200,
      identityOutcome(operation: 'DELETE'),
      session: true,
    );
    await expectLater(
      api.changeIdentity(
        sessionToken: _token,
        idempotencyKey: key,
        operation: IdentityOperation.create,
        nickname: '春风',
      ),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
    community.respond = (request) =>
        _json(request, 409, _error('IDENTITY_LAST_REQUIRED'));
    await expectLater(
      api.changeIdentity(
        sessionToken: _token,
        idempotencyKey: key,
        operation: IdentityOperation.delete,
        identityId: _account,
      ),
      throwsA(
        _failure(
          AuthFailureKind.rejected,
          status: 409,
          code: 'IDENTITY_LAST_REQUIRED',
        ),
      ),
    );
  });

  test('identity directory validates default avatar unique owners and byte valid long graphemes', () async {
    final payload = identityDirectory();
    final items = payload['identities'] as List<Map<String, Object?>>;
    items.single['nickname'] = 'a${List.filled(245, '\u0301').join()}b';
    community.respond = (request) =>
        _json(request, 200, payload, session: true);
    expect(
      (await api.identities(_token)).identities.single.nickname,
      items.single['nickname'],
    );
    for (final bad in ['unknown-avatar', null]) {
      items.single['avatar'] = bad;
      await expectLater(
        api.identities(_token),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
    }
  });

  test(
    'directory TLS response carries complete nodes and authoritative deadline',
    () async {
      community.respond = (request) =>
          _json(request, 200, directory(), session: true);
      final result = await channels.loadChannels(sessionToken: _token);
      expect(result.channels, hasLength(7));
      expect(result.expiresAt, DateTime.parse(_expiry));
      expect(community.requests.single.path, '/api/v1/channels');
      expect(
        community.requests.single.headers['authorization'],
        'Bearer $_token',
      );
    },
  );

  test(
    'directory rejects missing ambiguous or invalid authoritative deadline',
    () async {
      for (final expiry in <String?>[
        null,
        '2026-10-30T10:00:00+00:00',
        '2026-02-30T10:00:00Z',
        '2026-10-30T10:00:00Z,2026-10-31T10:00:00Z',
        'not-a-deadline',
      ]) {
        community.respond = (request) async {
          if (expiry != null) {
            request.response.headers.set('Session-Expires-At', expiry);
          }
          await _json(request, 200, directory());
        };
        await expectLater(
          channels.loadChannels(sessionToken: _token),
          throwsA(
            isA<ChannelRepositoryException>().having(
              (e) => e.code,
              'code',
              'invalid_channel_directory',
            ),
          ),
        );
      }
    },
  );

  test('directory rejects partial nodes even with a valid deadline', () async {
    community.respond = (request) =>
        _json(request, 200, {'channels': <Object>[]}, session: true);
    await expectLater(
      channels.loadChannels(sessionToken: _token),
      throwsA(
        isA<ChannelRepositoryException>().having(
          (e) => e.code,
          'code',
          'invalid_channel_directory',
        ),
      ),
    );
  });

  test(
    'directory parses wrapper status code and top-level request ID over TLS',
    () async {
      for (final entry in {
        400: 'MALFORMED_REQUEST',
        401: 'session_replaced',
        403: 'AUTHENTICATION_FAILED',
        429: 'RATE_LIMITED',
        503: 'SERVICE_UNAVAILABLE',
      }.entries) {
        community.respond = (request) =>
            _json(request, entry.key, _error(entry.value));
        await expectLater(
          channels.loadChannels(sessionToken: _token),
          throwsA(
            isA<ChannelRepositoryException>()
                .having((e) => e.statusCode, 'status', entry.key)
                .having((e) => e.code, 'code', entry.value)
                .having(
                  (e) => e.isUnauthorized,
                  'unauthorized',
                  entry.key == 401,
                )
                .having(
                  (e) => e.requestId,
                  'request ID',
                  AuthCrypto.encode(List<int>.filled(16, 10)),
                ),
          ),
        );
      }
    },
  );

  test('directory TLS failures discard untrusted diagnostic fields without changing authorization status', () async {
    const private =
        'Exact.Case+alias@hainanu.edu.cn OTP-123456 password-private recovery-private';
    for (final status in [401, 429, 503]) {
      community.respond = (request) async {
        request.response.headers.set('X-Request-ID', _token);
        await _json(request, status, {
          'error': {
            'code': private,
            'message': private,
            'details': {'secret': _key},
          },
          'requestId': _token,
        });
      };
      try {
        await channels.loadChannels(sessionToken: _token);
        fail('Expected directory rejection');
      } on ChannelRepositoryException catch (error) {
        expect(error.statusCode, status);
        expect(error.isUnauthorized, status == 401);
        expect(error.code, isNull);
        expect(error.requestId, isNull);
        expect(error.message, isNot(contains(private)));
        expect(error.toString(), isNot(contains(_token)));
        expect(error.toString(), isNot(contains(_key)));
      }
    }
  });

  test('directory TLS diagnostic request ID must be canonical and agree with its header', () async {
    final header = AuthCrypto.encode(List<int>.filled(16, 10));
    for (final bodyID in [_token, 'private@hainanu.edu.cn', _cInstallation]) {
      community.respond = (request) => _json(request, 503, {
        'error': {'code': 'SERVICE_UNAVAILABLE', 'message': 'generic failure'},
        'requestId': bodyID,
      });
      try {
        await channels.loadChannels(sessionToken: _token);
        fail('Expected directory rejection');
      } on ChannelRepositoryException catch (error) {
        expect(error.statusCode, 503);
        expect(error.code, 'SERVICE_UNAVAILABLE');
        expect(error.requestId, isNull);
        expect(error.toString(), isNot(contains(bodyID)));
      }
    }
    community.respond = (request) =>
        _json(request, 503, _error('SERVICE_UNAVAILABLE'));
    await expectLater(
      channels.loadChannels(sessionToken: _token),
      throwsA(
        isA<ChannelRepositoryException>().having(
          (e) => e.requestId,
          'request ID',
          header,
        ),
      ),
    );
  });

  test('directory transport failures never retain raw socket TLS or HTTP exception text', () async {
    const private =
        'private@hainanu.edu.cn OTP-123456 password-private recovery-private';
    for (final failure in <IOException>[
      const SocketException(private),
      const HandshakeException(private),
      const HttpException(private),
    ]) {
      final transport = HttpChannelRepository(
        baseUri: community.uri,
        client: _FailingChannelClient(failure),
      );
      try {
        await transport.loadChannels(sessionToken: _token);
        fail('Expected directory transport failure');
      } on ChannelRepositoryException catch (error) {
        expect(error.message, 'The channel service is unavailable');
        expect(error.statusCode, isNull);
        expect(error.code, isNull);
        expect(error.requestId, isNull);
        expect(error.toString(), isNot(contains(private)));
      } finally {
        transport.close();
      }
    }
  });

  test('auth TLS failures preserve safe error classes without retaining response secrets', () async {
    const private =
        'private@hainanu.edu.cn OTP-123456 password-private recovery-private';
    for (final status in [401, 503]) {
      community.respond = (request) => _json(request, status, {
        'error': {
          'code': status == 401
              ? 'AUTHENTICATION_FAILED'
              : 'SERVICE_UNAVAILABLE',
          'message': private,
          'details': {'email': private, 'bearer': _token},
        },
        'requestId': AuthCrypto.encode(List<int>.filled(16, 10)),
      });
      try {
        await api.currentSession(_token);
        fail('Expected authentication failure');
      } on AuthFailure catch (error) {
        expect(error.statusCode, status);
        expect(
          error.kind,
          status == 401
              ? AuthFailureKind.unauthorized
              : AuthFailureKind.unavailable,
        );
        expect(
          error.code,
          status == 401 ? 'AUTHENTICATION_FAILED' : 'SERVICE_UNAVAILABLE',
        );
        expect(error.toString(), isNot(contains(private)));
        expect(error.toString(), isNot(contains(_token)));
      }
    }
  });

  test('only fixed independent HTTPS origins are accepted', () {
    for (final origin in [
      'http://example.test',
      'https://user@example.test',
      'https://example.test/auth',
      'https://example.test?host=evil',
      'https://example.test#fragment',
    ]) {
      expect(
        () => HttpAuthApi(
          communityBaseUri: Uri.parse(origin),
          verifierBaseUri: verifier.uri,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => HttpAuthApi(
        communityBaseUri: community.uri,
        verifierBaseUri: community.uri,
      ),
      throwsArgumentError,
    );
  });

  test(
    'OTP and login use independent origins installation IDs and payloads',
    () async {
      verifier.respond = (r) =>
          _json(r, 202, {'flowId': _flow, 'retryAfterSeconds': 60});
      community.respond = (r) => _json(r, 201, _session(), session: true);
      final otp = await api.requestOtp(
        email: 'Exact.Case+alias@hainanu.edu.cn',
        installationId: _vInstallation,
        idempotencyKey: _key,
      );
      expect(otp.flowId, _flow);
      final session = await api.login(
        username: 'private_user',
        password: 'a long private password',
        installationId: _cInstallation,
        idempotencyKey: _token,
      );
      expect(session.sessionToken, _token);
      final v = verifier.requests.single;
      expect(jsonDecode(v.body), {'email': 'Exact.Case+alias@hainanu.edu.cn'});
      expect(v.headers['v-installation-id'], _vInstallation);
      expect(v.headers['idempotency-key'], _key);
      final c = community.requests.single;
      expect(jsonDecode(c.body), {
        'username': 'private_user',
        'password': 'a long private password',
        'installationId': _cInstallation,
      });
      expect(c.headers.containsKey('v-installation-id'), isFalse);
      expect(c.headers.containsKey('otp-flow-id'), isFalse);
      expect(c.headers.containsKey('x-request-id'), isFalse);
      expect(c.headers.containsKey('traceparent'), isFalse);
      expect(v.headers.containsKey('authorization'), isFalse);
      expect(c.body, isNot(contains('hainanu.edu.cn')));
    },
  );

  test(
    'normal session and independent revocation capabilities never mix',
    () async {
      community.respond = (r) async {
        if (r.uri.path.endsWith('session-revocations')) {
          r.response.statusCode = 204;
          await r.response.close();
        } else {
          await _json(r, 200, {
            'accountId': _account,
            'username': 'private_user',
            'expiresAt': _expiry,
          }, session: true);
        }
      };
      expect((await api.currentSession(_token)).username, 'private_user');
      final secret = AuthCrypto.revocationSecret(_token);
      await api.revokeSession(secret);
      expect(community.requests[0].headers['authorization'], 'Bearer $_token');
      expect(
        community.requests[1].headers['authorization'],
        'SessionRevoke $secret',
      );
      expect(community.requests[1].body, isEmpty);
      expect(
        community.requests[1].headers.containsKey('idempotency-key'),
        isFalse,
      );
      expect(community.requests[1].path, isNot(contains(secret)));
      expect(verifier.requests, isEmpty);
    },
  );

  test(
    'reset result and closure status use scoped headers with no URL secrets',
    () async {
      community.respond = (r) => r.uri.path.endsWith('password-reset-result')
          ? _json(r, 202, {'state': 'PENDING'})
          : _json(r, 200, {'state': 'PENDING', 'dueAt': _expiry});
      expect(
        await api.passwordResetResult(
          resetIntentId: _flow,
          idempotencyKey: _key,
        ),
        PasswordResetResult.pending,
      );
      final closure = await api.closureStatus(
        closureId: _flow,
        statusSecret: _token,
      );
      expect(closure.state, ClosureState.pending);
      expect(
        community.requests[0].headers['authorization'],
        'ResetResult $_key',
      );
      expect(community.requests[0].headers['reset-intent-id'], _flow);
      expect(
        community.requests[1].headers['authorization'],
        'ClosureStatus $_token',
      );
      expect(community.requests[1].path, '/api/v1/account-closures/$_flow');
      for (final request in community.requests) {
        expect(request.path, isNot(contains(_token)));
        expect(request.path, isNot(contains(_key)));
        expect(request.body, isEmpty);
      }
    },
  );

  test(
    'OTP original polls distinguish unknown from irreversible results',
    () async {
      verifier.respond = (r) => r.uri.path.endsWith('otp-request-result')
          ? _json(r, 202, {'state': 'PENDING', 'retryAfterSeconds': 3})
          : _json(r, 200, {'state': 'TICKET_AVAILABLE'});
      final sending = await api.otpRequestResult(
        installationId: _vInstallation,
        idempotencyKey: _key,
      );
      expect(sending.state, OtpRequestState.pending);
      final confirmation = await api.otpConfirmationResult(
        flowId: _flow,
        installationId: _vInstallation,
        idempotencyKey: _token,
      );
      expect(confirmation.state, OtpConfirmationState.ticketAvailable);
      expect(
        verifier.requests[0].headers['authorization'],
        'OtpRequestResult $_key',
      );
      expect(
        verifier.requests[1].headers['authorization'],
        'OtpConfirmationResult $_token',
      );
      expect(verifier.requests[1].headers['otp-flow-id'], _flow);
    },
  );

  test(
    'registration sends only the fixed ticket and PoP across C boundary',
    () async {
      final vectors = jsonDecode(
        File('../../packages/auth-protocol-vectors/v1.json').readAsStringSync(),
      ) as Map;
      final signatures = vectors['positiveSignatures'] as List;
      final ticket = signatures.firstWhere(
        (v) => v['id'] == 'SIG_REGISTER_CURRENT',
      ) as Map;
      final proof =
          signatures.firstWhere((v) => v['id'] == 'SIG_BOOTSTRAP_POP') as Map;
      final wire = ticket['wireBase64url'] as String;
      final parsed = AuthCrypto.parseRegistrationTicket(wire);
      verifier.respond = (r) => _json(r, 200, {'registrationTicket': wire});
      community.respond = (r) => r.uri.path.endsWith('registration-intents')
          ? _json(r, 201, {
              'intentId': _flow,
              'challenge': _key,
              'expiresAt': _expiry,
              'recoveryCode': _code,
            })
          : _json(r, 201, _session(), session: true);
      final confirmed = await api.confirmOtp(
        flowId: _flow,
        otp: '123456',
        slotId: parsed.slotId,
        bootstrapPublicKey: parsed.bootstrapPublicKey,
        installationId: _vInstallation,
        idempotencyKey: _key,
      );
      expect(confirmed.registrationTicket, wire);
      final intent = await api.createRegistrationIntent(
        registrationTicket: wire,
        username: 'private_user',
        password: 'private long password',
        installationId: _cInstallation,
      );
      expect(intent.challenge, _key);
      final session = await api.commitRegistration(
        intentId: intent.intentId,
        bootstrapSignature: proof['wireBase64url'] as String,
        recoveryCodeConfirmation: intent.recoveryCode,
        idempotencyKey: _token,
      );
      expect(session.accountId, _account);
      final creation = jsonDecode(community.requests[0].body) as Map;
      expect(creation.keys.toSet(), {
        'registrationTicket',
        'username',
        'password',
        'installationId',
      });
      expect(creation['registrationTicket'], wire);
      final commit = jsonDecode(community.requests[1].body) as Map;
      expect(commit.keys.toSet(), {
        'intentId',
        'bootstrapSignature',
        'recoveryCodeConfirmation',
      });
      expect(community.requests[1].headers['idempotency-key'], _token);
      expect(
        community.requests[0].headers.containsKey('v-installation-id'),
        isFalse,
      );
      expect(
        community.requests[0].headers.containsKey('idempotency-key'),
        isFalse,
      );
    },
  );

  test('server ticket must match original local slot and public key', () async {
    final vectors = jsonDecode(
      File('../../packages/auth-protocol-vectors/v1.json').readAsStringSync(),
    ) as Map;
    final ticket = (vectors['positiveSignatures'] as List).firstWhere(
      (v) => v['id'] == 'SIG_REGISTER_CURRENT',
    ) as Map;
    verifier.respond = (r) =>
        _json(r, 200, {'registrationTicket': ticket['wireBase64url']});
    final attacker = await AuthCrypto.bootstrapKeyFromSeed(
      AuthCrypto.encode(List<int>.generate(32, (i) => i)),
    );
    await expectLater(
      api.confirmOtp(
        flowId: _flow,
        otp: '123456',
        slotId: attacker.slotId,
        bootstrapPublicKey: attacker.publicKey,
        installationId: _vInstallation,
        idempotencyKey: _key,
      ),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
    expect(community.requests, isEmpty);
  });

  test('closure submission binds original ID and does not reuse bearer on status reads', () async {
    community.respond = (r) => r.method == 'POST'
        ? _json(r, 202, {'closureId': _flow, 'dueAt': _expiry})
        : _json(r, 200, {'state': 'CANCELLED'});
    final digest = AuthCrypto.closureStatusDigest(_key);
    final accepted = await api.requestClosure(
      sessionToken: _token,
      password: 'private password',
      closureId: _flow,
      statusDigest: digest,
    );
    expect(accepted.closureId, _flow);
    expect(
      (await api.closureStatus(closureId: _flow, statusSecret: _key)).state,
      ClosureState.cancelled,
    );
    expect(jsonDecode(community.requests[0].body), {
      'password': 'private password',
      'closureId': _flow,
      'statusDigest': digest,
    });
    expect(community.requests[0].headers['authorization'], 'Bearer $_token');
    expect(
      community.requests[1].headers['authorization'],
      'ClosureStatus $_key',
    );
    expect(
      community.requests[0].headers.containsKey('idempotency-key'),
      isFalse,
    );
  });

  test(
    'rotation and removal bind fixed intents and secret-free 204 confirmations',
    () async {
      final credential = AuthCrypto.encode([1, 2, 3, 4]);
      community.respond = (r) async {
        r.response.headers.set('Session-Expires-At', _expiry);
        if (r.uri.path.endsWith('recovery-credentials')) {
          await _json(r, 200, {
            'recoveryCodeAvailable': true,
            'passkeys': [
              {
                'credentialId': credential,
                'createdAt': _expiry,
                'backupEligible': true,
                'backedUp': false,
              },
            ],
          });
        } else if (r.uri.path.endsWith('recovery-code-rotations')) {
          await _json(r, 201, {
            'rotationIntentId': _flow,
            'expiresAt': _expiry,
            'newRecoveryCode': _code,
          });
        } else if (r.uri.path.endsWith('passkey-removal-intents')) {
          await _json(r, 201, {'removalIntentId': _flow, 'expiresAt': _expiry});
        } else {
          r.response.statusCode = 204;
          await r.response.close();
        }
      };
      expect(
        (await api.recoveryCredentials(_token)).passkeys.single.credentialId,
        credential,
      );
      final rotation = await api.createRecoveryCodeRotation(
        sessionToken: _token,
        password: 'private password',
      );
      await api.confirmRecoveryCodeRotation(
        sessionToken: _token,
        rotationIntentId: rotation.rotationIntentId,
        newRecoveryCodeConfirmation: rotation.newRecoveryCode,
        idempotencyKey: _key,
      );
      final removal = await api.createPasskeyRemovalIntent(
        sessionToken: _token,
        credentialId: credential,
        password: 'private password',
      );
      await api.removePasskey(
        sessionToken: _token,
        credentialId: credential,
        removalIntentId: removal.removalIntentId,
        idempotencyKey: _flow,
      );
      final deletion = community.requests.last;
      expect(deletion.method, 'DELETE');
      expect(deletion.body, isEmpty);
      expect(deletion.path, '/api/v1/auth/passkeys/$credential');
      expect(deletion.headers['credential-change-id'], _flow);
      expect(deletion.headers['idempotency-key'], _flow);
    },
  );

  test('device list has only current and recent roles plus authoritative session metadata', () async {
    community.respond = (r) => _json(r, 200, {
      'current': {'role': 'CURRENT', 'signedInAt': '2026-10-02T00:00:00Z'},
      'lastReplaced': {
        'role': 'REPLACED',
        'signedInAt': '2026-10-01T00:00:00Z',
        'replacedAt': '2026-10-02T00:00:00Z',
      },
    }, session: true);
    final result = await api.devices(_token);
    expect(result.sessionExpiresAt, DateTime.parse(_expiry));
    expect(result.lastReplacedAt, DateTime.utc(2026, 10, 2));
    expect(
      community.requests.single.headers['authorization'],
      'Bearer $_token',
    );
    expect(community.requests.single.body, isEmpty);
    community.respond = (r) => _json(r, 200, {
      'current': {
        'role': 'CURRENT',
        'signedInAt': _expiry,
        'installationId': _cInstallation,
      },
    }, session: true);
    await expectLater(
      api.devices(_token),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
  });

  test('credential result queries original intent and key without resending any secret', () async {
    const states = {
      'PENDING': CredentialChangeState.pending,
      'COMMITTED': CredentialChangeState.committed,
      'NOT_COMMITTED': CredentialChangeState.notCommitted,
    };
    for (final state in states.entries) {
      community.respond = (r) =>
          _json(r, 200, {'state': state.key}, session: true);
      final result = await api.credentialChangeResult(
        sessionToken: _token,
        changeId: _flow,
        idempotencyKey: _key,
      );
      expect(result.state, state.value);
      expect(result.sessionExpiresAt, DateTime.parse(_expiry));
    }
    expect(community.requests, hasLength(3));
    final request = community.requests.first;
    expect(request.method, 'GET');
    expect(request.path, '/api/v1/auth/credential-change-result');
    expect(request.body, isEmpty);
    expect(request.headers['authorization'], 'Bearer $_token');
    expect(request.headers['credential-change-id'], _flow);
    expect(request.headers['idempotency-key'], _key);
    community.respond = (r) =>
        _json(r, 202, {'state': 'PENDING'}, session: true);
    await expectLater(
      api.credentialChangeResult(
        sessionToken: _token,
        changeId: _flow,
        idempotencyKey: _key,
      ),
      throwsA(_failure(AuthFailureKind.invalidResponse, status: 202)),
    );
  });

  test(
    'management success without authoritative metadata remains unknown',
    () async {
      community.respond = (r) =>
          _json(r, 200, {'recoveryCodeAvailable': true, 'passkeys': []});
      await expectLater(
        api.recoveryCredentials(_token),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
      community.respond = (r) async {
        r.response.statusCode = 204;
        await r.response.close();
      };
      await expectLater(
        api.removePasskey(
          sessionToken: _token,
          credentialId: AuthCrypto.encode([1, 2, 3]),
          removalIntentId: _flow,
          idempotencyKey: _key,
        ),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
    },
  );

  Map<String, Object> creationOptions() => {
    'challenge': _key,
    'rp': {'id': community.uri.host, 'name': 'Hnuhole'},
    'user': {'id': _flow, 'name': _flow, 'displayName': 'Hnuhole account'},
    'pubKeyCredParams': [
      {'type': 'public-key', 'alg': -7},
    ],
    'timeout': 60000,
    'excludeCredentials': [],
    'authenticatorSelection': {
      'residentKey': 'required',
      'requireResidentKey': true,
      'userVerification': 'required',
    },
    'attestation': 'none',
  };
  Map<String, dynamic> nativeAttestation() {
    final credential = AuthCrypto.encode([1, 2, 3, 4]);
    return {
      'id': credential,
      'rawId': credential,
      'type': 'public-key',
      'response': {
        'clientDataJSON': AuthCrypto.encode([1]),
        'attestationObject': AuthCrypto.encode([1]),
        'transports': ['internal'],
      },
      'clientExtensionResults': <String, Object>{},
    };
  }

  test(
    'Passkey binding carries reviewed C options and one exact native response',
    () async {
      community.respond = (r) async {
        if (r.uri.path.endsWith('passkey-options')) {
          await _json(r, 200, {
            'challengeId': _flow,
            'expiresAt': _expiry,
            'publicKey': creationOptions(),
          }, session: true);
        } else {
          r.response.headers.set('Session-Expires-At', _expiry);
          r.response.statusCode = 204;
          await r.response.close();
        }
      };
      final options = await api.createPasskeyCreationOptions(
        sessionToken: _token,
        password: 'fresh password',
      );
      expect(options.sessionExpiresAt, DateTime.parse(_expiry));
      expect(options.publicKey['attestation'], 'none');
      expect(
        () => options.publicKey['attestation'] = 'direct',
        throwsUnsupportedError,
      );
      expect(jsonDecode(community.requests.single.body), {
        'password': 'fresh password',
      });
      final native = nativeAttestation();
      expect(
        await api.registerPasskey(
          sessionToken: _token,
          challengeId: options.challengeId,
          attestation: native,
          idempotencyKey: _key,
        ),
        DateTime.parse(_expiry),
      );
      expect(jsonDecode(community.requests.last.body), {
        'challengeId': _flow,
        'webauthnAttestation': native,
      });
      expect(community.requests.last.headers['idempotency-key'], _key);
    },
  );

  test('Passkey options reject foreign RP and weaker verification before native ceremony', () async {
    for (final mutation in <void Function(Map<String, Object>)>[
      (m) => m['rp'] = {'id': 'elsewhere.invalid', 'name': 'Hnuhole'},
      (m) => m['attestation'] = 'direct',
      (m) => m['authenticatorSelection'] = {
        'residentKey': 'preferred',
        'requireResidentKey': false,
        'userVerification': 'required',
      },
      (m) => m['pubKeyCredParams'] = [
        {'type': 'public-key', 'alg': -257},
      ],
      (m) => m['user'] = {
        'id': _flow,
        'name': 'private_user',
        'displayName': 'Hnuhole account',
      },
      (m) => m['extensions'] = {'unreviewed': true},
    ]) {
      final publicKey = creationOptions();
      mutation(publicKey);
      community.respond = (r) => _json(r, 200, {
        'challengeId': _flow,
        'expiresAt': _expiry,
        'publicKey': publicKey,
      }, session: true);
      await expectLater(
        api.createPasskeyCreationOptions(
          sessionToken: _token,
          password: 'fresh password',
        ),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
    }
  });

  test(
    'discoverable Passkey recovery sends no identity hint or bearer',
    () async {
      final credential = AuthCrypto.encode([1, 2, 3, 4]);
      final assertion = <String, dynamic>{
        'id': credential,
        'rawId': credential,
        'type': 'public-key',
        'response': {
          'clientDataJSON': AuthCrypto.encode([1]),
          'authenticatorData': AuthCrypto.encode(List<int>.filled(37, 0)),
          'signature': AuthCrypto.encode(List<int>.filled(8, 0)),
          'userHandle': _key,
        },
        'clientExtensionResults': <String, Object>{},
      };
      community.respond = (r) {
        if (r.uri.path.endsWith('passkey-reset-options')) {
          return _json(r, 200, {
            'challengeId': _flow,
            'expiresAt': _expiry,
            'publicKey': {
              'challenge': _key,
              'rpId': community.uri.host,
              'timeout': 60000,
              'userVerification': 'required',
            },
          });
        }
        return _json(r, 201, {
          'resetIntentId': _flow,
          'expiresAt': _expiry,
          'username': 'private_user',
          'newRecoveryCode': _code,
        });
      };
      final options = await api.createPasskeyResetOptions();
      expect(options.sessionExpiresAt, isNull);
      final result = await api.createPasskeyResetIntent(
        challengeId: options.challengeId,
        assertion: assertion,
      );
      expect(result.resetIntentId, _flow);
      expect(jsonDecode(community.requests.first.body), <String, Object>{});
      expect(jsonDecode(community.requests.last.body), {
        'challengeId': _flow,
        'webauthnAssertion': assertion,
      });
      expect(
        community.requests.every(
          (r) => !r.headers.containsKey('authorization'),
        ),
        isTrue,
      );
      expect(
        community.requests.every(
          (r) => !r.headers.containsKey('idempotency-key'),
        ),
        isTrue,
      );
      expect(verifier.requests, isEmpty);
    },
  );

  test('native payload with duplicate identity or extension is rejected before POST', () async {
    final native = nativeAttestation()..['rawId'] = _flow;
    await expectLater(
      api.registerPasskey(
        sessionToken: _token,
        challengeId: _flow,
        attestation: native,
        idempotencyKey: _key,
      ),
      throwsA(_failure(AuthFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    expect(community.requests, isEmpty);
    final extension = nativeAttestation()
      ..['clientExtensionResults'] = {'unreviewed': true};
    await expectLater(
      api.registerPasskey(
        sessionToken: _token,
        challengeId: _flow,
        attestation: extension,
        idempotencyKey: _key,
      ),
      throwsA(_failure(AuthFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    expect(community.requests, isEmpty);
  });

  test(
    'untrusted certificate is rejected before a credential body reaches server',
    () async {
      api.close();
      api = HttpAuthApi(
        communityBaseUri: community.uri,
        verifierBaseUri: verifier.uri,
        client: HttpClient(context: SecurityContext(withTrustedRoots: false)),
      );
      community.respond = (r) => _json(r, 201, _session(), session: true);
      await expectLater(
        api.login(
          username: 'private_user',
          password: 'private password',
          installationId: _cInstallation,
          idempotencyKey: _key,
        ),
        throwsA(_failure(AuthFailureKind.unknownOutcome)),
      );
      expect(community.requests, isEmpty);
    },
  );

  test(
    'reset intent one-time recovery code and no-secret commits are typed',
    () async {
      community.respond = (r) async {
        if (r.uri.path.endsWith('password-resets')) {
          r.response.statusCode = 204;
          await r.response.close();
        } else {
          await _json(r, 201, {
            'resetIntentId': _flow,
            'expiresAt': _expiry,
            'username': 'private_user',
            'newRecoveryCode': _code,
          });
        }
      };
      final intent = await api.createCodeResetIntent(_code);
      expect(intent.newRecoveryCode, _code);
      await api.commitPasswordReset(
        resetIntentId: _flow,
        newPassword: 'a different private password',
        newRecoveryCodeConfirmation: _code,
        idempotencyKey: _key,
      );
      expect(
        community.requests[0].headers.containsKey('idempotency-key'),
        isFalse,
      );
      expect(community.requests[1].headers['idempotency-key'], _key);
      expect(
        community.requests[1].headers.containsKey('authorization'),
        isFalse,
      );
    },
  );

  test(
    '401 invalidates authentication while 503 stays an unknown result',
    () async {
      community.respond = (r) => _json(r, 401, _error('session_replaced'));
      await expectLater(
        api.currentSession(_token),
        throwsA(
          _failure(
            AuthFailureKind.unauthorized,
            status: 401,
            code: 'session_replaced',
          ),
        ),
      );
      community.respond = (r) => _json(r, 503, _error('SERVICE_UNAVAILABLE'));
      try {
        await api.currentSession(_token);
        fail('Expected unavailable');
      } on AuthFailure catch (error) {
        expect(error.kind, AuthFailureKind.unavailable);
        expect(error.uncertain, isTrue);
        expect(error.toString(), isNot(contains(_token)));
      }
      community.respond = (r) async {
        r.response.statusCode = 401;
        r.response.headers.contentType = ContentType.html;
        r.response.write('<html>$_token</html>');
        await r.response.close();
      };
      await expectLater(
        api.currentSession(_token),
        throwsA(_failure(AuthFailureKind.unauthorized, status: 401)),
      );
    },
  );

  test(
    'unrecognized error contracts cannot establish a terminal mutation result',
    () async {
      community.respond = (r) => _json(r, 409, _error('UNREVIEWED_CODE'));
      await expectLater(
        api.login(
          username: 'private_user',
          password: 'private password',
          installationId: _cInstallation,
          idempotencyKey: _key,
        ),
        throwsA(_failure(AuthFailureKind.invalidResponse, status: 409)),
      );
      community.respond = (r) => _json(r, 410, _error('RESULT_EXPIRED'));
      try {
        await api.passwordResetResult(
          resetIntentId: _flow,
          idempotencyKey: _key,
        );
        fail('Expected expired result');
      } on AuthFailure catch (error) {
        expect(error.resultsExpired, isTrue);
        expect(error.statusCode, 410);
      }
    },
  );

  test('responses reject duplicate keys unknown fields null malformed UTF8 and oversized bodies', () async {
    final badBodies = [
      '{"accountId":"$_account","username":"private_user","expiresAt":"$_expiry","username":"other_user"}',
      '{"accountId":"$_account","username":"private_user","expiresAt":"$_expiry","email":"private@hainanu.edu.cn"}',
      '{"accountId":"$_account","username":null,"expiresAt":"$_expiry"}',
      '{"accountId":"$_account","username":"private_user","expiresAt":"2026-02-31T00:00:00Z"}',
      '${jsonEncode({'accountId': _account, 'username': 'private_user', 'expiresAt': _expiry})} false',
    ];
    for (final body in badBodies) {
      community.respond = (r) async {
        r.response.headers.set('Session-Expires-At', _expiry);
        r.response.write(body);
        await r.response.close();
      };
      await expectLater(
        api.currentSession(_token),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
    }
    community.respond = (r) async {
      r.response.add([0xff, 0xfe]);
      await r.response.close();
    };
    await expectLater(
      api.currentSession(_token),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
    community.respond = (r) async {
      r.response.write('x' * 32769);
      await r.response.close();
    };
    await expectLater(
      api.currentSession(_token),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
  });

  test(
    'missing no-store or mismatched expiry never yields a session',
    () async {
      community.respond = (r) async {
        r.response.headers.removeAll(HttpHeaders.cacheControlHeader);
        await _json(r, 201, _session(), session: true);
      };
      await expectLater(
        api.login(
          username: 'private_user',
          password: 'private password',
          installationId: _cInstallation,
          idempotencyKey: _key,
        ),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
      community.respond = (r) async {
        r.response.headers.set('Session-Expires-At', '2026-10-31T10:00:00Z');
        await _json(r, 201, _session());
      };
      await expectLater(
        api.login(
          username: 'private_user',
          password: 'private password',
          installationId: _cInstallation,
          idempotencyKey: _key,
        ),
        throwsA(_failure(AuthFailureKind.invalidResponse)),
      );
    },
  );

  test(
    'redirect never sends an auth capability or request body to another origin',
    () async {
      community.respond = (r) async {
        r.response.statusCode = 307;
        r.response.headers.set(
          HttpHeaders.locationHeader,
          '${verifier.uri}/stolen',
        );
        r.response.write(jsonEncode(_error('SERVICE_UNAVAILABLE')));
        await r.response.close();
      };
      verifier.respond = (r) => _json(r, 200, {'stolen': true});
      await expectLater(
        api.requestClosure(
          sessionToken: _token,
          password: 'private password',
          closureId: _flow,
          statusDigest: AuthCrypto.closureStatusDigest(_key),
        ),
        throwsA(
          _failure(
            AuthFailureKind.unknownOutcome,
            status: 307,
            code: 'SERVICE_UNAVAILABLE',
          ),
        ),
      );
      expect(verifier.requests, isEmpty);
      expect(community.requests, hasLength(1));
    },
  );

  test(
    'timeout remains uncertain and transport never retries the mutation',
    () async {
      api.close();
      final context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(utf8.encode(_certificate));
      final client = HttpClient(context: context)
        ..badCertificateCallback = (certificate, host, port) =>
            host == '127.0.0.1' &&
            (port == community.server.port || port == verifier.server.port) &&
            certificate.pem.trim() == _certificate.trim();
      api = HttpAuthApi(
        communityBaseUri: community.uri,
        verifierBaseUri: verifier.uri,
        client: client,
        timeout: const Duration(milliseconds: 250),
      );
      community.respond = (r) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await _json(r, 201, _session(), session: true);
      };
      await expectLater(
        api.login(
          username: 'private_user',
          password: 'private password',
          installationId: _cInstallation,
          idempotencyKey: _key,
        ),
        throwsA(_failure(AuthFailureKind.timeout)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(community.requests, hasLength(1));
      expect(verifier.requests, isEmpty);
    },
  );

  test('invalid byte encodings and exact mailbox spelling are rejected before sending', () async {
    await expectLater(
      api.currentSession('$_token='),
      throwsA(_failure(AuthFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    await expectLater(
      api.requestOtp(
        email: ' user@hainanu.edu.cn',
        installationId: _vInstallation,
        idempotencyKey: _key,
      ),
      throwsA(_failure(AuthFailureKind.rejected, code: 'CLIENT_INPUT_INVALID')),
    );
    expect(community.requests, isEmpty);
    expect(verifier.requests, isEmpty);
  });
}

// Public, synthetic loopback-only test credentials. Never deployment material.
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
