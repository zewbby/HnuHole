import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/development/app_transport.dart';

void main() {
  final c = Uri.parse('https://127.0.0.1:8443');
  final v = Uri.parse('https://127.0.0.1:8444');
  test(
    'development RP needs explicit debug trust and independent loopback APIs',
    () {
      expect(
        developmentPasskeyRp(
          community: c,
          verifier: v,
          rp: '',
          developmentCa: '',
        ),
        isNull,
      );
      expect(
        developmentPasskeyRp(
          community: c,
          verifier: v,
          rp: 'zewbby.github.io',
          developmentCa: 'explicit-development-certificate',
        ),
        'zewbby.github.io',
      );
      expect(
        () => developmentPasskeyRp(
          community: c,
          verifier: v,
          rp: 'zewbby.github.io',
          developmentCa: '',
        ),
        throwsStateError,
      );
      expect(
        () => developmentPasskeyRp(
          community: Uri.parse('https://community.example.com'),
          verifier: v,
          rp: 'zewbby.github.io',
          developmentCa: 'explicit-development-certificate',
        ),
        throwsArgumentError,
      );
    },
  );
  test('development trust is confined to separate loopback HTTPS origins', () {
    validateDevelopmentOrigins(c, v);
    for (final invalid in [
      'http://127.0.0.1:8443',
      'https://api.example.com:8443',
      'https://127.0.0.1',
      'https://127.0.0.1:443',
      'https://user@127.0.0.1:8443',
      'https://127.0.0.1:8443/api',
      'https://127.0.0.1:8443?ca=1',
      'https://127.0.0.1:8443#ca',
    ]) {
      expect(
        () => validateDevelopmentOrigins(Uri.parse(invalid), v),
        throwsArgumentError,
      );
    }
    expect(() => validateDevelopmentOrigins(c, c), throwsArgumentError);
  });
  test('absent development CA leaves normal trust available', () {
    final client = createAppHttpClient(
      community: Uri.parse('https://community.example.com'),
      verifier: Uri.parse('https://verifier.example.com'),
      developmentCa: '',
    );
    client.close(force: true);
  });
  test('malformed development certificate fails instead of bypassing TLS', () {
    expect(
      () => createAppHttpClient(
        community: c,
        verifier: v,
        developmentCa: 'bm90IGEgY2VydGlmaWNhdGU=',
      ),
      throwsA(anything),
    );
  });
}
