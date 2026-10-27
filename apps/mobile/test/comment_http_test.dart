import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';

import 'loopback_tls_fixture.dart';

void main() {
  test('canonical underscore command keys traverse the real protected TLS transport', () async {
    final tls = await LoopbackTlsFixture.create();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChainBytes(utf8.encode(tls.certificate))
        ..usePrivateKeyBytes(utf8.encode(tls.privateKey)),
    );
    final received = <String>[];
    final receivedNonces = <String?>[];
    final key = AuthCrypto.encode(List.filled(16, 255));
    expect(key, contains('_'));
    server.listen((r) async {
      received.add(r.uri.path);
      receivedNonces.add(r.headers.value('X-Comment-Snapshot-Request'));
      await r.drain<void>();
      r.response.headers.contentType = ContentType.json;
      r.response.headers.set(
        'X-Request-ID',
        AuthCrypto.encode(List.filled(16, 3)),
      );
      r.response.headers.set('Cache-Control', 'no-store');
      r.response.headers.set('Server-Time', '2026-10-19T00:00:00Z');
      r.response.headers.set('Session-Expires-At', '2026-10-20T00:00:00Z');
      r.response.write(jsonEncode({'state': 'UNKNOWN_NOT_OBSERVED'}));
      await r.response.close();
    });
    final transport = CommentHttp(
      Uri.parse('https://127.0.0.1:${server.port}'),
      client: HttpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificatesBytes(utf8.encode(tls.certificate)),
      ),
    );
    try {
      final r = await transport.send(
        AuthCrypto.encode(List.filled(32, 4)),
        'GET',
        '/api/v1/comment-commands/$key',
      );
      expect(r.value['state'], 'UNKNOWN_NOT_OBSERVED');
      expect(received, ['/api/v1/comment-commands/$key']);
      const path =
          '/api/v1/posts/11111111-1111-4111-8111-111111111111/comments';
      await transport.send(
        AuthCrypto.encode(List.filled(32, 4)),
        'GET',
        path,
        snapshotRequest: key,
      );
      expect(receivedNonces, [null, key]);
      await expectLater(
        transport.send(
          AuthCrypto.encode(List.filled(32, 4)),
          'GET',
          path,
          query: {'cursor': 'old'},
          snapshotRequest: key,
        ),
        throwsFormatException,
      );
      expect(received.length, 2);
    } finally {
      transport.close();
      await server.close(force: true);
      await tls.dispose();
    }
  });
}
