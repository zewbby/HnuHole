import 'dart:io';

/// Fresh loopback-only TLS material; no reusable private key is stored in Git.
class LoopbackTlsFixture {
  LoopbackTlsFixture._(this._directory, this.certificate, this.privateKey);

  final Directory _directory;
  final String certificate, privateKey;

  static Future<LoopbackTlsFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'hnuhole-test-tls-',
    );
    try {
      final config = File('${directory.path}/openssl.cnf');
      await config.writeAsString('[req]\ndistinguished_name=dn\n[dn]\n');
      final certificate = File('${directory.path}/certificate.pem');
      final key = File('${directory.path}/key.pem');
      final executable =
          Platform.environment['HNUHOLE_TEST_OPENSSL'] ?? 'openssl';
      final result = await Process.run(executable, [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-sha256',
        '-nodes',
        '-days',
        '1',
        '-config',
        config.path,
        '-subj',
        '/CN=127.0.0.1',
        '-addext',
        'subjectAltName=IP:127.0.0.1',
        '-keyout',
        key.path,
        '-out',
        certificate.path,
      ]);
      if (result.exitCode != 0) {
        throw StateError(
          'Loopback TLS fixture generation failed; check OpenSSL availability.',
        );
      }
      return LoopbackTlsFixture._(
        directory,
        await certificate.readAsString(),
        await key.readAsString(),
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() => _directory.delete(recursive: true);
}
