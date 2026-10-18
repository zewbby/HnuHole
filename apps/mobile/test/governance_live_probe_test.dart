import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';

import 'loopback_tls_fixture.dart';

void main() {
  const post = '11111111-1111-4111-8111-111111111111';
  const identity = '22222222-2222-4222-8222-222222222222';
  const caseId = '33333333-3333-4333-8333-333333333333';
  const fence = '44444444-4444-4444-8444-444444444444';
  const notice = '55555555-5555-4555-8555-555555555555';
  final token = AuthCrypto.encode(List.filled(32, 5)),
      requestId = AuthCrypto.encode(List.filled(16, 7));
  late LoopbackTlsFixture tls;
  late HttpServer server;
  late Directory temporary;
  Map<String, dynamic>? submitted;
  late List<String> requests;
  setUp(() async {
    tls = await LoopbackTlsFixture.create();
    temporary = await Directory.systemTemp.createTemp(
      'hnuhole-governance-probe-',
    );
    requests = [];
    submitted = null;
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChainBytes(utf8.encode(tls.certificate))
        ..usePrivateKeyBytes(utf8.encode(tls.privateKey)),
    );
    server.listen((request) async {
      try {
        requests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('X-Request-ID', requestId);
        request.response.headers.set('Cache-Control', 'no-store');
        Object body;
        var status = 200;
        if (request.uri.path == '/api/v1/system-notifications') {
          expect(request.uri.queryParameters['identityId'], identity);
          body = {
            'items': [
              {
                'id': notice,
                'eventId': 'report:${submitted!['id']}:submitted',
                'source': 'SERVER',
                'scope': 'IDENTITY',
                'identityId': identity,
                'kind': 'REPORT_PROGRESS',
                'state': 'PENDING',
                'title': '举报已提交，等待处理',
                // The actual Go DTO permits an empty pending explanation/body.
                'body': '', 'createdAt': '2026-10-18T00:00:00Z', 'readAt': null,
                'route': {'name': 'REPORT', 'resourceId': submitted!['id']},
              },
            ],
            'nextBefore': null,
          };
        } else if (request.method == 'GET') {
          body = submitted == null
              ? {'state': 'NOT_SUBMITTED', 'retryToken': fence}
              : {'state': 'SUBMITTED', 'report': submitted};
        } else {
          final raw = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          if (raw['retryToken'] != fence) {
            status = 409;
            body = {
              'error': {'code': 'REPORT_ATTEMPT_SEALED', 'message': 'sealed'},
              'requestId': requestId,
            };
          } else {
            expect(request.headers.value('authorization'), 'Bearer $token');
            submitted = {
              'id': request.uri.path.split('/').last,
              'caseId': caseId,
              'postId': post,
              'reason': raw['reason'],
              'description': raw['description'],
              'state': 'PENDING',
              'createdAt': '2026-10-18T00:00:00Z',
              'outcome': '',
              'explanation': '',
            };
            body = {'state': 'SUBMITTED', 'report': submitted};
          }
        }
        request.response.statusCode = status;
        if (status == 200) {
          request.response.headers.set(
            'Session-Expires-At',
            '2031-01-01T00:00:00Z',
          );
        }
        request.response.write(jsonEncode(body));
        await request.response.close();
      } on Object {
        /* Untrusted TLS clients may disconnect before HTTP. */
      }
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await tls.dispose();
    await temporary.delete(recursive: true);
  });
  Future<ProcessResult> run(String certificate, String suffix) async {
    final fixture = File('${temporary.path}/fixture-$suffix.json');
    await fixture.writeAsString(
      jsonEncode({
        'url': 'https://127.0.0.1:${server.port}',
        'certificatePem': certificate,
        'reporterToken': token,
        'reporterIdentityId': identity,
        'postId': post,
      }),
    );
    var dart = Platform.environment['HNUHOLE_PROBE_DART'];
    if (dart == null) {
      final config = File(
        '${Directory.current.path}/.dart_tool/package_config.json',
      );
      final data = jsonDecode(await config.readAsString()) as Map;
      final flutter = (data['packages'] as List).cast<Map>().singleWhere(
        (p) => p['name'] == 'flutter',
      );
      final root = Directory.fromUri(
        config.uri.resolve(flutter['rootUri'] as String),
      ).parent.parent;
      dart =
          '${root.path}/bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}';
    }
    return Process.run(dart, [
      '--packages=${Directory.current.path}/.dart_tool/package_config.json',
      '${Directory.current.path}/integration/governance_live_probe.dart',
      fixture.path,
      'report',
      '${temporary.path}/result-$suffix.json',
    ]);
  }

  test('pure Dart VM report probe exercises pinned TLS, fenced retry and empty-body notice DTO', () async {
    final result = await run(tls.certificate, 'trusted');
    expect(result.exitCode, 0, reason: result.stderr as String);
    expect((result.stdout as String).trim(), 'PASS report');
    expect(result.stderr, isEmpty);
    final output = jsonDecode(
      await File('${temporary.path}/result-trusted.json').readAsString(),
    ) as Map;
    expect(output['caseId'], caseId);
    expect(output['requestId'], submitted!['id']);
    expect(requests.map((r) => r.split(' ').first), [
      'GET',
      'PUT',
      'PUT',
      'GET',
      'GET',
    ]);
    expect(result.stdout, isNot(contains(token)));
  });
  test(
    'pure Dart VM probe rejects an untrusted fixture CA without fallback',
    () async {
      final another = await LoopbackTlsFixture.create();
      try {
        final result = await run(another.certificate, 'untrusted');
        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect((result.stderr as String).trim(), 'FAIL report');
        expect(requests, isEmpty);
        final output = jsonDecode(
          await File('${temporary.path}/result-untrusted.json').readAsString(),
        ) as Map;
        expect(output['status'], 'FAIL');
        expect(output['step'], 'report_original_not_submitted');
      } finally {
        await another.dispose();
      }
    },
  );
}
