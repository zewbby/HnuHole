import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/config/mobile_environment.dart';

void main() {
  test('valid origins preserve the historical URI scope exactly', () {
    for (final c in [
      'https://community.example',
      'https://community.example/',
      'https://community.example:8443/',
    ]) {
      final community = Uri.parse(c);
      final verifier = Uri.parse('https://verifier.example:9443');
      final environment = MobileEnvironment(
        communityBaseUri: community,
        verifierBaseUri: verifier,
      );
      expect(
        environment.storageScope,
        'hnuhole.isolated.auth.v1|$community|$verifier',
      );
      expect(environment.communityBaseUri, same(community));
    }
  });

  test('rejects invalid origins on either authority before store access', () {
    final valid = Uri.parse('https://community.example');
    for (final value in [
      'http://example.test',
      'https://',
      'https://user:password@example.test',
      'https://example.test/api',
      'https://example.test?scope=other',
      'https://example.test#other',
      'https://example.test:0',
      'https://example.test:65536',
    ]) {
      final invalid = Uri.parse(value);
      expect(
        () => MobileEnvironment(
          communityBaseUri: invalid,
          verifierBaseUri: valid,
        ),
        throwsArgumentError,
      );
      expect(
        () => MobileEnvironment(
          communityBaseUri: valid,
          verifierBaseUri: invalid,
        ),
        throwsArgumentError,
      );
    }
  });
}
