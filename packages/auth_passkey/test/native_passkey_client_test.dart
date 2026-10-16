import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

String encoded(int count, [int value = 7]) =>
    base64Url.encode(List.filled(count, value)).replaceAll('=', '');
Map<String, dynamic> getOptions() => {
  'challenge': encoded(32), 'rpId': 'auth.example.invalid',
  'timeout': 60000, 'userVerification': 'required',
};
Map<String, dynamic> createOptions() => {
  'challenge': encoded(32), 'timeout': 60000,
  'rp': {'id': 'auth.example.invalid', 'name': 'Hnuhole'},
  'user': {'id': encoded(32, 9), 'name': encoded(32, 9), 'displayName': 'Hnuhole account'},
  'pubKeyCredParams': [{'type': 'public-key', 'alg': -7}],
  'excludeCredentials': <dynamic>[],
  'authenticatorSelection': {'residentKey': 'required', 'requireResidentKey': true, 'userVerification': 'required'},
  'attestation': 'none',
};
Map<String, dynamic> credential({bool create = false}) => {
  'id': encoded(16), 'rawId': encoded(16), 'type': 'public-key',
  'response': create ? <String, dynamic>{'clientDataJSON': encoded(40), 'attestationObject': encoded(100)} :
      <String, dynamic>{'clientDataJSON': encoded(40), 'authenticatorData': encoded(37), 'signature': encoded(72), 'userHandle': encoded(32, 9)},
  'clientExtensionResults': <String, dynamic>{},
};
Matcher fails(String code) => throwsA(isA<PasskeyFailure>().having((value) => value.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hnuhole/auth_passkey_test');
  late NativePasskeyClient client;
  setUp(() { client = NativePasskeyClient(channel: channel, platform: TargetPlatform.android); });
  tearDown(() { TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null); });

  test('create passes fixed server policy and preserves signed fields', () async {
    final options = createOptions();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'create');
      expect(jsonDecode((call.arguments as Map)['publicKey'] as String), options);
      return jsonEncode(credential(create: true));
    });
    expect(await client.create(options), credential(create: true));
  });
  test('get discovers a credential without a username or allow list', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final options = jsonDecode((call.arguments as Map)['publicKey'] as String) as Map;
      expect(options.containsKey('allowCredentials'), isFalse);
      expect(options.containsKey('user'), isFalse);
      return jsonEncode(credential());
    });
    expect(await client.get(getOptions()), credential());
  });
  test('unsafe creation policy fails before native work starts', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async { ++calls; return null; });
    final mutations = <void Function(Map<String, dynamic>)>[
      (value) => value['origin'] = 'https://auth.example.invalid',
      (value) => value['attestation'] = 'direct',
      (value) => (value['authenticatorSelection'] as Map)['userVerification'] = 'preferred',
      (value) => (value['authenticatorSelection'] as Map)['residentKey'] = 'preferred',
      (value) => (value['user'] as Map)['name'] = 'private_username',
      (value) => (value['pubKeyCredParams'] as List).add({'type': 'public-key', 'alg': -257}),
      (value) => value['challenge'] = '${encoded(32)}=',
      (value) => (value['rp'] as Map)['id'] = '127.0.0.1',
      (value) => (value['rp'] as Map)['id'] = 'auth.example.invalid\n',
    ];
    for (final mutate in mutations) {
      final options = createOptions(); mutate(options);
      await expectLater(client.create(options), fails('PASSKEY_INVALID_OPTIONS'));
    }
    expect(calls, 0);
  });
  test('recovery refuses a caller-provided allow list', () async {
    await expectLater(client.get({...getOptions(), 'allowCredentials': []}), fails('PASSKEY_INVALID_OPTIONS'));
  });
  test('invalid platform responses never reach callers', () async {
    final mutations = <void Function(Map<String, dynamic>)>[
      (value) => value['rawId'] = encoded(16, 8),
      (value) => value['authenticatorAttachment'] = 'platform',
      (value) => value['clientExtensionResults'] = {'appid': true},
      (value) => (value['response'] as Map)['userHandle'] = null,
      (value) => (value['response'] as Map)['userHandle'] = encoded(31),
      (value) => (value['response'] as Map)['authenticatorData'] = encoded(36),
      (value) => (value['response'] as Map)['clientDataJSON'] = encoded(3073),
    ];
    for (final mutate in mutations) {
      final response = credential(); mutate(response);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => jsonEncode(response));
      await expectLater(client.get(getOptions()), fails('PASSKEY_INVALID_RESPONSE'));
    }
  });
  test('cancel suppresses late success and does not expose its credential', () async {
    final completion = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') return null;
      return completion.future;
    });
    final first = client.get(getOptions());
    final assertion = expectLater(first, fails('PASSKEY_CANCELLED'));
    await client.cancel();
    completion.complete(jsonEncode(credential()));
    await assertion;
  });
  test('a second operation is busy until the first has settled', () async {
    final completion = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) => completion.future);
    final first = client.get(getOptions());
    await expectLater(client.create(createOptions()), fails('PASSKEY_BUSY'));
    completion.complete(jsonEncode(credential()));
    await first;
  });
  test('known cancellation is retained and provider details are discarded', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'PASSKEY_CANCELLED', message: 'synthetic private data', details: 'synthetic assertion');
    });
    await expectLater(client.get(getOptions()), fails('PASSKEY_CANCELLED'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'PROVIDER_SECRET', details: 'synthetic private data');
    });
    await expectLater(client.get(getOptions()), fails('PASSKEY_FAILED'));
  });
  test('a missing plugin and unsupported platform fail closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await expectLater(client.get(getOptions()), fails('PASSKEY_UNAVAILABLE'));
    await expectLater(NativePasskeyClient(channel: channel, platform: TargetPlatform.linux).get(getOptions()), fails('PASSKEY_UNAVAILABLE'));
  });
}
