import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';
import 'loopback_tls_fixture.dart';

void main() {
  late LoopbackTlsFixture tls;
  late HttpServer server;
  late HttpGovernanceApi api;
  late Future<void> Function(HttpRequest) respond;
  final received = <Map<String, Object?>>[];
  final requestId = AuthCrypto.encode(List.filled(16, 3));
  const expiry = '2031-01-01T00:00:00Z';
  setUpAll(() async {
    tls = await LoopbackTlsFixture.create();
  });
  tearDownAll(() async {
    await tls.dispose();
  });
  setUp(() async {
    received.clear();
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChainBytes(utf8.encode(tls.certificate))
        ..usePrivateKeyBytes(utf8.encode(tls.privateKey)),
    );
    server.listen((request) async {
      try {
        final bytes = await request.fold<List<int>>(
          [],
          (bytes, next) => bytes..addAll(next),
        );
        received.add({
          'method': request.method,
          'path': request.uri.path,
          'authorization': request.headers.value('authorization'),
          'body': utf8.decode(bytes),
        });
        request.response.headers.set('X-Request-ID', requestId);
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.contentType = ContentType.json;
        await respond(request);
      } on Object {
        /* An aborted client is an expected transport failure. */
      }
    });
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(utf8.encode(tls.certificate)),
    );
    api = HttpGovernanceApi(
      baseUri: Uri.parse('https://127.0.0.1:${server.port}'),
      client: client,
      timeout: const Duration(seconds: 3),
    );
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });
  Future<void> json(
    HttpRequest request,
    Object body, {
    int status = 200,
    bool renewal = true,
  }) async {
    request.response.statusCode = status;
    if (renewal) request.response.headers.set('Session-Expires-At', expiry);
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  test('HTTPS request carries Bearer and persists no cookies', () async {
    respond = (r) => json(r, {'items': <Object>[], 'nextBefore': null});
    final result = await api.request(
      identityTestToken,
      'GET',
      '/api/v1/system-notifications',
    );
    expect(result.expiresAt, DateTime.parse(expiry));
    expect(received.single['authorization'], 'Bearer $identityTestToken');
    expect(received.single['body'], '');
  });
  test('redirect never follows a response-selected endpoint', () async {
    respond = (r) async {
      r.response.statusCode = 302;
      r.response.headers.set('Location', '/api/v1/appeals/anything');
      await r.response.close();
    };
    await expectLater(
      api.request(identityTestToken, 'GET', '/api/v1/system-notifications'),
      throwsA(isA<GovernanceFailure>()),
    );
    expect(received.length, 1);
  });
  test('missing session deadline is uncertain and never accepted', () async {
    respond = (r) => json(r, {'items': <Object>[]}, renewal: false);
    await expectLater(
      api.request(identityTestToken, 'GET', '/api/v1/system-notifications'),
      throwsA(
        isA<GovernanceFailure>().having((e) => e.uncertain, 'uncertain', true),
      ),
    );
  });
  test(
    'duplicate JSON fields are rejected before interpreting result',
    () async {
      respond = (r) async {
        r.response.headers.set('Session-Expires-At', expiry);
        r.response.write('{"state":"SUBMITTED","state":"NOT_SUBMITTED"}');
        await r.response.close();
      };
      await expectLater(
        api.request(
          identityTestToken,
          'GET',
          '/api/v1/reports/11111111-1111-4111-8111-111111111111',
        ),
        throwsA(isA<GovernanceFailure>()),
      );
    },
  );
  test(
    'malformed 401 retains authoritative revocation classification',
    () async {
      respond = (r) async {
        r.response.statusCode = 401;
        r.response.write('{');
        await r.response.close();
      };
      await expectLater(
        api.request(identityTestToken, 'GET', '/api/v1/system-notifications'),
        throwsA(
          isA<GovernanceFailure>().having((e) => e.status, 'revoked', 401),
        ),
      );
    },
  );
  test('cacheable response and cookie injection are rejected', () async {
    respond = (r) async {
      r.response.headers.set('Cache-Control', 'public');
      await json(r, {'items': <Object>[]});
    };
    await expectLater(
      api.request(identityTestToken, 'GET', '/api/v1/system-notifications'),
      throwsA(isA<GovernanceFailure>()),
    );
    respond = (r) async {
      r.response.headers.set('Set-Cookie', 'unexpected=secret');
      await json(r, {'items': <Object>[]});
    };
    await expectLater(
      api.request(identityTestToken, 'GET', '/api/v1/system-notifications'),
      throwsA(isA<GovernanceFailure>()),
    );
  });
  test(
    'error request id must match and failed operations cannot renew session',
    () async {
      respond = (r) => json(r, {
        'error': {'code': 'REPORT_CONFLICT', 'message': 'conflict'},
        'requestId': requestId,
      }, status: 409);
      await expectLater(
        api.request(
          identityTestToken,
          'PUT',
          '/api/v1/reports/11111111-1111-4111-8111-111111111111',
          body: {},
        ),
        throwsA(
          isA<GovernanceFailure>().having(
            (e) => e.code,
            'invalid renewal',
            'INVALID_RESPONSE',
          ),
        ),
      );
      respond = (r) => json(
        r,
        {
          'error': {'code': 'REPORT_CONFLICT', 'message': 'conflict'},
          'requestId': 'wrong',
        },
        status: 409,
        renewal: false,
      );
      await expectLater(
        api.request(
          identityTestToken,
          'PUT',
          '/api/v1/reports/11111111-1111-4111-8111-111111111111',
          body: {},
        ),
        throwsA(
          isA<GovernanceFailure>().having(
            (e) => e.code,
            'request mismatch',
            'INVALID_RESPONSE',
          ),
        ),
      );
    },
  );
  test('restricted credential never enters normal session and is cleared on logout', () async {
    final vault = IdentityTestVault(),
        authVault = IdentityTestVault(),
        ordinary = AuthStore(IdentityTestVault());
    final access = ModerationAccess(api: api, vault: vault);
    addTearDown(access.dispose);
    addTearDown(ordinary.dispose);
    respond = (r) async {
      if (r.uri.path.endsWith('session-revocations')) {
        r.response.statusCode = 204;
        await r.response.close();
        return;
      }
      await json(
        r,
        {
          'sessionToken': identityTestToken,
          'expiresAt': expiry,
          'scope': 'MODERATION_SELF',
          'moderationSubject': AuthCrypto.encode(List.filled(32, 9)),
        },
        status: 201,
        renewal: false,
      );
    };
    expect(
      await access.login('private_user', 'never-store-this-password'),
      isTrue,
    );
    expect(access.token, identityTestToken);
    expect(vault.value, contains('MODERATION_SELF'));
    expect(vault.value, isNot(contains('never-store-this-password')));
    expect(ordinary.current?.session, isNull);
    expect(authVault.value, isNull);
    expect(received.first['authorization'], isNull);
    await access.clear();
    expect(access.token, isNull);
    expect(vault.value, isNot(contains(identityTestToken)));
    expect(
      received.last['path'],
      '/api/v1/moderation-access/session-revocations',
    );
  });
  test(
    'restricted scope mismatch does not save or expose capability',
    () async {
      final vault = IdentityTestVault(),
          access = ModerationAccess(api: api, vault: IdentityTestVault());
      addTearDown(access.dispose);
      respond = (r) => json(
        r,
        {
          'sessionToken': identityTestToken,
          'expiresAt': expiry,
          'scope': 'ADMIN',
          'moderationSubject': AuthCrypto.encode(List.filled(32, 9)),
        },
        status: 201,
        renewal: false,
      );
      expect(await access.login('private_user', 'password'), isFalse);
      expect(access.token, isNull);
      expect(vault.value, isNull);
    },
  );
  test('restricted subject remains server-bound and cannot call reports or identities', () async {
    final auth = await IdentityTestFixture.create();
    addTearDown(auth.dispose);
    await auth.sessions.logout();
    final subject = AuthCrypto.encode(List.filled(32, 7));
    final access = ModerationAccess(api: api, vault: IdentityTestVault());
    addTearDown(access.dispose);
    respond = (r) async {
      if (r.uri.path == '/api/v1/moderation-access/sessions') {
        await json(
          r,
          {
            'sessionToken': identityTestToken,
            'moderationSubject': subject,
            'expiresAt': expiry,
            'scope': 'MODERATION_SELF',
          },
          status: 201,
          renewal: false,
        );
      } else {
        await json(r, {'items': <Object>[], 'nextBefore': null});
      }
    };
    final controller = GovernanceController(
      api: api,
      sessions: auth.sessions,
      authStore: auth.store,
      identitiesApi: auth.api,
      pendingStore: GovernancePendingStore(IdentityTestVault()),
      restrictedAccess: access,
    );
    addTearDown(controller.dispose);
    expect(await access.login('private_user', 'password'), isTrue);
    expect(controller.accountId, subject);
    expect(controller.restricted, isTrue);
    await controller.loadIdentities();
    expect(auth.api.reads, 0);
    await controller.loadNotifications();
    expect(received.last['authorization'], 'Bearer $identityTestToken');
    final count = received.length;
    expect(
      await controller.submitReport(
        postId: identityTestId,
        identityId: null,
        reason: 'OTHER',
        description: '',
        images: [],
      ),
      isFalse,
    );
    expect(
      await controller.readResource(
        const NotificationRoute('REPORT', identityTestId),
      ),
      isNull,
    );
    expect(received.length, count);
    expect(auth.store.current?.session, isNull);
  });
}
