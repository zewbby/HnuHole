import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hnuhole/auth_vault');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'native boundary forwards exact namespace and awaits write acknowledgment',
    () async {
      String? value;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'read') return value;
        value = (call.arguments as Map)['value'] as String;
        return null;
      });
      final vault = DurableAuthVault('deployment.test');
      expect(await vault.read(), isNull);
      await vault.write('opaque state');
      expect(await vault.read(), 'opaque state');
      expect(calls.map((e) => e.method), ['read', 'write', 'read']);
      for (final call in calls) {
        expect((call.arguments as Map)['namespace'], 'deployment.test');
      }
    },
  );
  test('unsupported namespace rejected before native dispatch', () {
    for (final namespace in ['', 'a/b', 'a b', 'a' * 129]) {
      expect(() => DurableAuthVault(namespace), throwsArgumentError);
    }
  });
  test('platform failures reach caller without fallback', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'AUTH_STORAGE_UNAVAILABLE'),
    );
    final vault = DurableAuthVault('deployment.test');
    await expectLater(vault.read(), throwsA(isA<PlatformException>()));
    await expectLater(vault.write('state'), throwsA(isA<PlatformException>()));
  });
  test('parsed workflow records cannot grant unpersisted permission', () {
    final wire = AuthCrypto.encode(List<int>.filled(32, 1));
    final state = AuthState.parse(
      jsonDecode(
        jsonEncode(
          AuthState(
            pendingReset: {
              'v': 1,
              'intentId': wire,
              'key': wire,
              'state': 'UNKNOWN',
            },
          ).toJson('test'),
        ),
      ) as Map<String, dynamic>,
      'test',
    );
    expect(
      () => state.pendingReset!['state'] = 'COMMITTED',
      throwsUnsupportedError,
    );
  });
  test('desktop adapter refuses authentication storage instead of plaintext fallback', () async {
    await expectLater(
      FlutterAuthVault().read(),
      throwsA(isA<AuthStorageFailure>()),
    );
  });
}
